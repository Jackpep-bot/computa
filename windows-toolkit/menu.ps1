<#
.SYNOPSIS
  Master menu for the computa Windows cleanup toolkit.
.DESCRIPTION
  Runs the scripts in a sensible order (protect first, diagnose, audits, then
  the destructive actions last). Destructive scripts run as a DRY-RUN/report
  first; you must type APPLY to re-run them with -Confirm. Before the heavy
  disk scans, if SMART health is anything other than Healthy, it warns you to
  back up first.
#>
param()

. "$PSScriptRoot\lib\Common.ps1"

$script:RestoreDone = $false

function Invoke-Script {
    param([string]$Name, [hashtable]$Params = @{})
    & (Join-Path $PSScriptRoot $Name) @Params
}

function Invoke-Destructive {
    param([string]$Name, [hashtable]$Params = @{}, [string]$ApplyWarning = '')
    if (-not $script:RestoreDone) {
        Write-Host 'Tip: consider creating a System Restore point first (option 1).' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host ('Running {0} as a PREVIEW (nothing will be changed)...' -f $Name) -ForegroundColor Cyan
    Invoke-Script -Name $Name -Params $Params
    if ($ApplyWarning) { Write-Host $ApplyWarning -ForegroundColor Yellow }
    $ans = Read-Host 'Apply these changes for real now? Type APPLY to confirm (anything else cancels)'
    if ($ans -eq 'APPLY') {
        $p = $Params.Clone()
        $p['Confirm'] = $true
        Invoke-Script -Name $Name -Params $p
    } else {
        Write-Host 'Cancelled — no changes made.' -ForegroundColor Gray
    }
}

function Confirm-HeavyScan {
    $h = Test-DiskHealthy
    if ($h -eq $false) {
        Write-Host ''
        Write-Host '  *** WARNING: disk SMART status is NOT "Healthy". ***' -ForegroundColor Red
        Write-Host '  A heavy scan stresses a failing disk. BACK UP your important files first.' -ForegroundColor Red
        $a = Read-Host '  Type YES to proceed anyway'
        return ($a -eq 'YES')
    } elseif ($null -eq $h) {
        Write-Host '  (Could not read SMART status — proceed with normal caution.)' -ForegroundColor Yellow
    }
    return $true
}

function Show-Menu {
    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor White
    Write-Host '  computa :: Windows cleanup & speed-up toolkit' -ForegroundColor White
    Write-Host '  Read-only audits are safe. Destructive steps preview first,' -ForegroundColor Gray
    Write-Host '  and only act when you type APPLY / use -Confirm.' -ForegroundColor Gray
    Write-Host '==============================================================' -ForegroundColor White
    Write-Host '  PROTECT'
    Write-Host '   1) Create System Restore point      (do this before changes)'
    Write-Host '  DIAGNOSE (read-only)'
    Write-Host '   2) Diagnose - full health report'
    Write-Host '   3) Health summary (copy back for advice)'
    Write-Host '   a) Upgrade advisor - best hardware upgrade for your PC + how-to'
    Write-Host '   u) Update toolkit - pull the latest scripts into THIS folder'
    Write-Host '   4) Disk map - biggest files/folders        [heavy scan]'
    Write-Host '   5) Profile bloat - biggest profile folders'
    Write-Host '   6) Find clutter - big/stale/duplicate files [heavy scan]'
    Write-Host '   7) Programs audit - installed apps by size'
    Write-Host '   8) Services audit - Automatic services'
    Write-Host '   9) Startup audit - what launches at boot'
    Write-Host '  10) Bloatware audit - Store/preinstalled apps'
    Write-Host '  11) Event errors - recurring crashes/errors'
    Write-Host '  ADJUST (preview, then APPLY)'
    Write-Host '  12) Power plan - report / switch to High Performance'
    Write-Host '  13) Network - flush DNS / reset stack (reboot)'
    Write-Host '  14) Optimize drives - TRIM SSD / defrag HDD'
    Write-Host '  15) System repair - SFC/DISM scan / repair'
    Write-Host '  CLEAN (last)'
    Write-Host '  16) Cleanup junk - preview, then APPLY to delete'
    Write-Host '  17) Uninstall apps - remove ALL non-essential programs +'
    Write-Host '                       Steam games (keeps Valorant/Claude/Chrome/drivers)'
    Write-Host '   d) Desktop sweep - clear Desktop clutter + old project copies'
    Write-Host '                       (keeps the toolkit in use + your inventory; failsafe stops on danger)'
    Write-Host '   q) Quit'
    Write-Host ''
}

while ($true) {
    Show-Menu
    $choice = (Read-Host 'Choose an option').Trim().ToLower()
    switch ($choice) {
        '1'  { Invoke-Script 'restore-point.ps1'; $script:RestoreDone = $true }
        '2'  { Invoke-Script 'diagnose.ps1' }
        '3'  { Invoke-Script 'health-report.ps1' }
        'a'  { Invoke-Script 'upgrade-advisor.ps1' }
        'u'  { Invoke-Script 'update.ps1' }
        '4'  { if (Confirm-HeavyScan) { $p = Read-Host 'Folder to scan (Enter for C:\)'; if ([string]::IsNullOrWhiteSpace($p)) { $p = 'C:\' }; Invoke-Script 'disk-map.ps1' @{ Path = $p } } }
        '5'  { Invoke-Script 'profile-bloat.ps1' }
        '6'  { if (Confirm-HeavyScan) { $p = Read-Host 'Folder to scan (Enter for your profile)'; if ([string]::IsNullOrWhiteSpace($p)) { $p = $env:USERPROFILE }; Invoke-Script 'find-clutter.ps1' @{ Path = $p } } }
        '7'  { Invoke-Script 'programs-audit.ps1' }
        '8'  { Invoke-Script 'services-audit.ps1' }
        '9'  { Invoke-Script 'startup-audit.ps1' }
        '10' { Invoke-Script 'bloatware-audit.ps1' }
        '11' { Invoke-Script 'event-errors.ps1' }
        '12' { Invoke-Destructive 'power-plan.ps1' @{ Plan = 'High' } }
        '13' { Invoke-Destructive 'network-reset.ps1' @{} '  NOTE: applying a stack reset REQUIRES A REBOOT.' }
        '14' { Invoke-Destructive 'optimize-drives.ps1' @{} }
        '15' { Invoke-Destructive 'system-repair.ps1' @{} }
        '16' { Invoke-Destructive 'cleanup.ps1' @{} '  This will permanently delete junk files when applied.' }
        '17' { Invoke-Destructive 'app-uninstall.ps1' @{ NukeSteamLibraries = $true; AutoConfirm = $true } '  This UNINSTALLS all non-essential programs (silently where possible) and DELETES Steam game files. Keeps Valorant, Claude, Chrome, Windows and drivers.' }
        'd'  { Invoke-Destructive 'safe-sweep.ps1' @{ All = $true } '  This clears your Desktop. The toolkit folder in use and MY-PC-INVENTORY are protected; a failsafe stops everything if anything protected is touched.' }
        'q'  { Write-Host 'Bye.'; return }
        ''   { }
        default { Write-Host ('Unknown option: {0}' -f $choice) -ForegroundColor Yellow }
    }
    if ($choice -ne 'q') {
        Write-Host ''
        [void](Read-Host 'Press Enter to return to the menu')
    }
}
