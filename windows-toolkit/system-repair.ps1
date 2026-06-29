<#
.SYNOPSIS
  Check Windows system files for corruption (SFC + DISM), repair only with -Confirm.
.DESCRIPTION
  DRY-RUN by default: runs DISM CheckHealth/ScanHealth and SFC /VERIFYONLY
  (all read-only) and reports whether corruption was found. With -Confirm it
  runs DISM /RestoreHealth and SFC /SCANNOW to repair. Full output is logged.
  Needs Administrator.
#>
param(
    [switch]$Confirm
)

. "$PSScriptRoot\lib\Common.ps1"

$log = New-ActionLog -Name 'system-repair'

if (-not (Test-IsAdmin)) {
    Write-Log 'This needs Administrator. Run PowerShell as administrator and re-run.' 'ERROR' -Path $log
    return
}

function Invoke-Native {
    param([string]$Exe, [string[]]$Args, [string]$Label)
    Write-Log ('Running: {0} {1}' -f $Exe, ($Args -join ' ')) 'INFO' -Path $log
    $out = & $Exe @Args 2>&1
    ($out | Out-String) | Add-Content -LiteralPath $log
    return ($out | Out-String)
}

Write-Log 'Read-only health checks (this can take several minutes)...' 'INFO' -Path $log
$check = Invoke-Native 'dism.exe' @('/Online','/Cleanup-Image','/CheckHealth') 'DISM CheckHealth'
$scan  = Invoke-Native 'dism.exe' @('/Online','/Cleanup-Image','/ScanHealth') 'DISM ScanHealth'
$sfc   = Invoke-Native 'sfc.exe'  @('/verifyonly') 'SFC verify'

$corruption = $false
if ($scan -match '(?i)repairable' -or $check -match '(?i)repairable') { $corruption = $true }
if ($sfc -match '(?i)integrity violations' -and $sfc -notmatch '(?i)did not find any integrity violations') { $corruption = $true }

Write-Log '------------------------------------------------------------' 'INFO' -Path $log
if ($corruption) {
    Write-Log 'RESULT: corruption indicators FOUND. A repair is recommended.' 'WARN' -Path $log
} else {
    Write-Log 'RESULT: no corruption detected by the read-only scans.' 'INFO' -Path $log
}

if (-not $Confirm) {
    Write-Log 'DRY-RUN: scans only. Re-run with -Confirm to actually repair.' 'DRYRUN' -Path $log
    return
}

Write-Log 'Repairing (DISM /RestoreHealth, then SFC /SCANNOW)...' 'ACTION' -Path $log
[void](Invoke-Native 'dism.exe' @('/Online','/Cleanup-Image','/RestoreHealth') 'DISM RestoreHealth')
[void](Invoke-Native 'sfc.exe'  @('/scannow') 'SFC scannow')
Write-Log ('Repair finished. Full output in: {0}' -f $log) 'ACTION' -Path $log
