# ITM GmbH | Windows 11 Upgrade Enabler (robust, unattended, self-elevating)
# Compatible with Windows PowerShell 5.1 and PowerShell 7.x

# =========================[ Meta ]=========================
# Safe UTF-8 setup even without a real console handle
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {
  try { $global:OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
  try { $PSStyle.OutputRendering = 'PlainText' } catch {}
}

$Host.UI.RawUI.WindowTitle = "ITM GmbH | Windows 11 Upgrade Enabler"
$ErrorActionPreference = 'Stop'

$Script:BrandName   = "ITM GmbH"
$Script:AppName     = "Windows 11 Upgrade Enabler"
$Script:StartTime   = Get-Date
$Script:LogPath     = Join-Path $env:TEMP "ITM-W11-Upgrade.log"
$Script:Changes     = New-Object System.Collections.Generic.List[object]

# ===================[ Helper: Console/Log ]================
function Write-Line { param([string]$Text='') ; Write-Host $Text }
function Write-Header {
    param([string]$Title)
    $line = ('=' * [Math]::Max(60, $Title.Length + 10))
    Write-Line
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  " + $Title) -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Line
}
function Write-Log {
    param(
        [ValidateSet('INFO','OK','WARN','ERROR')] [string]$Level,
        [string]$Message
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    switch ($Level) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line -ForegroundColor Gray }
    }
    try { Add-Content -Path $Script:LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}
function Start-Log {
    Write-Header "$($Script:BrandName) - $($Script:AppName)"
    Write-Log INFO  ("Logdatei: {0}" -f $Script:LogPath)
    try { Start-Transcript -Path $Script:LogPath -Append -ErrorAction Stop | Out-Null } catch {}
}
function Stop-Log {
    try { Stop-Transcript | Out-Null } catch {}
    $dur = ((Get-Date) - $Script:StartTime)
    Write-Header "Zusammenfassung"
    if ($Script:Changes.Count -gt 0) {
        foreach ($c in $Script:Changes) {
            $msg = "Path='{0}', Name='{1}', Type='{2}', Action='{3}', Before='{4}', After='{5}'" -f `
                $c.Path,$c.Name,$c.Type,$c.Action,$c.Before,$c.After
            Write-Log OK $msg
        }
    } else {
        Write-Log INFO "Keine geaenderten Werte (alles bereits korrekt gesetzt)."
    }
    Write-Log OK ("Dauer: {0:g}" -f $dur)
}

# ===================[ Helper: Elevation ]==================
function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Log WARN "Administratorrechte erforderlich. Starte Skript mit erhoehten Rechten neu..."
        $hostPath = (Get-Process -Id $PID).Path
        if (-not $hostPath) { $hostPath = "powershell.exe" }
        $argsList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
        Start-Process -FilePath $hostPath -ArgumentList $argsList -Verb RunAs | Out-Null
        exit
    }
}

# ===========[ Helper: Ensure registry PSDrives exist ]============
function Ensure-RegistryDrives {
    foreach ($drv in @(
        @{Name='HKU';  Root='HKEY_USERS'},
        @{Name='HKLM'; Root='HKEY_LOCAL_MACHINE'},
        @{Name='HKCU'; Root='HKEY_CURRENT_USER'}
    )) {
        if (-not (Get-PSDrive -Name $drv.Name -ErrorAction SilentlyContinue)) {
            try {
                New-PSDrive -Name $drv.Name -PSProvider Registry -Root $drv.Root -ErrorAction Stop | Out-Null
                Write-Log INFO ("PSDrive {0}: gemountet ({1})" -f $drv.Name,$drv.Root)
            } catch {
                Write-Log WARN ("PSDrive {0}: konnte nicht gemountet werden: {1}" -f $drv.Name, $_.Exception.Message)
            }
        }
    }
}

# ===================[ Helper: Registry ]===================
function Convert-ToRegExePath {
    param([Parameter(Mandatory)][string]$Path)
    $p = $Path -replace '^HKLM:\\','HKEY_LOCAL_MACHINE\' `
               -replace '^HKCU:\\','HKEY_CURRENT_USER\' `
               -replace '^HKU:\\','HKEY_USERS\' `
               -replace '^HKCR:\\','HKEY_CLASSES_ROOT\' `
               -replace '^HKCC:\\','HKEY_CURRENT_CONFIG\'
    return $p
}
function Backup-RegistryKey {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Test-Path $Path) {
            $reg = Convert-ToRegExePath -Path $Path
            $safe = ($reg -replace '[^A-Za-z0-9_\\-]','_') -replace '\\','_'
            $out = Join-Path (Split-Path $Script:LogPath) ("backup_{0}.reg" -f $safe)
            $p = Start-Process -FilePath reg.exe -ArgumentList @('export',"$reg","$out","/y") -PassThru -WindowStyle Hidden -Wait
            if ($p.ExitCode -eq 0) {
                Write-Log OK ("Backup erstellt: {0}" -f $out)
            } else {
                # Häufig 1, z. B. wenn der Schlüssel leer/speziell ist -> kein Hard-Warn
                Write-Log INFO ("Kein .reg-Backup erstellt (reg.exe ExitCode {0}) fuer {1}" -f $p.ExitCode, $reg)
            }
        } else {
            Write-Log INFO ("Kein Backup noetig (Schluessel nicht vorhanden): {0}" -f $Path)
        }
    } catch {
        Write-Log WARN ("Backup-Fehler fuer ${Path}: {0}" -f $_.Exception.Message)
    }
}
function Ensure-Key {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
        Write-Log OK ("Schluessel erstellt: {0}" -f $Path)
    }
}
function Get-ExistingRegistryValue {
    param([string]$Path,[string]$Name)
    try {
        if (Test-Path $Path) {
            $item = Get-ItemProperty -Path $Path -ErrorAction Stop
            if ($null -ne ($item.PSObject.Properties[$Name])) {
                return $item.$Name
            }
        }
    } catch {}
    return $null
}
function Compare-Value {
    param([object]$Current,[object]$Desired)
    if ($Current -is [array] -and $Desired -is [array]) {
        if ($Current.Count -ne $Desired.Count) { return $false }
        for ($i=0; $i -lt $Current.Count; $i++) {
            if ([string]$Current[$i] -ne [string]$Desired[$i]) { return $false }
        }
        return $true
    } else {
        return ([string]$Current -eq [string]$Desired)
    }
}
function Set-RegistryValueVerbose {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('String','ExpandString','MultiString','DWord','QWord','Binary','Unknown')] [string]$Type,
        [Parameter(Mandatory)][object]$Value
    )
    try {
        Ensure-Key -Path $Path
        $before = Get-ExistingRegistryValue -Path $Path -Name $Name
        $action = 'Created'
        if ($null -ne $before) {
            if (Compare-Value -Current $before -Desired $Value) {
                $action = 'Unchanged'
            } else {
                $action = 'Updated'
            }
        }
        if ($action -ne 'Unchanged') {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        }
        $after = Get-ExistingRegistryValue -Path $Path -Name $Name
        $Script:Changes.Add([pscustomobject]@{
            Path=$Path; Name=$Name; Type=$Type; Action=$action;
            Before= if ($before -is [array]) { ($before -join '|') } else { $before }
            After = if   ($after  -is [array]) { ($after  -join '|') } else { $after  }
        })
        $lvl = if ($action -eq 'Unchanged') { 'INFO' } else { 'OK' }
        Write-Log $lvl ("{0} -> {1}\{2}" -f $action,$Path,$Name)
    } catch {
        Write-Log ERROR ("Setzen von {0} in {1} fehlgeschlagen: {2}" -f $Name,$Path,$_.Exception.Message)
        throw
    }
}
function Remove-RegistryKeySafe {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Test-Path -Path $Path) {
            Backup-RegistryKey -Path $Path
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Log OK ("Entfernt: {0}" -f $Path)
        } else {
            Write-Log INFO ("Nicht vorhanden: {0}" -f $Path)
        }
    } catch {
        Write-Log WARN ("Konnte {0} nicht entfernen: {1}" -f $Path, $_.Exception.Message)
    }
}

