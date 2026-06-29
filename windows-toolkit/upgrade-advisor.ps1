<#
.SYNOPSIS
  Read-only: inspect your hardware and recommend the best upgrades to make this
  PC faster — with the single highest-impact option highlighted and how to do it.
.DESCRIPTION
  Changes nothing. Looks at RAM (and free slots), storage type/space, CPU and
  GPU, then prints prioritized, plain-English upgrade advice. Saves a report.
#>
param()

. "$PSScriptRoot\lib\Common.ps1"

$log = Get-LogPath -Name 'upgrade-advisor'
$lines = New-Object System.Collections.Generic.List[string]
function Add-Line { param([string]$s = '') $lines.Add($s) }

$recs = New-Object System.Collections.Generic.List[object]
function Add-Rec {
    param([int]$Priority, [string]$Title, [string]$Why, [string]$Cost, [string]$How)
    $recs.Add([pscustomobject]@{ Priority = $Priority; Title = $Title; Why = $Why; Cost = $Cost; How = $How })
}

Add-Line '============================================================'
Add-Line ' computa :: Upgrade Advisor (read-only)'
Add-Line (' Generated: {0}' -f (Get-Date))
Add-Line '============================================================'
Add-Line ''
Add-Line 'Your hardware --------------------------------------------'

# --- CPU / GPU ---
$cpuName = 'unknown'
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $cpuName = $cpu.Name.Trim()
    Add-Line ('  CPU : {0}  ({1}C/{2}T)' -f $cpuName, $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
} catch { Add-Line '  CPU : (unknown)' }

$gpuName = ''
try {
    Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
        if ($_.Name) {
            $gpuName = $_.Name
            $vram = ''
            if ($_.AdapterRAM -gt 0) { $vram = ' (' + (Format-Size ([double]$_.AdapterRAM)) + ' VRAM)' }
            Add-Line ('  GPU : {0}{1}' -f $_.Name, $vram)
        }
    }
} catch { }

# --- RAM ---
$installedGB = 0
$slots = 0
$used = 0
$ddr = 'DDR4'
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $installedGB = [math]::Round([double]$cs.TotalPhysicalMemory / 1GB, 0)
    $sticks = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $used = $sticks.Count
    $arr = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($arr -and $arr.MemoryDevices) { $slots = [int]$arr.MemoryDevices }
    if ($sticks.Count -gt 0) {
        switch ([int]$sticks[0].SMBIOSMemoryType) {
            24 { $ddr = 'DDR3' }
            26 { $ddr = 'DDR4' }
            34 { $ddr = 'DDR5' }
            default { $ddr = 'DDR4' }
        }
    }
    $slotText = ''
    if ($slots -gt 0) { $slotText = (' across {0} of {1} slots' -f $used, $slots) }
    Add-Line ('  RAM : {0} GB {1}{2}' -f $installedGB, $ddr, $slotText)
} catch { Add-Line '  RAM : (unknown)' }

# --- Storage ---
$bootIsHDD = $false
$bootSmall = $false
try {
    $sysDrive = ($env:SystemDrive)  # e.g. C:
    $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    Add-Line '  Storage:'
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
        $size = [double]$_.Size; $free = [double]$_.FreeSpace
        Add-Line ('    {0}  {1} free / {2}' -f $_.DeviceID, (Format-Size $free), (Format-Size $size))
    }
    # Determine the boot drive's media type
    try {
        $part = Get-Partition -DriveLetter ($sysDrive.TrimEnd(':')) -ErrorAction Stop
        $disk = $part | Get-Disk -ErrorAction Stop
        $pd = $disks | Where-Object { [string]$_.DeviceId -eq [string]$disk.Number }
        if ($pd -and $pd.MediaType -eq 'HDD') { $bootIsHDD = $true }
    } catch { }
    $sysVol = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $sysDrive) -ErrorAction SilentlyContinue
    if ($sysVol -and $sysVol.Size -gt 0) {
        $freePct = $sysVol.FreeSpace / $sysVol.Size * 100
        if ($freePct -lt 12) { $bootSmall = $true }
    }
} catch { Add-Line '  Storage: (unknown)' }

