# Setup-WireGuard-DNS-Task.ps1
# Erstellt C:\ITM\Scripts\WG-Tunnel-ping.ps1 + WG-Runner.ps1 und legt geplante Aufgabe als SYSTEM an


# ================== SELF-ELEVATION (robust for irm|iex) ==================
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Starte Script mit Administratorrechten..." -ForegroundColor Yellow

    # Wenn das Script NICHT aus einer Datei läuft (z.B. irm|iex), ist $PSCommandPath leer.
    # Dann speichern wir den aktuellen Script-Inhalt in eine Temp-Datei und starten die.
    $tempFile = Join-Path $env:TEMP "Setup-WireGuard-DNS-Task.elevated.ps1"

    if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path $PSCommandPath)) {
        # Content des aktuell laufenden Scripts aus dem Callstack holen (funktioniert bei irm|iex)
        $scriptText = (Get-Variable MyInvocation -Scope 0).Value.MyCommand.ScriptBlock.ToString()
        Set-Content -Path $tempFile -Value $scriptText -Encoding UTF8 -Force

        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempFile`""
        exit
    }

    # Normaler Fall: Script läuft aus Datei
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
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

# --- Ordner anlegen ---
if (-not (Test-Path $baseDir)) {
  New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

# --- Inhalt: WG-Tunnel-ping.ps1 (nutzt feste DNS IP und festen Tunnel) ---
$checkScript = @"
param(
  [int]`$Log = 0
)

# ================== FESTE PARAMETER ==================
`$TunnelNameFixed = "$TunnelNameFixed"        # ohne .conf / .conf.dpapi
`$DnsIpFixed      = "$DnsIpFixed"             # DNS-IP für Ping
# =====================================================

`$logPath = Join-Path `$env:TEMP ("wg_dns_check_" + (Get-Date -Format "yyyyMMdd") + ".log")

function OutLog([string]`$m){
  `$line = "[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] " + `$m
  Write-Host `$line
  if(`$Log -eq 1){
    Add-Content -Path `$logPath -Value `$line -Encoding UTF8
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

function Ensure-TunnelServiceRunning([string]`$TunnelName){
  `$wgExe = Get-WireGuardExePath
  if(-not `$wgExe){
    OutLog "WireGuard EXE nicht gefunden"
    return
  }

  `$cfgFile = Get-TunnelConfigPath `$TunnelName
  if(-not `$cfgFile){
    OutLog "Config-Datei nicht gefunden für Tunnel `$TunnelName"
    return
  }

  `$svcName = "WireGuardTunnel`$" + `$TunnelName
  `$svc = Get-Service -Name `$svcName -ErrorAction SilentlyContinue

  if(`$svc){
    OutLog "Dienst existiert: `$svcName (Status=`$(`$svc.Status))"
    if(`$svc.Status -ne "Running"){
      OutLog "Starte Dienst `$svcName"
      Start-Service -Name `$svcName -ErrorAction SilentlyContinue
    }
  }
  else {
    OutLog "Dienst existiert nicht → installiere Tunnel-Service"
    OutLog "CMD: `$wgExe /installtunnelservice `$cfgFile"
    & `$wgExe /installtunnelservice "`$cfgFile" | Out-Null
    Start-Service -Name `$svcName -ErrorAction SilentlyContinue
  }

  `$svc2 = Get-Service -Name `$svcName -ErrorAction SilentlyContinue
  if(`$svc2){
    OutLog "Dienststatus nach Aktion: `$(`$svc2.Status)"
  }
}

# ================== START ==================
OutLog "Start"
OutLog "TunnelName=`$TunnelNameFixed"
OutLog "DnsIp=`$DnsIpFixed"
OutLog "LogFile=`$logPath"

# ================== PING ==================
OutLog "Ping `$DnsIpFixed (4 Versuche)"
`$ok = `$true

for (`$i=1; `$i -le 4; `$i++) {
  ping.exe -n 1 -w 1000 `$DnsIpFixed > `$null
  if (`$LASTEXITCODE -eq 0) {
    OutLog "Ping `$i/4 OK"
  } else {
    OutLog "Ping `$i/4 FAIL"
    `$ok = `$false
    break
  }
}

if (`$ok) {
  OutLog "Result=1 DNS erreichbar"
  Write-Output 1
  exit 0
}

# ================== DNS DOWN → TUNNEL START ==================
OutLog "DNS nicht erreichbar → Tunnel starten"
Ensure-TunnelServiceRunning -TunnelName `$TunnelNameFixed

OutLog "Result=0 DNS offline"
Write-Output 0
"@

Set-Content -Path $checkPath -Value $checkScript -Encoding UTF8 -Force

# --- Inhalt: WG-Runner.ps1 (führt alle 30s das Check-Script aus) ---
$runnerScript = @"
# Läuft dauerhaft und startet alle 30 Sekunden das Check-Script
`$check = "$checkPath"

while (`$true) {
  try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`$check" -Log 1 | Out-Null
  } catch {
    # nicht sterben, einfach weiter
  }
  Start-Sleep -Seconds 30
}
"@

Set-Content -Path $runPath -Value $runnerScript -Encoding UTF8 -Force

# --- Scheduled Task erstellen ---
$taskName = "ITM-WireGuard-DNS-Check-30s"

# Wenn Task existiert -> löschen
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runPath`""
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
Write-Host "FERTIG." -ForegroundColor Green
Write-Host "Script gespeichert: $checkPath"
Write-Host "Runner gespeichert: $runPath"
Write-Host "Aufgabe erstellt:  $taskName (SYSTEM, Highest, Start at boot, loop alle 30s)"
Write-Host ""
Write-Host "Status prüfen:"
Write-Host "  Get-ScheduledTask -TaskName `"$taskName`" | Get-ScheduledTaskInfo"
Write-Host "Dienst prüfen:"
Write-Host "  Get-Service `"WireGuardTunnel`$$TunnelNameFixed`""
