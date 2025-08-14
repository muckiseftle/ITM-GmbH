[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ITM GmbH | Windows 11 Upgrade Enabler"

$Script:BrandName   = "ITM GmbH"
$Script:AppName     = "Windows 11 Upgrade Enabler"
$Script:LogPath     = Join-Path $env:TEMP "ITM-W11-Upgrade.log"
$Script:StartTime   = Get-Date

function Write-Header {
    param(
        [string]$Title,
        [ConsoleColor]$Color = 'Cyan'
    )
    $line = ('═' * ([Math]::Max(50, $Title.Length + 4)))
    Write-Host ""
    Write-Host "  $line" -ForegroundColor $Color
    Write-Host ("  ║ " + $Title + " " + "║").PadRight($line.Length + 2) -ForegroundColor $Color
    Write-Host "  $line" -ForegroundColor $Color
    Write-Host ""
}

function Write-Section {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ConsoleColor]$Color = 'White'
    )
    Write-Host ("-- " + $Text) -ForegroundColor $Color
}

function Write-Info  { param([string]$m) Write-Host "   • $m" -ForegroundColor Gray }
function Write-Ok    { param([string]$m) Write-Host "   ✓ $m" -ForegroundColor Green }
function Write-Warn  { param([string]$m) Write-Host "   ! $m" -ForegroundColor Yellow }
function Write-Err   { param([string]$m) Write-Host "   x $m" -ForegroundColor Red }

function Start-Log   { Write-Info "Logdatei: $($Script:LogPath)"; try { Start-Transcript -Path $Script:LogPath -Append -ErrorAction Stop | Out-Null } catch {} }
function Stop-Log    { try { Stop-Transcript | Out-Null } catch {} }

function Require-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    if (-not $isAdmin) { Write-Err "Administratorrechte sind erforderlich."; throw "Kein Administrator" }
}

function Set-RegistryValueForced {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('String','ExpandString','MultiString','DWord','QWord','Binary','Unknown')][string]$Type,
        [Parameter(Mandatory)][object]$Value
    )
    try {
        if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Ok "$Name gesetzt in $Path"
    } catch {
        Write-Err "Setzen von $Name in $Path fehlgeschlagen: $($_.Exception.Message)"
        throw
    }
}

function Remove-RegistryKeySafe {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Test-Path -Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Ok "Entfernt: $Path"
        } else {
            Write-Info "Nicht vorhanden: $Path"
        }
    } catch {
        Write-Warn "Konnte $Path nicht entfernen: $($_.Exception.Message)"
    }
}

param([switch]$Quiet)

try {
    Clear-Host
    Write-Header "$($Script:BrandName) — $($Script:AppName)"
    Start-Log
    Require-Admin

    if (-not $Quiet) {
        Write-Section "Hinweis"
        Write-Info  "Dieses Skript verändert Registry-Einträge systemweit."
        Write-Info  "Ein Neustart ist i. d. R. nicht erforderlich."
        $choice = Read-Host "Fortfahren? (J/N)"
        if ($choice -notin @('J','j','Y','y')) { Write-Warn "Abgebrochen durch Benutzer."; return }
        Write-Host ""
    }

    Write-Section "Schritt 1/4 — Alte Upgrade-Indikatoren bereinigen" Yellow
    Write-Progress -Activity "Bereinigung" -Status "Entferne alte Upgrade-Marker..." -PercentComplete 5
    Remove-RegistryKeySafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\CompatMarkers"
    Remove-RegistryKeySafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Shared"
    Remove-RegistryKeySafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators"
    Write-Ok "Bereinigung abgeschlossen."

    Write-Section "Schritt 2/4 — Hardware-Kompatibilität simulieren" Yellow
    Write-Progress -Activity "Kompatibilität" -Status "Setze Simulationswerte (TPM/SecureBoot/RAM)..." -PercentComplete 35
    Set-RegistryValueForced -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk" -Name "HwReqChkVars" -Type MultiString -Value @(
        "SQ_SecureBootCapable=TRUE",
        "SQ_SecureBootEnabled=TRUE",
        "SQ_TpmVersion=2",
        "SQ_RamMB=8192"
    )
    Write-Ok "Hardware-Kompatibilitätswerte angewendet."

    Write-Section "Schritt 3/4 — Upgrade auf nicht unterstützter CPU/TPM erlauben" Yellow
    Write-Progress -Activity "Upgrade-Policy" -Status "Erlaube Upgrade mit nicht unterstützter CPU/TPM..." -PercentComplete 65
    Set-RegistryValueForced -Path "HKLM:\SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Type DWord -Value 1
    Write-Ok "Upgrade-Policy gesetzt."

    Write-Section "Schritt 4/4 — Upgrade-Berechtigung setzen (Benutzerkontext)" Yellow
    Write-Progress -Activity "Eligibility" -Status "Setze UpgradeEligibility=1..." -PercentComplete 85
    Set-RegistryValueForced -Path "HKCU:\Software\Microsoft\PCHC" -Name "UpgradeEligibility" -Type DWord -Value 1
    Write-Ok "UpgradeEligibility gesetzt."

    Write-Progress -Activity "Abschluss" -Completed

    Write-Header "Fertig"
    Write-Info "Alle Operationen wurden erfolgreich ausgeführt."
    Write-Info "Sie können jetzt den Windows 11 Upgrade Assistant oder setup.exe vom Installationsmedium starten."
    Write-Ok   ("Dauer: {0:g}" -f ((Get-Date) - $Script:StartTime))

} catch {
    Write-Err "Unerwarteter Fehler: $($_.Exception.Message)"
} finally {
    Stop-Log
}
