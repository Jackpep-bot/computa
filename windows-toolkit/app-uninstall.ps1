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
    [switch]$NukeSteamLibraries,
    [switch]$AutoConfirm,   # run uninstallers silently so you don't have to click
    [switch]$AutoClick      # extra: auto-press Enter on any uninstaller window that still appears
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

# Build the most-silent uninstall command we can, by detecting the installer
# engine. This is what lets you walk away — most uninstallers can run with no UI.
function Get-UninstallCommand {
    param($App)
    if ($App.QuietUninstall) { return @{ Cmd = $App.QuietUninstall; Silent = $true } }
    $u = $App.Uninstall
    if (-not $u) { return @{ Skip = 'no uninstall command found' } }
    if ($u -match '(?i)steam://uninstall') { return @{ Skip = 'Steam-managed game (use -NukeSteamLibraries)' } }

    if ($u -match '(?i)msiexec') {
        $guid = $null
        if ($App.Key -match '^\{[0-9A-Fa-f\-]+\}$') { $guid = $App.Key }
        elseif ($u -match '(\{[0-9A-Fa-f\-]+\})') { $guid = $Matches[1] }
        if ($guid) { return @{ Cmd = ('msiexec.exe /x {0} /qn /norestart' -f $guid); Silent = $true } }
        return @{ Cmd = $u; Silent = $false }
    }

    $exe = Get-ExePath $u
    $low = ([string]$exe).ToLower()
    # Inno Setup uninstaller (unins000.exe, unins001.exe, ...)
    if ($low -match 'unins[0-9]*\.exe$') {
        return @{ Cmd = ('"{0}" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -f $exe); Silent = $true }
    }
    # NSIS-style uninstaller (Uninstall.exe / uninst*.exe) supports /S
    if ($low -match 'uninstall\.exe$' -or $low -match 'uninst[^\\]*\.exe$') {
        return @{ Cmd = ('"{0}" /S' -f $exe); Silent = $true }
    }
    # Unknown engine: in AutoConfirm mode try a silent switch best-effort.
    if ($AutoConfirm) { return @{ Cmd = ('"{0}" /S' -f $exe); Silent = $false } }
    return @{ Cmd = $u; Silent = $false }
}

function Invoke-Uninstall {
    param($App)
    $plan = Get-UninstallCommand -App $App
    if ($plan.Skip) {
        Write-Log ('SKIP {0}: {1}' -f $App.Name, $plan.Skip) 'WARN' $log
        return
    }
    $cmd = $plan.Cmd
    $silent = [bool]$plan.Silent
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

# Optional auto-clicker: a background watcher that presses Enter on any window
# whose title looks like an uninstaller (uninstall/setup/remove/wizard), so the
# rare GUI uninstaller advances itself while you're away. Best-effort.
$clickJob = $null
if ($Confirm -and $AutoClick) {
    Write-Log 'AutoClick on: will press Enter on uninstaller windows that appear.' 'INFO' $log
    $clickJob = Start-Job -ScriptBlock {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FgWin {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
}
'@
        while ($true) {
            Start-Sleep -Milliseconds 1500
            $h = [FgWin]::GetForegroundWindow()
            $sb = New-Object System.Text.StringBuilder 256
            [void][FgWin]::GetWindowText($h, $sb, 256)
            $title = $sb.ToString()
            if ($title -match '(?i)uninstall|setup|remove|wizard|installshield|install') {
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
            }
        }
    }
}

foreach ($c in $candidates) {
    # FAILSAFE: re-verify nothing protected slipped through. If it did, STOP all.
    if (Test-Protected $c.Name $c.Publisher) {
        Write-Log ('FAILSAFE TRIPPED: "{0}" is protected but was about to be uninstalled. STOPPING.' -f $c.Name) 'ERROR' $log
        Write-Host ''
        Write-Host '*** STOPPED ***' -ForegroundColor Red
        Write-Host ('A protected program was about to be uninstalled: {0}' -f $c.Name) -ForegroundColor Red
        Write-Host ('Nothing further was done. Log: {0}' -f $log) -ForegroundColor Yellow
        if ($clickJob) { Stop-Job $clickJob -ErrorAction SilentlyContinue; Remove-Job $clickJob -Force -ErrorAction SilentlyContinue }
        return
    }
    if ($Confirm) {
        Invoke-Uninstall -App $c
    } else {
        Write-Log ('WOULD UNINSTALL {0}' -f $c.Name) 'DRYRUN' $log
    }
}

if ($clickJob) {
    Stop-Job $clickJob -ErrorAction SilentlyContinue
    Remove-Job $clickJob -Force -ErrorAction SilentlyContinue
}

# --- Steam game files (optional) ---
if ($NukeSteamLibraries) {
    Write-Host ''
    Write-Host 'Steam game files:' -ForegroundColor White

    # Auto-detect Steam library locations across every fixed drive (not just C:).
    $libs = New-Object System.Collections.Generic.List[string]
    $driveRoots = @()
    try {
        $driveRoots = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop |
            ForEach-Object { $_.DeviceID + '\' }
    } catch {
        $driveRoots = @('C:\', 'D:\')
    }
    foreach ($root in $driveRoots) {
        foreach ($cand in @(
                (Join-Path $root 'Program Files (x86)\Steam\steamapps'),
                (Join-Path $root 'Steam\steamapps'),
                (Join-Path $root 'SteamLibrary\steamapps'),
                (Join-Path $root 'Games\Steam\steamapps'),
                (Join-Path $root 'SteamGames\steamapps'))) {
            if ((Test-Path -LiteralPath $cand) -and ($libs -notcontains $cand)) { $libs.Add($cand) }
        }
    }
    if ($libs.Count -eq 0) { Write-Log 'No Steam library folders found.' 'INFO' $log }

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
