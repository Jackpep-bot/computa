<#
.SYNOPSIS
  Automate uninstalling non-essential programs (and optionally wipe Steam game
  files), keeping Windows, drivers, and your chosen keepers.
.DESCRIPTION
  DRY-RUN by default: lists exactly what WOULD be removed. Pass -Confirm to
  actually uninstall. A hard PROTECTED list means it can never remove Windows,
  NVIDIA/Realtek/Intel/AMD drivers, Visual C++/.NET/DirectX runtimes, Edge,
  Riot Vanguard, VALORANT, Claude or Google Chrome — regardless of options.

  Some apps uninstall fully silently (MSI / those with a quiet uninstall
  string); a few may briefly show their own uninstaller window that needs a
  click. Steam *games* are managed by Steam, so use -NukeSteamLibraries to
  reclaim their disk space directly.
.PARAMETER Confirm
  Actually uninstall / delete. Without it, nothing changes.
.PARAMETER Only
  Optional regex patterns: only target apps whose name matches one of these.
.PARAMETER Keep
  Optional regex patterns: extra apps to protect (in addition to the built-ins).
.PARAMETER NukeSteamLibraries
  Also delete the Steam game files (steamapps\common and \downloading) to
  reclaim their space. Still dry-run unless -Confirm is given.
#>
param(
    [switch]$Confirm,
    [string[]]$Only,
    [string[]]$Keep,
    [switch]$NukeSteamLibraries
)

. "$PSScriptRoot\lib\Common.ps1"

$log = New-ActionLog -Name 'app-uninstall'

# --- Hard protected list: NEVER uninstalled, whatever options are passed. ---
# Grouped for clarity; matched case-insensitively as regex against the app name.
$Protected = @(
    # Your explicit keepers + anti-cheat that Valorant needs
    'VALORANT', 'Riot Vanguard', 'Vanguard', 'Riot Games',
    'Claude',
    'Google Chrome',
    # Hardware vendors / drivers
    'NVIDIA', 'Realtek', 'Intel', 'Advanced Micro Devices', 'AMD ',
    'Synaptics', 'Conexant', 'Qualcomm', 'Killer', 'MediaTek', 'Broadcom',
    # Driver/firmware by name (covers drivers whatever the publisher)
    'HD Audio', 'High Definition Audio', 'Audio Driver', 'Chipset',
    'Wi-?Fi', 'Wireless', 'Bluetooth', 'Ethernet', 'LAN Driver',
    'Network Adapter', 'Graphics Driver', 'Display Driver', 'Serial IO',
    'Management Engine', 'Platform Device', 'Card Reader',
    'Windows Driver Package', 'Driver Package', 'PhysX',
    # Core runtimes / frameworks
    'Microsoft Visual C\+\+', 'Visual C\+\+', '\.NET', 'ASP\.NET', 'MSXML',
    'DirectX', 'GameInput', 'Microsoft GameInput', 'C\+\+ Redistributable',
    # Browser engine / Windows components
    'Microsoft Edge', 'WebView2', 'EdgeUpdate',
    'Microsoft Update Health', 'Update for', 'Security Update', 'KB\d',
    'Windows Software Development', 'Microsoft Windows', 'Windows App',
    # Security software — never strip a PC's protection automatically
    'Windows Defender', 'Microsoft Defender', 'Windows Security',
    'Malwarebytes', 'Avast', 'AVG', 'Bitdefender', 'Norton', 'McAfee',
    'Kaspersky', 'ESET', 'Webroot',
    # Useful keepers
    'WinRAR', '7-Zip', 'OneDrive'
)

# Driver/runtime keywords used as a publisher-based safety net.
$DriverKeywords =
    'driver|redistributable|runtime|\.net|directx|edge|webview|visual c|' +
    'gameinput|health|chipset|audio|wireless|bluetooth|ethernet|lan|wi-?fi|' +
    'graphics|firmware|update|management engine'

function Test-Protected {
    param([string]$Name, [string]$Publisher)
    foreach ($p in $Protected) {
        if ($Name -match $p) { return $true }
    }
    # Belt-and-braces: never touch anything from hardware vendors, and never
    # touch drivers/runtimes/security from Microsoft.
    if ($Publisher -match '(?i)nvidia|realtek|intel|advanced micro devices|qualcomm|synaptics|broadcom|mediatek') {
        return $true
    }
    if ($Publisher -match '(?i)microsoft' -and $Name -match ('(?i)' + $DriverKeywords)) {
        return $true
    }
    return $false
}

function Get-InstalledApps {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = @()
    foreach ($k in $keys) {
        Get-ItemProperty -Path $k -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } | ForEach-Object {
                $size = 0
                if ($_.EstimatedSize) { $size = [int64]$_.EstimatedSize * 1024 }
                $apps += [pscustomobject]@{
                    Name           = [string]$_.DisplayName
                    Publisher      = [string]$_.Publisher
                    SizeBytes      = $size
                    Uninstall      = [string]$_.UninstallString
                    QuietUninstall = [string]$_.QuietUninstallString
                    Key            = [string]$_.PSChildName
                }
            }
    }
    $apps | Sort-Object Name -Unique
}

