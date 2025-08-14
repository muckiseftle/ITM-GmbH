<p align="center">
  <img src="../../assets/logo-light.png#gh-light-mode-only" alt="ITM GmbH" width="150">
  <img src="../../assets/logo-dark.png#gh-dark-mode-only"  alt="ITM GmbH" width="150">
</p>
# ITM GmbH — Windows 11 Upgrade Enabler

Dieses PowerShell-Skript **Bypass_Win11_Requirements.ps1** ermöglicht das Upgrade auf Windows 11, auch wenn die offizielle Hardware-Prüfung von Microsoft fehlschlägt (z. B. wegen nicht unterstützter CPU oder fehlendem TPM 2.0).  
Es ist im ITM‑Stil gestaltet und führt den Prozess stabil, nachvollziehbar und mit klaren Statusmeldungen durch.


## Funktionsübersicht
- **Bereinigung** alter Windows‑Upgrade‑Indikatoren in der Registry
- **Simulation** von Hardware‑Kompatibilitätswerten (TPM 2.0, Secure Boot, RAM)
- **Freischaltung** von Upgrades auf nicht offiziell unterstützter CPU oder TPM
- **Setzen** der Upgrade‑Berechtigung im Benutzerkontext (HKCU)
- **Protokollierung** (Transcript) im `%TEMP%`‑Ordner
- **Administrator‑Check**, strukturierte Ausgaben und Fortschrittsanzeige





## Download

[![Download Script](https://img.shields.io/badge/Download-Script-blue?style=for-the-badge&logo=powershell)](https://raw.githubusercontent.com/muckiseflte/ITM-GmbH/main/scripts/Windows%2011%20Upgrade/Bypass_Win11_Requirements.ps1)





## Ausführung

### Variante A: Lokal ausführen
1. PowerShell **als Administrator** öffnen.
2. Skript starten:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   & ".\Bypass_Win11_Requirements.ps1"
   ```

### Variante B: Direkt aus GitHub herunterladen & ausführen
```powershell
powershell -ExecutionPolicy Bypass -NoProfile -Command "Invoke-WebRequest 'https://raw.githubusercontent.com/muckiseftle/ITM-GmbH/main/scripts/Windows%2011%20Upgrade/Bypass_Win11_Requirements.ps1' -OutFile $env:TEMP\itm_w11.ps1; & $env:TEMP\itm_w11.ps1"
```



## Hinweise
- Das Skript verändert Registry‑Einträge dauerhaft. Eine **Sicherung** wird empfohlen.
- **Kein Neustart erforderlich.**
- Einsatz auf eigenes Risiko.

---

© 2025 ITM GmbH — Alle Rechte vorbehalten
