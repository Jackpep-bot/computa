<#
.SYNOPSIS
  Clear known-safe junk: TEMP, Windows TEMP, browser caches, Recycle Bin,
  Windows Update download cache.
.DESCRIPTION
  DRY-RUN by default: shows what WOULD be deleted and how much space would be
  freed. Pass -Confirm to actually delete. Everything is logged. Only the
  known-safe paths from Get-JunkTargets (plus the Recycle Bin) are ever touched.
.PARAMETER Confirm
  Actually delete. Without it, nothing is removed.
#>
param(
    [switch]$Confirm
)

. "$PSScriptRoot\lib\Common.ps1"

$log = New-ActionLog -Name 'cleanup'
$mode = 'DRY-RUN (nothing will be deleted)'
if ($Confirm) { $mode = 'CONFIRM (files will be deleted)' }
Write-Log ('Cleanup starting — mode: {0}' -f $mode) 'INFO' -Path $log

$totalBytes = [int64]0
$totalFiles = 0

foreach ($t in Get-JunkTargets) {
    if ($t.NeedsAdmin -and -not (Test-IsAdmin)) {
        Write-Log ('SKIP {0}: needs Administrator (re-run as admin to include it)' -f $t.Label) 'WARN' -Path $log
        continue
    }

    $files = @(Get-ChildItem -LiteralPath $t.Path -Recurse -File -Force -ErrorAction SilentlyContinue)
    $bytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    $count = $files.Count

    if (-not $Confirm) {
        Write-Log ('WOULD DELETE {0}: {1} in {2} files  [{3}]' -f $t.Label, (Format-Size $bytes), $count, $t.Path) 'DRYRUN' -Path $log
        $totalBytes += $bytes
        $totalFiles += $count
        continue
    }

    $freed = [int64]0
    $del = 0
    $fail = 0
    foreach ($f in $files) {
        try {
            $sz = [int64]$f.Length
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $freed += $sz
            $del++
        } catch {
            $fail++
        }
    }
    Write-Log ('DELETED {0}: {1} freed in {2} files ({3} skipped/in-use)' -f $t.Label, (Format-Size $freed), $del, $fail) 'ACTION' -Path $log
    $totalBytes += $freed
    $totalFiles += $del
}

# --- Recycle Bin (special handling) ---
$rbBytes = Get-RecycleBinSize
if (-not $Confirm) {
    if ($null -ne $rbBytes) {
        Write-Log ('WOULD EMPTY Recycle Bin: {0}' -f (Format-Size $rbBytes)) 'DRYRUN' -Path $log
        $totalBytes += $rbBytes
    } else {
        Write-Log 'WOULD EMPTY Recycle Bin: (size unknown)' 'DRYRUN' -Path $log
    }
} else {
    try {
        Clear-RecycleBin -Force -Confirm:$false -ErrorAction Stop
        $freedRb = 0
        if ($null -ne $rbBytes) { $freedRb = $rbBytes }
        Write-Log ('EMPTIED Recycle Bin: {0}' -f (Format-Size $freedRb)) 'ACTION' -Path $log
        $totalBytes += $freedRb
    } catch {
        Write-Log ('Recycle Bin: could not empty ({0})' -f $_.Exception.Message) 'WARN' -Path $log
    }
}

Write-Log '------------------------------------------------------------' 'INFO' -Path $log
if (-not $Confirm) {
    Write-Log ('DRY-RUN total: {0} reclaimable across {1} files. Re-run with -Confirm to delete.' -f (Format-Size $totalBytes), $totalFiles) 'DRYRUN' -Path $log
} else {
    Write-Log ('DONE: {0} freed across {1} files. Log: {2}' -f (Format-Size $totalBytes), $totalFiles, $log) 'ACTION' -Path $log
}
