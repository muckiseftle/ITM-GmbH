# Setup-WireGuard-DNS-Task.ps1
# Erstellt C:\ITM\Scripts\WG-Tunnel-ping.ps1 und legt geplante Aufgabe als SYSTEM an

# ================== SELF-ELEVATION (robust for irm|iex) ==================
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Starte Script mit Administratorrechten..." -ForegroundColor Yellow

    $tempFile = Join-Path $env:TEMP "Setup-WireGuard-DNS-Task.elevated.ps1"

    if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path $PSCommandPath)) {
        $scriptText = (Get-Variable MyInvocation -Scope 0).Value.MyCommand.ScriptBlock.ToString()
        Set-Content -Path $tempFile -Value $scriptText -Encoding UTF8 -Force

        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempFile`"" -Wait
        
        # Cleanup temp file
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        exit
    }

    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}
# ========================================================================

$ErrorActionPreference = "Stop"

function Ask-NonEmpty($prompt) {
  while ($true) {
    $v = Read-Host $prompt
    if ($null -ne $v -and $v.Trim().Length -gt 0) { return $v.Trim() }
    Write-Host "Bitte einen Wert eingeben." -ForegroundColor Yellow
  }
}

function Ask-IPv4($prompt) {
  while ($true) {
    $v = (Read-Host $prompt).Trim()
    if ($v -match '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$') {
      return $v
    }
    Write-Host "Ungültige IPv4. Beispiel: 192.168.178.2" -ForegroundColor Yellow
  }
}

# --- Werte abfragen ---
$TunnelNameFixed = Ask-NonEmpty "Tunnel-Name (ohne .conf)"
$DnsIpFixed      = Ask-IPv4    "DNS-IP für Ping"

# --- Zielpfade ---
$baseDir   = "C:\ITM\Scripts"
$checkPath = Join-Path $baseDir "WG-Tunnel-ping.ps1"
$runPath   = Join-Path $baseDir "WG-Runner.ps1"

if (-not (Test-Path $baseDir)) {
  New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

# --- Inhalt: WG-Tunnel-ping.ps1 (VERBESSERT) ---
$checkScript = @"
param(
  [int]`$Log = 0
)

# ================== KONFIGURATION ==================
`$TunnelNameFixed     = "$TunnelNameFixed"        # ohne .conf / .conf.dpapi
`$DnsIpFixed          = "$DnsIpFixed"             # DNS-IP für Ping
`$PingTimeoutSeconds  = 2                         # Ping-Timeout
`$ServiceTimeoutSec   = 20                        # Service Start/Stop Timeout
`$LogRetentionDays    = 7                         # Log-Dateien älter als X Tage löschen
# ===================================================

`$logPath = Join-Path `$env:TEMP ("wg_dns_check_" + (Get-Date -Format "yyyyMMdd") + ".log")

function OutLog([string]`$m){
  `$line = "[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] " + `$m
  Write-Host `$line
  if(`$Log -eq 1){
    Add-Content -Path `$logPath -Value `$line -Encoding UTF8 -ErrorAction SilentlyContinue
  }
}

function Cleanup-OldLogs {
  try {
    `$maxAge = (Get-Date).AddDays(-`$LogRetentionDays)
    Get-ChildItem "`$env:TEMP\wg_dns_check_*.log" -ErrorAction SilentlyContinue | 
      Where-Object {`$_.LastWriteTime -lt `$maxAge} | 
      Remove-Item -Force -ErrorAction SilentlyContinue
  } catch {
    # Fehler beim Cleanup ignorieren
  }
}

function Get-WireGuardExePath {
  `$p = Join-Path `$env:ProgramFiles "WireGuard\wireguard.exe"
  if (Test-Path `$p) { return `$p }
  `$cmd = Get-Command wireguard.exe -ErrorAction SilentlyContinue
  if (`$cmd) { return `$cmd.Source }
  return `$null
}

function Get-TunnelConfigPath([string]`$TunnelName){
  `$cfgDir = Join-Path `$env:ProgramFiles "WireGuard\Data\Configurations"
  if(-not (Test-Path `$cfgDir)){ return `$null }

  `$dpapi = Join-Path `$cfgDir (`$TunnelName + ".conf.dpapi")
  `$plain = Join-Path `$cfgDir (`$TunnelName + ".conf")

  if(Test-Path `$dpapi){ return `$dpapi }
  if(Test-Path `$plain){ return `$plain }
  return `$null
}

