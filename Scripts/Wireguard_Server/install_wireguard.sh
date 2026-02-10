#!/bin/bash

################################################################################
# WireGuard VPN Server Installation mit Web Interface
# Basierend auf: https://adminforge.de/linux-allgemein/vpn/wireguard-vpn-server-mit-web-interface-einrichten/
# Autor: Nepomuk Gail - ITM GmbH
# Version: 2.0
################################################################################

set -e  # Beende bei Fehler

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging-Funktion
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[FEHLER]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNUNG]${NC} $1"
}

# Funktion um den Fortschritt zu aktualisieren
show_progress() {
    local progress=$1
    local message=$2
    echo "$progress" | whiptail --title "WireGuard Installation" --gauge "$message" 8 70 0
}

# Prüfe ob als root ausgeführt wird
if [[ $EUID -ne 0 ]]; then
   error "Dieses Script muss als root ausgeführt werden!"
   exit 1
fi

# Installiere whiptail, falls nicht vorhanden
if ! command -v whiptail &> /dev/null; then
    log "Installiere whiptail..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -qq && apt install -y whiptail &> /dev/null
fi

# Vorschaufenster mit Logo anzeigen
whiptail --title "WireGuard Installation" --msgbox "
    ╔══════════════════════════════════════════╗
    ║                                          ║
    ║      WireGuard VPN Server Installer      ║
    ║                                          ║
    ║         Nepomuk Gail - ITM GmbH          ║
    ║                                          ║
    ║  Basierend auf adminForge Tutorial       ║
    ║                                          ║
    ╚══════════════════════════════════════════╝
    
    Dieses Script installiert:
    • WireGuard VPN Server
    • WireGuard Web UI (wireguard-ui)
    • Automatische Konfiguration
    • Systemd Services
    
    Drücken Sie OK zum Fortfahren
" 20 60

################################################################################
# PUNKT 1: Debian Pakete installieren
################################################################################
{
    show_progress 10 "Aktualisiere Paketliste..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -qq &> /dev/null
    
    show_progress 20 "Installiere WireGuard, Curl und Tar..."
    apt install -y wireguard curl tar &> /dev/null
    
    show_progress 25 "Pakete erfolgreich installiert!"
    sleep 1
} &
wait

log "✓ WireGuard und Abhängigkeiten installiert"

################################################################################
# PUNKT 2: Firewall Port öffnen (falls UFW installiert ist)
################################################################################
if command -v ufw &> /dev/null; then
    {
        show_progress 30 "Öffne Firewall Port 51820/udp..."
        ufw allow 51820/udp &> /dev/null || true
        show_progress 35 "Firewall konfiguriert!"
        sleep 1
    } &
    wait
    log "✓ UFW Firewall Port 51820/udp geöffnet"
else
    warning "UFW nicht installiert - bitte manuell Port 51820/udp öffnen!"
fi

################################################################################
# PUNKT 3: IP Forwarding aktivieren
################################################################################
{
    show_progress 40 "Aktiviere IP-Forwarding..."
    
    # Prüfe ob bereits aktiviert
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    if ! grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
    
    sysctl -p &> /dev/null
    
    show_progress 45 "IP-Forwarding aktiviert!"
    sleep 1
} &
wait

log "✓ IP Forwarding aktiviert"

################################################################################
# PUNKT 4: WireGuard UI Startscript erstellen
################################################################################
{
    show_progress 50 "Erstelle WireGuard UI Start-Skript..."
    
    mkdir -p /etc/wireguard
    
    cat <<'EOF' > /etc/wireguard/start-wgui.sh
#!/bin/bash

cd /etc/wireguard
./wireguard-ui -bind-address 0.0.0.0:5000
EOF
    
    chmod +x /etc/wireguard/start-wgui.sh
    
    show_progress 55 "Start-Skript erstellt!"
    sleep 1
} &
wait

log "✓ WireGuard UI Start-Skript erstellt"

################################################################################
# PUNKT 5: Systemd Service Unit für WireGuard UI anlegen
################################################################################
{
    show_progress 60 "Erstelle Systemd Service für WireGuard UI..."
    
    cat <<'EOF' > /etc/systemd/system/wgui-web.service
[Unit]
Description=WireGuard UI Web Interface
After=network.target

[Service]
Type=simple
ExecStart=/etc/wireguard/start-wgui.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    show_progress 65 "Systemd Service erstellt!"
    sleep 1
} &
wait

log "✓ Systemd Service wgui-web.service erstellt"