function Invoke-Uninstall {
    param($App)
    $cmd = $App.QuietUninstall
    $silent = $true
    if (-not $cmd) {
        $u = $App.Uninstall
        if (-not $u) {
            Write-Log ('SKIP {0}: no uninstall command found' -f $App.Name) 'WARN' $log
            return
        }
        if ($u -match '(?i)steam://uninstall') {
            Write-Log ('SKIP {0}: Steam-managed game (use -NukeSteamLibraries)' -f $App.Name) 'WARN' $log
            return
        }
        if ($u -match '(?i)msiexec') {
            $guid = $null
            if ($App.Key -match '^\{[0-9A-Fa-f\-]+\}$') { $guid = $App.Key }
            elseif ($u -match '(\{[0-9A-Fa-f\-]+\})') { $guid = $Matches[1] }
            if ($guid) { $cmd = ('msiexec.exe /x {0} /qn /norestart' -f $guid) }
            else { $cmd = $u; $silent = $false }
        } else {
            $cmd = $u
            $silent = $false
        }
    }
    try {
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
        $note = ''
        if (-not $silent) { $note = ' (its own uninstaller window may have appeared)' }
        $level = 'ACTION'
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { $level = 'WARN' }
        Write-Log ('UNINSTALLED {0} [exit {1}]{2}' -f $App.Name, $p.ExitCode, $note) $level $log
    } catch {
        Write-Log ('FAILED {0}: {1}' -f $App.Name, $_.Exception.Message) 'ERROR' $log
    }
}

# --- Build the candidate list ---
$mode = 'DRY-RUN (nothing will be removed)'
if ($Confirm) { $mode = 'CONFIRM (programs will be uninstalled)' }
Write-Log ('App uninstall starting — mode: {0}' -f $mode) 'INFO' $log

$candidates = Get-InstalledApps | Where-Object { -not (Test-Protected $_.Name $_.Publisher) }

if ($Only) {
    $candidates = $candidates | Where-Object {
        $n = $_.Name
        @($Only | Where-Object { $n -match $_ }).Count -gt 0
    }
}
if ($Keep) {
    $candidates = $candidates | Where-Object {
        $n = $_.Name
        @($Keep | Where-Object { $n -match $_ }).Count -eq 0
    }
}
$candidates = @($candidates)

Write-Host ''
Write-Host ('Programs that WOULD be uninstalled: {0}' -f $candidates.Count) -ForegroundColor White
$candidates | Sort-Object SizeBytes -Descending |
    Select-Object @{ N = 'Size'; E = { if ($_.SizeBytes) { Format-Size $_.SizeBytes } else { '' } } }, Name, Publisher |
    Format-Table -AutoSize | Out-Host

foreach ($c in $candidates) {
    # FAILSAFE: re-verify nothing protected slipped through. If it did, STOP all.
    if (Test-Protected $c.Name $c.Publisher) {
        Write-Log ('FAILSAFE TRIPPED: "{0}" is protected but was about to be uninstalled. STOPPING.' -f $c.Name) 'ERROR' $log
        Write-Host ''
        Write-Host '*** STOPPED ***' -ForegroundColor Red
        Write-Host ('A protected program was about to be uninstalled: {0}' -f $c.Name) -ForegroundColor Red
        Write-Host ('Nothing further was done. Log: {0}' -f $log) -ForegroundColor Yellow
        return
    }
    if ($Confirm) {
        Invoke-Uninstall -App $c
    } else {
        Write-Log ('WOULD UNINSTALL {0}' -f $c.Name) 'DRYRUN' $log
    }
}

# --- Steam game files (optional) ---
if ($NukeSteamLibraries) {
    Write-Host ''
    Write-Host 'Steam game files:' -ForegroundColor White
    $libs = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps'),
        'D:\SteamLibrary\steamapps'
    )
    foreach ($lib in $libs) {
        foreach ($sub in 'common', 'downloading') {
            $path = Join-Path $lib $sub
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $bytes = [int64](Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
            if (-not $Confirm) {
                Write-Log ('WOULD DELETE Steam files: {0}  [{1}]' -f (Format-Size $bytes), $path) 'DRYRUN' $log
            } else {
                Remove-Item -LiteralPath (Join-Path $path '*') -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log ('DELETED Steam files: {0}  [{1}]' -f (Format-Size $bytes), $path) 'ACTION' $log
            }
        }
    }
}

Write-Log '------------------------------------------------------------' 'INFO' $log
if (-not $Confirm) {
    Write-Log ('DRY-RUN complete: {0} program(s) would be removed. Re-run with -Confirm to do it.' -f $candidates.Count) 'DRYRUN' $log
} else {
    Write-Log ('DONE. Uninstalled {0} program(s). Full log: {1}' -f $candidates.Count, $log) 'ACTION' $log
    Write-Log 'A reboot is recommended afterward.' 'INFO' $log
}