function Wait-ServiceStatus([string]`$Name, [string]`$Desired, [int]`$TimeoutSec = 15){
  `$sw = [Diagnostics.Stopwatch]::StartNew()
  while(`$sw.Elapsed.TotalSeconds -lt `$TimeoutSec){
    `$s = Get-Service -Name `$Name -ErrorAction SilentlyContinue
    if(`$s -and `$s.Status.ToString() -eq `$Desired){ return `$true }
    Start-Sleep -Milliseconds 300
  }
  return `$false
}

function Ensure-ServiceExistsOrInstall([string]`$TunnelName){
  `$svcName = "WireGuardTunnel`$" + `$TunnelName
  `$svc = Get-Service -Name `$svcName -ErrorAction SilentlyContinue
  if(`$svc){
    OutLog "Dienst existiert: `$svcName (Status=`$(`$svc.Status))"
    return `$true
  }

  OutLog "Dienst existiert NICHT: `$svcName → installiere Tunnel-Service"

  `$wgExe = Get-WireGuardExePath
  if(-not `$wgExe){
    OutLog "WireGuard EXE nicht gefunden → Abbruch"
    return `$false
  }

  `$cfgFile = Get-TunnelConfigPath `$TunnelName
  if(-not `$cfgFile){
    OutLog "Config-Datei nicht gefunden für Tunnel '`$TunnelName' → Abbruch"
    return `$false
  }

  OutLog "CMD: `$wgExe /installtunnelservice `$cfgFile"
  try {
    & `$wgExe /installtunnelservice "`$cfgFile" | Out-Null
  } catch {
    OutLog "FEHLER bei Installation: `$(`$_.Exception.Message)"
    return `$false
  }

  Start-Sleep -Seconds 1
  `$svc = Get-Service -Name `$svcName -ErrorAction SilentlyContinue
  if(`$svc){
    OutLog "Dienst nach Installation vorhanden: `$svcName (Status=`$(`$svc.Status))"
    return `$true
  } else {
    OutLog "Dienst konnte nicht installiert werden (Service nicht sichtbar) → Abbruch"
    return `$false
  }
}

function Restart-WireGuardService([string]`$TunnelName){
  `$svcName = "WireGuardTunnel`$" + `$TunnelName

  `$svc = Get-Service -Name `$svcName -ErrorAction SilentlyContinue
  if(-not `$svc){
    OutLog "Restart angefordert, aber Dienst fehlt: `$svcName"
    return `$false
  }

  OutLog "Neustart Dienst: `$svcName (aktuell=`$(`$svc.Status))"

  try {
    if(`$svc.Status -eq 'Running'){
      Stop-Service -Name `$svcName -Force -ErrorAction Stop
      if(-not (Wait-ServiceStatus -Name `$svcName -Desired "Stopped" -TimeoutSec `$ServiceTimeoutSec)){
        OutLog "WARNUNG: Dienst stoppt nicht sauber innerhalb Timeout (`$ServiceTimeoutSec`s) → weiter mit Start"
      } else {
        OutLog "Dienst gestoppt"
      }
    }

    Start-Service -Name `$svcName -ErrorAction Stop
    if(Wait-ServiceStatus -Name `$svcName -Desired "Running" -TimeoutSec `$ServiceTimeoutSec){
      OutLog "Dienst läuft wieder"
      return `$true
    } else {
      OutLog "WARNUNG: Dienst startet nicht sauber innerhalb Timeout (`$ServiceTimeoutSec`s)"
      return `$false
    }
  } catch {
    OutLog "FEHLER beim Neustart: `$(`$_.Exception.Message)"
    return `$false
  }
}

function Test-PingFast([string]`$Ip){
  # Nutzt eingebautes Test-Connection (1 Paket, schneller)
  try {
    return (Test-Connection -ComputerName `$Ip -Count 1 -Quiet -TimeoutSeconds `$PingTimeoutSeconds -ErrorAction Stop)
  } catch {
    OutLog "FEHLER bei Test-Connection: `$(`$_.Exception.Message)"
    return `$false
  }
}

function Test-PingByOutput([string]`$Ip){
  # Fallback: "Normaler" ping wie in CMD (1 Echo Request), Output wird ausgewertet
  # Erfolg, wenn irgendwo "TTL=" vorkommt (sprachunabhängig)
  `$timeoutMs = `$PingTimeoutSeconds * 1000
  try {
    `$out = & ping.exe -n 1 -w `$timeoutMs `$Ip 2>&1 | Out-String
  } catch {
    `$out = "`$(`$_.Exception.Message)"
  }

  OutLog ("PING-OUTPUT: " + (`$out -replace "`r","" -replace "`n"," | ").Trim())

  if(`$out -match "TTL="){
    return `$true
  }
  return `$false
}

# ================== START ==================
Cleanup-OldLogs

OutLog "=========================================="
OutLog "Start WG-DNS-Check"
OutLog "TunnelName=`$TunnelNameFixed"
OutLog "DnsIp=`$DnsIpFixed"
OutLog "PingTimeout=`$PingTimeoutSeconds`s"
OutLog "LogFile=`$logPath"

