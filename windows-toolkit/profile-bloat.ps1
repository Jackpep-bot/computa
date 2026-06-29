<#
.SYNOPSIS
  Read-only: list the largest folders inside your user profile, biggest first.
.DESCRIPTION
  Helps you target manual cleanup (AppData, Downloads, Desktop, etc.). Never
  deletes. Prints a table and writes a CSV.
.PARAMETER Path
  Profile root to scan. Default %USERPROFILE%.
#>
param(
    [string]$Path = $env:USERPROFILE,
    [int]$Depth = 2
)

. "$PSScriptRoot\lib\Common.ps1"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Log ('Path not found: {0}' -f $Path) 'ERROR'
    return
}
$root = (Resolve-Path -LiteralPath $Path).Path
Write-Log ('Measuring folders under {0} (read-only)...' -f $root) 'INFO'

# Sum every file's size into each of its ancestor folders, but only keep
# folders within $Depth levels of the root for a focused report.
$rootDepth = ($root.TrimEnd('\') -split '\\').Count
$totals = @{}

Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $len = [int64]$_.Length
    $dir = $_.DirectoryName
    while ($dir -and $dir.Length -ge $root.Length) {
        $d = ($dir -split '\\').Count - $rootDepth
        if ($d -le $Depth) {
            if ($totals.ContainsKey($dir)) { $totals[$dir] += $len } else { $totals[$dir] = $len }
        }
        if ($dir -eq $root) { break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
}

$rows = $totals.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 30 | ForEach-Object {
    [pscustomobject]@{ Size = (Format-Size $_.Value); SizeBytes = [int64]$_.Value; Folder = $_.Key }
}

Write-Host ''
Write-Host ('Largest folders under {0}:' -f $root) -ForegroundColor White
$rows | Format-Table -AutoSize Size, Folder | Out-Host

$csv = Get-LogPath -Name 'profile-bloat' -Extension 'csv'
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Log ('Saved profile-bloat CSV: {0}' -f $csv) 'INFO'
Write-Log 'Nothing was deleted — this is a report only.' 'INFO'
