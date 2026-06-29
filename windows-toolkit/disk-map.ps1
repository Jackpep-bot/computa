<#
.SYNOPSIS
  Read-only: list the 30 largest files and 20 largest folders under a path.
.PARAMETER Path
  Folder to scan. Default C:\
.PARAMETER MinFileMB
  Performance floor: only consider files at least this big as "large file"
  candidates (folder totals still count every file). Default 10.
#>
param(
    [string]$Path = 'C:\',
    [int]$MinFileMB = 10
)

. "$PSScriptRoot\lib\Common.ps1"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Log ("Path not found: {0}" -f $Path) 'ERROR'
    return
}
$root = (Resolve-Path -LiteralPath $Path).Path

Write-Log ("Scanning {0} (this can take a while on a full drive)..." -f $root) 'INFO'

$floor = [int64]$MinFileMB * 1MB
$dirTotals = @{}
$bigFiles = New-Object System.Collections.Generic.List[object]

Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $len = [int64]$_.Length
    if ($len -ge $floor) {
        $bigFiles.Add([pscustomobject]@{ SizeBytes = $len; Path = $_.FullName })
    }
    $dir = $_.DirectoryName
    while ($dir) {
        if ($dirTotals.ContainsKey($dir)) { $dirTotals[$dir] += $len } else { $dirTotals[$dir] = $len }
        if ($dir -eq $root) { break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
}

$topFiles = $bigFiles | Sort-Object SizeBytes -Descending | Select-Object -First 30 | ForEach-Object {
    [pscustomobject]@{ Size = (Format-Size $_.SizeBytes); SizeBytes = $_.SizeBytes; Path = $_.Path }
}
$topDirs = $dirTotals.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object {
    [pscustomobject]@{ Size = (Format-Size $_.Value); SizeBytes = [int64]$_.Value; Path = $_.Key }
}

Write-Host ''
Write-Host ('Top 30 largest files under {0}' -f $root) -ForegroundColor White
$topFiles | Format-Table -AutoSize Size, Path | Out-Host

Write-Host ''
Write-Host ('Top 20 largest folders under {0}' -f $root) -ForegroundColor White
$topDirs | Format-Table -AutoSize Size, Path | Out-Host

$filesCsv = Get-LogPath -Name 'disk-map-files' -Extension 'csv'
$dirsCsv  = Get-LogPath -Name 'disk-map-folders' -Extension 'csv'
$topFiles | Export-Csv -LiteralPath $filesCsv -NoTypeInformation -Encoding UTF8
$topDirs  | Export-Csv -LiteralPath $dirsCsv -NoTypeInformation -Encoding UTF8

Write-Log ('Saved largest-files CSV : {0}' -f $filesCsv) 'INFO'
Write-Log ('Saved largest-folders CSV: {0}' -f $dirsCsv) 'INFO'
