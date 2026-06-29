<#
.SYNOPSIS
  Create a System Restore point before making changes.
.DESCRIPTION
  Run this FIRST, before any cleanup/repair/optimize. Needs Administrator and
  System Restore enabled on the system drive. Warns (with enable instructions)
  if System Restore is off.
.PARAMETER Label
  Description for the restore point.
#>
param(
    [string]$Label = 'computa toolkit - before cleanup'
)

. "$PSScriptRoot\lib\Common.ps1"

$log = New-ActionLog -Name 'restore-point'

if (-not (Test-IsAdmin)) {
    Write-Log 'This needs Administrator. Right-click PowerShell > Run as administrator, then re-run.' 'ERROR' -Path $log
    return
}

$before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
Write-Log ('Creating System Restore point: "{0}"...' -f $Label) 'INFO' -Path $log

try {
    Checkpoint-Computer -Description $Label -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
} catch {
    Write-Log ('Could not create a restore point: {0}' -f $_.Exception.Message) 'ERROR' -Path $log
    Write-Log 'System Restore may be DISABLED. To enable it:' 'WARN' -Path $log
    Write-Log '  1) Start > "Create a restore point" > System Protection tab' 'INFO' -Path $log
    Write-Log '  2) Select your C: drive > Configure > "Turn on system protection" > OK' 'INFO' -Path $log
    Write-Log '  or in admin PowerShell:  Enable-ComputerRestore -Drive "C:\"' 'INFO' -Path $log
    return
}

$after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
if ($after -gt $before) {
    Write-Log ('Restore point created: "{0}".' -f $Label) 'ACTION' -Path $log
} else {
    Write-Log 'No new restore point appeared. Windows allows only one per 24h by default.' 'WARN' -Path $log
    Write-Log 'To allow more, set (admin): HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore\SystemRestorePointCreationFrequency = 0' 'INFO' -Path $log
}