# ================[ HKCU across loaded user hives ]================
function Set-ForAllLoadedUsers {
    param(
        [Parameter(Mandatory)][string]$SubPathUnderUser,     # e.g. Software\Microsoft\PCHC
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][object]$Value
    )
    # ensure drives first
    Ensure-RegistryDrives

    $targets = @(
        "HKCU:\$SubPathUnderUser",
        "HKU:\.DEFAULT\$SubPathUnderUser"
    )
    try {
        $hkus = Get-ChildItem HKU:\ -ErrorAction Stop | Where-Object {
            $_.Name -notmatch '\\\.DEFAULT$' -and
            $_.Name -notmatch '_Classes$'
        } | Select-Object -ExpandProperty PSChildName
        foreach ($sid in $hkus) {
            $targets += "HKU:\$sid\$SubPathUnderUser"
        }
    } catch {
        Write-Log WARN ("HKU Enumeration Fehler: {0}" -f $_.Exception.Message)
    }
    foreach ($tp in $targets) {
        try {
            Set-RegistryValueVerbose -Path $tp -Name $Name -Type $Type -Value $Value
        } catch {
            Write-Log WARN ("Setzen fuer {0} fehlgeschlagen: {1}" -f $tp, $_.Exception.Message)
        }
    }
}

# =========================[ Run ]==========================
try {
    Start-Log
    Ensure-Admin
    Ensure-RegistryDrives

    # OS Info (optional)
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Log INFO ("OS: {0} ({1}), Build {2}" -f $os.Caption,$os.Version,$os.BuildNumber)
        if ($os.ProductType -ne 1) {
            Write-Log WARN "Server-OS erkannt. Dieses Skript ist fuer Client-Upgrades gedacht."
        }
    } catch {}

    # Schritt 1: Alte Upgrade-Indikatoren bereinigen
    Write-Header "Schritt 1/4 - Alte Upgrade-Indikatoren bereinigen"
    Remove-RegistryKeySafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\CompatMarkers"
    Remove-RegistryKeySafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Shared"
    Remove-RegistryKeySafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators"
    Write-Log OK "Bereinigung abgeschlossen."

    # Schritt 2: Hardware-Kompatibilitaet simulieren
    Write-Header "Schritt 2/4 - Hardware-Kompatibilitaet simulieren"
    $hwVars = @(
        "SQ_SecureBootCapable=TRUE",
        "SQ_SecureBootEnabled=TRUE",
        "SQ_TpmVersion=2",
        "SQ_RamMB=8192"
    )
    Set-RegistryValueVerbose -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk" -Name "HwReqChkVars" -Type MultiString -Value $hwVars
    Write-Log OK "Hardware-Kompatibilitaetswerte angewendet."

    # Schritt 3: Upgrade-Policy (TPM/CPU) erlauben
    Write-Header "Schritt 3/4 - Upgrade-Policy (TPM/CPU) erlauben"
    Set-RegistryValueVerbose -Path "HKLM:\SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Type DWord -Value 1
    Write-Log OK "Upgrade-Policy gesetzt."

    # Zusatz: LabConfig-Bypaesse fuer Setup.exe/ISO
    Write-Header "Zusatz - LabConfig-Bypaesse fuer Setup.exe"
    $lab = "HKLM:\SYSTEM\Setup\LabConfig"
    Set-RegistryValueVerbose -Path $lab -Name "BypassTPMCheck"       -Type DWord -Value 1
    Set-RegistryValueVerbose -Path $lab -Name "BypassSecureBootCheck" -Type DWord -Value 1
    Set-RegistryValueVerbose -Path $lab -Name "BypassCPUCheck"        -Type DWord -Value 1
    Set-RegistryValueVerbose -Path $lab -Name "BypassRAMCheck"        -Type DWord -Value 1
    Set-RegistryValueVerbose -Path $lab -Name "BypassStorageCheck"    -Type DWord -Value 1
    Write-Log OK "LabConfig-Bypaesse angewendet."

    # Schritt 4: UpgradeEligibility fuer Benutzer
    Write-Header "Schritt 4/4 - UpgradeEligibility fuer Benutzer setzen"
    Set-ForAllLoadedUsers -SubPathUnderUser "Software\Microsoft\PCHC" -Name "UpgradeEligibility" -Type DWord -Value 1
    Write-Log OK "UpgradeEligibility gesetzt."

    Write-Header "Fertig"
    Write-Log INFO "Alle Operationen wurden erfolgreich ausgefuehrt."
    Write-Log INFO "Sie koennen jetzt den Windows 11 Installationsassistenten oder setup.exe vom Installationsmedium starten."

} catch {
    Write-Log ERROR ("Unerwarteter Fehler: {0}" -f $_.Exception.Message)
    throw
} finally {
    Stop-Log
}