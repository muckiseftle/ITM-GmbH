# ITM – WireGuard DNS Monitor (30s)

Dieses Setup erstellt ein kleines Monitoring, das eine feste DNS-IP per Ping prüft.  
Wenn der Ping fehlschlägt, wird der konfigurierte WireGuard-Tunnel **automatisch als Tunnel-Service installiert** und **gestartet**.

> Praktisch, wenn WireGuard beim Stoppen den Dienst löscht oder der Tunnel “weg” ist.

---

## ✅ Features

- Fester Tunnelname + feste DNS-IP (wird im Setup abgefragt)
- Ping-Check (4 Versuche)
- Bei DNS down:
  - findet automatisch `*.conf.dpapi` oder `*.conf`
  - `wireguard.exe /installtunnelservice`
  - startet `WireGuardTunnel$<TunnelName>`
- Erstellt eine geplante Aufgabe als **SYSTEM** mit **höchsten Rechten**
- Ausführung alle **30 Sekunden** (über `WG-Runner.ps1`)
- Setup holt sich automatisch Adminrechte (UAC)

---

## 📦 Voraussetzungen

- Windows Server 2022+ (funktioniert auch auf Windows 10/11)
- WireGuard for Windows installiert  
  Standardpfade:
  - `C:\Program Files\WireGuard\wireguard.exe`
  - `C:\Program Files\WireGuard\Data\Configurations\`

---

## 📁 Pfade / Dateien

### GitHub (Repository)
- `Scripts/WireGuard DNS Monitor/Setup-WireGuard-DNS-Task.ps1`

### Lokal (wird durch Setup erstellt)
- Ordner:
  - `C:\ITM\Scripts\`

- Monitoring Script:
  - `C:\ITM\Scripts\WG-Tunnel-ping.ps1`

- Runner Script (führt alle 30 Sekunden aus):
  - `C:\ITM\Scripts\WG-Runner.ps1`

### Logs
- `%TEMP%\wg_dns_check_YYYYMMDD.log`

---

## 🚀 Quick Start (direkt aus GitHub)

> Lädt das Setup-Script und führt es aus (fragt Tunnelname + DNS-IP ab).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/muckiseftle/ITM-GmbH/main/Scripts/WireGuard%20DNS%20Monitor/Setup-WireGuard-DNS-Task.ps1' | iex"
