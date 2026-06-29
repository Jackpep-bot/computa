<#
.SYNOPSIS
  Report drive type (SSD/HDD) and optimization status; optimize only with -Confirm.
.DESCRIPTION
  DRY-RUN by default: detects SSD vs HDD per fixed drive and reports the
  recommended action and a fragmentation analysis. With -Confirm it TRIMs SSDs
  (ReTrim) and defragments HDDs (Defrag). It will NEVER defrag an SSD, and skips
  any drive whose media type can't be confirmed. Needs Administrator to optimize.
#>
param(
    [switch]$Confirm
)

. "$PSScriptRoot\lib\Common.ps1"

$log = New-ActionLog -Name 'optimize-drives'

function Get-DriveMedia {
    param([char]$Letter)
    try {
        $part = Get-Partition -DriveLetter $Letter -ErrorAction Stop
        $disk = $part | Get-Disk -ErrorAction Stop
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$disk.Number }
        if ($pd) { return [string]$pd.MediaType }
    } catch { }
    return 'Unknown'
}

$vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter })
if ($vols.Count -eq 0) {
    Write-Log 'No fixed drives with letters found.' 'WARN' -Path $log
    return
}

foreach ($v in $vols) {
    $letter = $v.DriveLetter
    $media = Get-DriveMedia -Letter $letter
    Write-Log ('Drive {0}: media = {1}' -f $letter, $media) 'INFO' -Path $log

    # Read-only analysis snapshot.
    try {
        $analysis = & defrag.exe ("{0}:" -f $letter) '/A' '/V' 2>&1 | Out-String
        ($analysis) | Add-Content -LiteralPath $log
    } catch { }

    if ($media -eq 'SSD') {
        if ($Confirm) {
            if (-not (Test-IsAdmin)) { Write-Log ('Drive {0}: TRIM needs Administrator — skipped.' -f $letter) 'WARN' -Path $log; continue }
            try {
                Optimize-Volume -DriveLetter $letter -ReTrim -ErrorAction Stop
                Write-Log ('Drive {0}: TRIM (ReTrim) completed.' -f $letter) 'ACTION' -Path $log
            } catch { Write-Log ('Drive {0}: TRIM failed - {1}' -f $letter, $_.Exception.Message) 'ERROR' -Path $log }
        } else {
            Write-Log ('Drive {0}: SSD -> would TRIM (ReTrim).' -f $letter) 'DRYRUN' -Path $log
        }
    } elseif ($media -eq 'HDD') {
        if ($Confirm) {
            if (-not (Test-IsAdmin)) { Write-Log ('Drive {0}: defrag needs Administrator — skipped.' -f $letter) 'WARN' -Path $log; continue }
            try {
                Optimize-Volume -DriveLetter $letter -Defrag -ErrorAction Stop
                Write-Log ('Drive {0}: defragment completed.' -f $letter) 'ACTION' -Path $log
            } catch { Write-Log ('Drive {0}: defrag failed - {1}' -f $letter, $_.Exception.Message) 'ERROR' -Path $log }
        } else {
            Write-Log ('Drive {0}: HDD -> would defragment.' -f $letter) 'DRYRUN' -Path $log
        }
    } else {
        Write-Log ('Drive {0}: media UNKNOWN -> skipping (will never defrag an unconfirmed drive).' -f $letter) 'WARN' -Path $log
    }
}

if (-not $Confirm) {
    Write-Log 'DRY-RUN: report only. Re-run with -Confirm to optimize.' 'DRYRUN' -Path $log
}
