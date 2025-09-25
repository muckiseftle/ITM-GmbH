#!/bin/bash

# Funktion, um den Fortschritt zu aktualisieren
show_progress() {
    local progress=$1
    local message=$2
    echo $progress | whiptail --title "Installation" --gauge "$message" 6 60 0
}

# Installiere whiptail, falls nicht vorhanden
if ! command -v whiptail &> /dev/null
then
    echo "Installiere whiptail..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -qq && apt install -y whiptail &> /dev/null
fi

# Vorschaufenster mit Logo anzeigen
whiptail --title "WireGuard Installation" --msgbox "
               WireGuard Installer                                    
            Nepomuk Gail - ITM GmbH
" 15 50

# Punkt 1: Debian Pakete installieren
show_progress 10 "Aktualisiere Paketliste..."
export DEBIAN_FRONTEND=noninteractive
apt update -qq &> /dev/null
show_progress 20 "Installiere WireGuard, Curl und Tar..."
apt install -y wireguard curl tar &> /dev/null
show_progress 30 "Pakete erfolgreich installiert!"

# Punkt 2: IP Forwarding aktivieren
show_progress 40 "Aktiviere IP-Forwarding..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p &> /dev/null

# Punkt 3: WireGuard UI Startscript erstellen
show_progress 50 "Erstelle WireGuard UI Start-Skript..."
mkdir -p /etc/wireguard
cat <<EOF > /etc/wireguard/start-wgui.sh
#!/bin/bash

cd /etc/wireguard
./wireguard-ui -bind-address 0.0.0.0:5000
EOF
chmod +x /etc/wireguard/start-wgui.sh

# Punkt 4: Systemd Service Unit anlegen
show_progress 60 "Erstelle Systemd Service für WireGuard UI..."
cat <<EOF > /etc/systemd/system/wgui-web.service
[Unit]
Description=WireGuard UI

[Service]
Type=simple
ExecStart=/etc/wireguard/start-wgui.sh

[Install]
WantedBy=multi-user.target
EOF

# WireGuard UI Update Script erstellen
show_progress 70 "Erstelle WireGuard UI Update-Skript..."
cat <<EOF > /etc/wireguard/update.sh
#!/bin/bash

VER=\$(curl -sI https://github.com/ngoduykhanh/wireguard-ui/releases/latest | grep "location:" | cut -d "/" -f8 | tr -d '\r')

echo "downloading wireguard-ui \$VER"
curl -sL "https://github.com/ngoduykhanh/wireguard-ui/releases/download/\$VER/wireguard-ui-\$VER-linux-amd64.tar.gz" -o wireguard-ui-\$VER-linux-amd64.tar.gz

echo -n "extracting "; tar xvf wireguard-ui-\$VER-linux-amd64.tar.gz -C /etc/wireguard

echo "restarting wgui-web.service"
systemctl restart wgui-web.service
EOF
chmod +x /etc/wireguard/update.sh

# WireGuard UI Update Script ausführen
show_progress 80 "Führe das WireGuard UI Update-Skript aus..."
cd /etc/wireguard
./update.sh &> /dev/null

# Punkt 5: WireGuard Konfigurationsdatei von Systemd überwachen lassen
show_progress 90 "Erstelle Überwachungsskripte für WireGuard..."
cat <<EOF > /etc/systemd/system/wgui.service
[Unit]
Description=Restart WireGuard
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart wg-quick@wg0.service

[Install]
RequiredBy=wgui.path
EOF

cat <<EOF > /etc/systemd/system/wgui.path
[Unit]
Description=Watch /etc/wireguard/wg0.conf for changes

[Path]
PathModified=/etc/wireguard/wg0.conf

[Install]
WantedBy=multi-user.target
EOF

# Punkt 6: Dienste aktivieren und starten
show_progress 100 "Aktiviere und starte Dienste..."
touch /etc/wireguard/wg0.conf
systemctl enable wgui.{path,service} wg-quick@wg0.service wgui-web.service &> /dev/null
systemctl start wgui.{path,service} &> /dev/null

# Fortschrittsbalken schließen, sobald 100 % erreicht ist
sleep 1  # eine kurze Pause, damit der Balken bei 100% sichtbar ist
clear  # terminal zurücksetzen

# Abschlusshinweis
whiptail --title "Installation abgeschlossen" --msgbox "WireGuard UI wurde erfolgreich installiert! Sie können nun den Webdienst aufrufen." 10 50

echo "Installation abgeschlossen!"
