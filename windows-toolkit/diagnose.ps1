<#
.SYNOPSIS
  Read-only health report: disk, SMART, RAM, CPU, top processes, startup, OS, uptime.
.NOTES
  Strictly read-only. Prints to console and saves a timestamped .txt in logs\.
#>
param()

. "$PSScriptRoot\lib\Common.ps1"

$log = Get-LogPath -Name 'diagnose'
$lines = New-Object System.Collections.Generic.List[string]
function Add-Line { param([string]$s = '') $lines.Add($s) }

Add-Line '============================================================'
Add-Line ' computa :: System Health Report (read-only)'
Add-Line (' Generated: {0}' -f (Get-Date))
Add-Line '============================================================'
Add-Line ''

# --- OS / uptime ---
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $boot = $os.LastBootUpTime
    $up = (Get-Date) - $boot
    Add-Line ('Windows : {0} (build {1})' -f $os.Caption.Trim(), $os.BuildNumber)
    Add-Line ('Uptime  : {0}d {1}h {2}m  (last boot {3})' -f $up.Days, $up.Hours, $up.Minutes, $boot)
} catch { Add-Line 'Windows : (could not read OS info)' }

# --- CPU ---
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    Add-Line ('CPU     : {0}  ({1} cores / {2} threads)' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
} catch { Add-Line 'CPU     : (unknown)' }

# --- RAM ---
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $totalB = [double]$os.TotalVisibleMemorySize * 1024
    $freeB  = [double]$os.FreePhysicalMemory * 1024
    $usedB  = $totalB - $freeB
    $pct = 0
    if ($totalB -gt 0) { $pct = [math]::Round($usedB / $totalB * 100, 0) }
    Add-Line ('RAM     : {0} used of {1}  ({2}% in use)' -f (Format-Size $usedB), (Format-Size $totalB), $pct)
} catch { Add-Line 'RAM     : (unknown)' }

Add-Line ''
Add-Line 'Disks ------------------------------------------------------'
try {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
        $size = [double]$_.Size
        $free = [double]$_.FreeSpace
        $pct = 0
        if ($size -gt 0) { $pct = [math]::Round(($size - $free) / $size * 100, 1) }
        Add-Line ('  {0}  {1,9} free of {2,9}   {3,5}% full' -f $_.DeviceID, (Format-Size $free), (Format-Size $size), $pct)
    }
} catch { Add-Line '  (could not read disks)' }

Add-Line ''
Add-Line 'Disk health (SMART) ----------------------------------------'
$health = Get-DiskHealth
if (@($health).Count -eq 0) {
    Add-Line '  (could not read SMART/health status on this system)'
} else {
    foreach ($d in $health) {
        $sz = 'n/a'
        if ($d.SizeBytes) { $sz = Format-Size $d.SizeBytes }
        Add-Line ('  {0,-32} {1,-8} {2,9}  status: {3}' -f $d.Name, $d.MediaType, $sz, $d.HealthStatus)
    }
}

Add-Line ''
Add-Line 'Top 10 processes by RAM ------------------------------------'
try {
    Get-Process -ErrorAction Stop | Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 | ForEach-Object {
            Add-Line ('  {0,10}  {1}' -f (Format-Size $_.WorkingSet64), $_.ProcessName)
        }
} catch { Add-Line '  (could not read processes)' }

Add-Line ''
Add-Line 'Top 10 processes by CPU time -------------------------------'
try {
    Get-Process -ErrorAction Stop | Sort-Object CPU -Descending |
        Select-Object -First 10 | ForEach-Object {
            $c = 0
            if ($_.CPU) { $c = [math]::Round($_.CPU, 0) }
            Add-Line ('  {0,9}s  {1}' -f $c, $_.ProcessName)
        }
} catch { Add-Line '  (could not read processes)' }

Add-Line ''
Add-Line 'Startup -----------------------------------------------------'
try {
    $count = @(Get-StartupEntries).Count
    Add-Line ('  {0} startup entries (run startup-audit.ps1 for the full list)' -f $count)
} catch { Add-Line '  (could not read startup entries)' }

Add-Line ''
Add-Line ('Report saved to: {0}' -f $log)

$lines | Tee-Object -FilePath $log