# ================== PING (PRIMÄR) ==================
OutLog "Ping (Test-Connection) `$DnsIpFixed"
`$ok = Test-PingFast -Ip `$DnsIpFixed

# ================== PING FALLBACK ==================
if (-not `$ok) {
  OutLog "Test-Connection fehlgeschlagen → Fallback zu ping.exe"
  `$ok = Test-PingByOutput -Ip `$DnsIpFixed
}

if (`$ok) {
  OutLog "Result=1 DNS erreichbar"
  OutLog "=========================================="
  Write-Output 1
  exit 0
}

# ================== PING FAIL → SERVICE CHECK/INSTALL/RESTART ==================
OutLog "DNS nicht erreichbar → Dienst prüfen / installieren / neustarten"

if(Ensure-ServiceExistsOrInstall -TunnelName `$TunnelNameFixed){
  `$r = Restart-WireGuardService -TunnelName `$TunnelNameFixed
  OutLog "RestartResult=`$r"
} else {
  OutLog "Service konnte nicht sichergestellt werden → kein Neustart möglich"
}

OutLog "Result=0 DNS offline"
OutLog "=========================================="
Write-Output 0
"@

Set-Content -Path $checkPath -Value $checkScript -Encoding UTF8 -Force

# --- Inhalt: WG-Runner.ps1 (optimiert mit Mutex gegen Race Conditions) ---
$runnerScript = @"
# Läuft dauerhaft und startet alle 30 Sekunden das Check-Script
# Mutex verhindert parallele Ausführungen

`$checkScript = "$checkPath"
`$intervalSeconds = 30

`$mutexName = "Global\WG-DNS-Check-Mutex"
`$mutex = New-Object System.Threading.Mutex(`$false, `$mutexName)

Write-Host "[Runner] Gestartet. Interval=`$intervalSeconds`s, Mutex=`$mutexName"

while (`$true) {
  `$acquired = `$false
  try {
    # Versuche Mutex zu bekommen (non-blocking)
    `$acquired = `$mutex.WaitOne(0)
    
    if (`$acquired) {
      try {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`$checkScript" -Log 1 | Out-Null
      } catch {
        Write-Host "[Runner] Fehler beim Ausführen: `$(`$_.Exception.Message)"
      } finally {
        `$mutex.ReleaseMutex()
      }
    } else {
      Write-Host "[Runner] Check läuft bereits, überspringe..."
    }
  } catch {
    Write-Host "[Runner] Mutex-Fehler: `$(`$_.Exception.Message)"
  }
  
  Start-Sleep -Seconds `$intervalSeconds
}
"@

Set-Content -Path $runPath -Value $runnerScript -Encoding UTF8 -Force

# --- Scheduled Task erstellen (mit Runner für 30s-Intervall) ---
$taskName = "ITM-WireGuard-DNS-Check-30s"

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runPath`""

# Trigger: Bei Systemstart
$trigger = New-ScheduledTaskTrigger -AtStartup

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Days 3650) `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "INSTALLATION ABGESCHLOSSEN" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Scripts gespeichert:" -ForegroundColor White
Write-Host "  Check-Script:      $checkPath" -ForegroundColor Gray
Write-Host "  Runner-Script:     $runPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Aufgabe erstellt:      $taskName" -ForegroundColor White
Write-Host ""
Write-Host "Konfiguration:" -ForegroundColor Yellow
Write-Host "  - Benutzer:          SYSTEM (Höchste Rechte)" -ForegroundColor Gray
Write-Host "  - Start:             Bei Systemstart" -ForegroundColor Gray
Write-Host "  - Intervall:         Alle 30 Sekunden (via Runner)" -ForegroundColor Gray
Write-Host "  - Parallele Läufe:   Verhindert (Mutex)" -ForegroundColor Gray
Write-Host "  - Fenster:           Versteckt" -ForegroundColor Gray
Write-Host ""
Write-Host "Status prüfen:" -ForegroundColor Yellow
Write-Host "  Get-ScheduledTask -TaskName `"$taskName`" | Get-ScheduledTaskInfo" -ForegroundColor Gray
Write-Host ""
Write-Host "Dienst prüfen:" -ForegroundColor Yellow
Write-Host "  Get-Service `"WireGuardTunnel`$TunnelNameFixed`"" -ForegroundColor Gray
Write-Host ""
Write-Host "Logs anzeigen:" -ForegroundColor Yellow
Write-Host "  Get-Content `"`$env:TEMP\wg_dns_check_`$(Get-Date -Format 'yyyyMMdd').log`" -Tail 50" -ForegroundColor Gray
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
pause