################################################################################
# PUNKT 6: WireGuard UI Update Script erstellen
################################################################################
{
    show_progress 70 "Erstelle WireGuard UI Update-Skript..."
    
    cat <<'EOF' > /etc/wireguard/update.sh
#!/bin/bash

set -e

VER=$(curl -sI https://github.com/ngoduykhanh/wireguard-ui/releases/latest | grep "location:" | cut -d "/" -f8 | tr -d '\r')

if [ -z "$VER" ]; then
    echo "Fehler: Konnte neueste Version nicht ermitteln"
    exit 1
fi

echo "Downloading wireguard-ui $VER"
curl -sL "https://github.com/ngoduykhanh/wireguard-ui/releases/download/$VER/wireguard-ui-$VER-linux-amd64.tar.gz" -o wireguard-ui-$VER-linux-amd64.tar.gz

echo -n "Extracting: "
tar xvf wireguard-ui-$VER-linux-amd64.tar.gz -C /etc/wireguard

# Aufräumen
rm -f wireguard-ui-$VER-linux-amd64.tar.gz

echo "Restarting wgui-web.service"
systemctl restart wgui-web.service

echo "Update abgeschlossen! Version: $VER"
EOF
    
    chmod +x /etc/wireguard/update.sh
    
    show_progress 75 "Update-Skript erstellt!"
    sleep 1
} &
wait

log "✓ WireGuard UI Update-Skript erstellt"

################################################################################
# PUNKT 7: WireGuard UI herunterladen und installieren
################################################################################
{
    show_progress 80 "Lade WireGuard UI herunter..."
    
    cd /etc/wireguard
    ./update.sh &> /tmp/wgui-install.log
    
    show_progress 85 "WireGuard UI heruntergeladen und extrahiert!"
    sleep 1
} &
wait

log "✓ WireGuard UI installiert"

################################################################################
# PUNKT 8: Systemd Units für automatischen WireGuard-Neustart erstellen
################################################################################
{
    show_progress 90 "Erstelle Überwachungsskripte für WireGuard..."
    
    cat <<'EOF' > /etc/systemd/system/wgui.service
[Unit]
Description=Restart WireGuard on config change
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart wg-quick@wg0.service

[Install]
RequiredBy=wgui.path
EOF

    cat <<'EOF' > /etc/systemd/system/wgui.path
[Unit]
Description=Watch /etc/wireguard/wg0.conf for changes

[Path]
PathModified=/etc/wireguard/wg0.conf

[Install]
WantedBy=multi-user.target
EOF
    
    show_progress 93 "Überwachungsskripte erstellt!"
    sleep 1
} &
wait

log "✓ Systemd Überwachungs-Units erstellt"

################################################################################
# PUNKT 9: Dienste aktivieren und starten
################################################################################
{
    show_progress 95 "Aktiviere und starte Dienste..."
    
    # Erstelle leere wg0.conf falls nicht vorhanden
    touch /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf
    
    # Systemd Daemon neu laden
    systemctl daemon-reload
    
    # Services aktivieren
    systemctl enable wgui.path wgui.service wg-quick@wg0.service wgui-web.service &> /dev/null
    
    # Services starten
    systemctl start wgui.path wgui.service &> /dev/null
    systemctl start wgui-web.service &> /dev/null
    
    show_progress 98 "Dienste gestartet!"
    sleep 1
} &
wait

log "✓ Alle Dienste aktiviert und gestartet"

################################################################################
# PUNKT 10: Installation abgeschlossen
################################################################################
{
    show_progress 100 "Installation abgeschlossen!"
    sleep 2
} &
wait

clear

# Ermittle Server-IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Abschlussinformationen
whiptail --title "Installation erfolgreich abgeschlossen!" --msgbox "
╔══════════════════════════════════════════════════════╗
║                                                      ║
║  WireGuard VPN Server erfolgreich installiert!       ║
║                                                      ║
╚══════════════════════════════════════════════════════╝

🌐 WEB INTERFACE ZUGRIFF:
   URL: http://$SERVER_IP:5000
   
   Standard-Login:
   • Benutzername: admin
   • Passwort: admin

⚠️  WICHTIGE NÄCHSTE SCHRITTE:

1. Web Interface aufrufen und einloggen

2. Global Settings konfigurieren:
   • Endpoint Address prüfen (Public IP/Hostname)
   • DNS Server eintragen (z.B. 176.9.93.198, 176.9.1.117)

3. WireGuard Server konfigurieren:
   • Post Up Script:
     iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
     (eth0 durch dein Interface ersetzen!)
   
   • Post Down Script:
     iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
     (eth0 durch dein Interface ersetzen!)

4. Clients erstellen und verbinden

5. SICHERHEIT (WICHTIG!):
   • Passwort ändern in: /etc/wireguard/db/server/users.json
   • Bind-Address ändern auf VPN-IP in: /etc/wireguard/start-wgui.sh
     (0.0.0.0:5000 → 10.252.1.0:5000)
   • Service neustarten: systemctl restart wgui-web.service

📋 NÜTZLICHE BEFEHLE:
   • Status prüfen: systemctl status wgui-web.service
   • WireGuard Status: wg show
   • Logs ansehen: journalctl -u wgui-web.service -f
   • UI updaten: /etc/wireguard/update.sh

📝 Port 51820/udp muss in der Firewall geöffnet sein!

Drücken Sie OK zum Beenden
" 35 70

# Finale Ausgabe
cat << EOF

${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}
${GREEN}║                                                                  ║${NC}
${GREEN}║          WireGuard Installation erfolgreich abgeschlossen!       ║${NC}
${GREEN}║                                                                  ║${NC}
${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}

${GREEN}✓${NC} WireGuard VPN Server installiert
${GREEN}✓${NC} WireGuard UI installiert
${GREEN}✓${NC} Systemd Services konfiguriert
${GREEN}✓${NC} IP Forwarding aktiviert

${YELLOW}➜${NC} Web Interface: ${GREEN}http://$SERVER_IP:5000${NC}
   Login: ${GREEN}admin${NC} / ${GREEN}admin${NC}

${RED}⚠ WICHTIG:${NC} Bitte Passwort und Bind-Address ändern (siehe Anleitung)!

${YELLOW}Nützliche Befehle:${NC}
  systemctl status wgui-web.service  # Service Status
  wg show                            # WireGuard Status
  /etc/wireguard/update.sh           # UI Update

${YELLOW}Dokumentation:${NC}
  https://adminforge.de/linux-allgemein/vpn/wireguard-vpn-server-mit-web-interface-einrichten/

EOF

log "Installation abgeschlossen!"
log "Installationslog: /tmp/wgui-install.log"

exit 0