# ---------------- Recommendations ----------------
if ($installedGB -gt 0 -and $installedGB -le 8) {
    $slotHint = 'Check how many RAM slots are free first'
    if ($slots -gt 0) { $slotHint = ('You have {0} of {1} slots filled' -f $used, $slots) }
    Add-Rec 1 ("Add RAM -> 16 GB (you have {0} GB)" -f $installedGB) `
        "8 GB is the single biggest bottleneck for modern games plus Chrome/Discord. When RAM fills, Windows swaps to disk and everything stutters." `
        '$ (~$30-50)' `
        ("Buy a matching $ddr kit (ideally 2x8GB = 16GB dual-channel). $slotHint. Power off, open the side panel, push the stick(s) into the slot until both clips click, then enable XMP/DOCP in BIOS so it runs at full speed.")
} elseif ($installedGB -gt 0 -and $installedGB -lt 32) {
    Add-Rec 3 ("Consider 32 GB RAM (you have {0} GB)" -f $installedGB) `
        "16 GB is fine for most gaming; 32 GB helps heavy multitasking, streaming or video editing." `
        '$$' `
        ("Add a matching $ddr kit and enable XMP. Only worth it if you stream/edit or keep many apps open.")
}

if ($bootIsHDD) {
    Add-Rec 1 'Move Windows to an SSD' `
        "Your Windows drive is a mechanical HDD — the #1 cause of slow boot and app launches. An SSD is a night-and-day difference." `
        '$ (~$30-60 for 500GB-1TB SATA SSD)' `
        "Buy a 2.5in SATA SSD (or NVMe if your board has an M.2 slot), clone Windows with the free tool from the SSD maker (e.g. Samsung/Crucial), or do a clean Windows reinstall onto it."
}
if ($bootSmall -and -not $bootIsHDD) {
    Add-Rec 2 'Free up / enlarge your Windows SSD' `
        "Your Windows drive is nearly full, which slows the whole system and blocks updates. Keep ~15% free." `
        'Free (cleanup) or $ (bigger SSD)' `
        "First reclaim space (cleanup.ps1, uninstall games, move large files to another drive). If it's still cramped, fit a larger SSD."
}

# Free, no-cost wins (always worth listing)
Add-Rec 4 'Free tune-ups (no money needed)' `
    "Several speed wins cost nothing." `
    'Free' `
    "1) Enable XMP/DOCP in BIOS so RAM runs at rated speed.  2) Set the High Performance power plan (power-plan.ps1).  3) Trim startup apps (startup-audit.ps1).  4) Keep ~15% of your SSD free.  5) Make sure GPU drivers are current."

# GPU note (only if a dedicated GPU is present and CPU is mid-range)
if ($gpuName -and $gpuName -notmatch '(?i)intel|microsoft basic') {
    Add-Rec 5 'GPU upgrade (only if you want higher FPS)' `
        ("Your GPU is '{0}'. If games feel low-FPS at your settings, the graphics card is usually the part to upgrade for gaming." -f $gpuName) `
        '$$$' `
        "Match a new card to your power supply and CPU (avoid pairing a top-end GPU with a much weaker CPU). This is the most expensive upgrade — do RAM/SSD first."
}

# ---------------- Output ----------------
$ordered = $recs | Sort-Object Priority
Add-Line ''
if (@($ordered).Count -gt 0) {
    $best = $ordered | Select-Object -First 1
    Add-Line '★ BEST UPGRADE RIGHT NOW ★ -------------------------------'
    Add-Line ('  {0}' -f $best.Title)
    Add-Line ('  Why : {0}' -f $best.Why)
    Add-Line ('  Cost: {0}' -f $best.Cost)
    Add-Line ('  How : {0}' -f $best.How)
    Add-Line ''
    Add-Line 'All recommendations (best first) --------------------------'
    $n = 0
    foreach ($r in $ordered) {
        $n++
        Add-Line ''
        Add-Line ('  {0}. {1}   [cost: {2}]' -f $n, $r.Title, $r.Cost)
        Add-Line ('     Why: {0}' -f $r.Why)
        Add-Line ('     How: {0}' -f $r.How)
    }
} else {
    Add-Line 'Could not read enough hardware info to advise (run on the Windows PC).'
}

Add-Line ''
Add-Line ('Report saved to: {0}' -f $log)
$lines | Tee-Object -FilePath $log
