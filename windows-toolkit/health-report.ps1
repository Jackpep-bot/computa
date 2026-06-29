<#
.SYNOPSIS
  Read-only: one dated summary of the key findings (disk health, disk space,
  top errors, startup count, drive optimization status) to copy back for advice.
.DESCRIPTION
  Changes nothing. Saves a single timestamped .txt summary in logs\.
#>
param(
    [int]$ErrorDays = 7
)

. "$PSScriptRoot\lib\Common.ps1"

$log = Get-LogPath -Name 'health-report'
$lines = New-Object System.Collections.Generic.List[string]
function R { param([string]$s = '') $lines.Add($s) }

R '============================================================'
R ' computa :: Combined Health Summary (read-only)'
R (' Generated: {0}   Computer: {1}' -f (Get-Date), $env:COMPUTERNAME)
R '============================================================'

# OS / uptime
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $up = (Get-Date) - $os.LastBootUpTime
    R (' OS: {0} (build {1}) | Uptime: {2}d {3}h' -f $os.Caption.Trim(), $os.BuildNumber, $up.Days, $up.Hours)
} catch { }

R ''
R 'Disk space --------------------------------------------------'
try {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
        $size = [double]$_.Size; $free = [double]$_.FreeSpace
        $pct = 0; if ($size -gt 0) { $pct = [math]::Round(($size - $free) / $size * 100, 1) }
        R ('  {0}  {1,9} free of {2,9}  ({3}% full)' -f $_.DeviceID, (Format-Size $free), (Format-Size $size), $pct)
    }
} catch { R '  (unavailable)' }

R ''
R 'Disk health (SMART) + type ---------------------------------'
$health = Get-DiskHealth
if (@($health).Count -eq 0) {
    R '  (could not read SMART/health status)'
} else {
    foreach ($d in $health) {
        $sz = 'n/a'; if ($d.SizeBytes) { $sz = Format-Size $d.SizeBytes }
        R ('  {0,-30} {1,-8} {2,9}  status: {3}' -f $d.Name, $d.MediaType, $sz, $d.HealthStatus)
    }
}

R ''
R 'Startup ----------------------------------------------------'
try { R ('  {0} startup entries' -f @(Get-StartupEntries).Count) } catch { R '  (unavailable)' }

R ''
R ('Top errors (last {0} days) --------------------------------' -f $ErrorDays)
try {
    $start = (Get-Date).AddDays(-1 * $ErrorDays)
    $ev = New-Object System.Collections.Generic.List[object]
    foreach ($ln in 'System', 'Application') {
        try {
            Get-WinEvent -FilterHashtable @{ LogName = $ln; Level = 1, 2; StartTime = $start } -ErrorAction Stop |
                ForEach-Object { $ev.Add($_) }
        } catch { }
    }
    if (@($ev).Count -eq 0) {
        R '  none — good news'
    } else {
        $ev | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
            R ('  {0,5}x  {1}' -f $_.Count, $_.Name)
        }
    }
} catch { R '  (unavailable)' }

R ''
R ('Summary saved to: {0}' -f $log)

$lines | Tee-Object -FilePath $log
