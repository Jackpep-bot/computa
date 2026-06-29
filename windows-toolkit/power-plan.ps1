<#
.SYNOPSIS
  Report the active power plan; switch to Balanced/High Performance only with -Confirm.
.DESCRIPTION
  DRY-RUN by default: reports the active plan and warns if the PC is on a
  power-saver plan that can slow it down. With -Confirm it switches to the plan
  given by -Plan (default High).
.PARAMETER Plan
  Balanced or High. Used only with -Confirm.
#>
param(
    [ValidateSet('Balanced', 'High')][string]$Plan = 'High',
    [switch]$Confirm
)

. "$PSScriptRoot\lib\Common.ps1"

$log = New-ActionLog -Name 'power-plan'

$guids = @{
    Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    High     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    Saver    = 'a1841308-3541-4fab-bc81-f71556f20b4a'
}

$active = & powercfg.exe '/getactivescheme' 2>&1 | Out-String
Write-Log ('Active power plan: {0}' -f $active.Trim()) 'INFO' -Path $log

$onSaver = $active -match $guids.Saver
if ($onSaver) {
    Write-Log 'You are on the POWER SAVER plan — this can throttle CPU and slow the PC.' 'WARN' -Path $log
}

if (-not $Confirm) {
    Write-Log ('DRY-RUN: report only. Re-run with -Confirm to switch to {0}.' -f $Plan) 'DRYRUN' -Path $log
    return
}

$target = $guids[$Plan]
try {
    & powercfg.exe '/setactive' $target 2>&1 | Out-Null
    Write-Log ('Switched active power plan to {0}.' -f $Plan) 'ACTION' -Path $log
} catch {
    Write-Log ('Could not switch power plan: {0}' -f $_.Exception.Message) 'ERROR' -Path $log
}
