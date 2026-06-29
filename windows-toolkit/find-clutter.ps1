<#
.SYNOPSIS
  Read-only: find big files (>500MB), stale files (not accessed in 2+ years),
  and likely duplicates (same size + matching hash) under a folder.
.DESCRIPTION
  Never deletes. Writes three CSVs. Hashing is limited to size-collision groups
  above -MinDuplicateMB for performance.
.PARAMETER Path
  Folder to scan (required-ish; defaults to your user profile).
#>
param(
    [string]$Path = $env:USERPROFILE,
    [int]$LargeMB = 500,
    [int]$StaleYears = 2,
    [int]$MinDuplicateMB = 50
)

. "$PSScriptRoot\lib\Common.ps1"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Log ('Path not found: {0}' -f $Path) 'ERROR'
    return
}
$root = (Resolve-Path -LiteralPath $Path).Path
Write-Log ('Scanning {0} for clutter (read-only)...' -f $root) 'INFO'

$largeFloor = [int64]$LargeMB * 1MB
$dupFloor = [int64]$MinDuplicateMB * 1MB
$staleCut = (Get-Date).AddYears(-1 * $StaleYears)

$large = New-Object System.Collections.Generic.List[object]
$stale = New-Object System.Collections.Generic.List[object]
$bySize = @{}   # size -> list of paths (for duplicate detection)

Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $len = [int64]$_.Length

    if ($len -ge $largeFloor) {
        $large.Add([pscustomobject]@{
            Size = (Format-Size $len); SizeBytes = $len
            LastWrite = $_.LastWriteTime; Path = $_.FullName
        })
    }

    if ($_.LastAccessTime -lt $staleCut -and $_.LastWriteTime -lt $staleCut) {
        $stale.Add([pscustomobject]@{
            Size = (Format-Size $len); SizeBytes = $len
            LastAccess = $_.LastAccessTime; LastWrite = $_.LastWriteTime; Path = $_.FullName
        })
    }

    if ($len -ge $dupFloor) {
        if ($bySize.ContainsKey($len)) { $bySize[$len].Add($_.FullName) }
        else {
            $l = New-Object System.Collections.Generic.List[string]
            $l.Add($_.FullName); $bySize[$len] = $l
        }
    }
}

# Duplicate detection: only hash within same-size groups of 2+.
$dupes = New-Object System.Collections.Generic.List[object]
foreach ($size in $bySize.Keys) {
    $paths = $bySize[$size]
    if ($paths.Count -lt 2) { continue }
    $byHash = @{}
    foreach ($p in $paths) {
        try {
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash
        } catch { continue }
        if ($byHash.ContainsKey($h)) { $byHash[$h].Add($p) }
        else {
            $l = New-Object System.Collections.Generic.List[string]
            $l.Add($p); $byHash[$h] = $l
        }
    }
    foreach ($h in $byHash.Keys) {
        if ($byHash[$h].Count -lt 2) { continue }
        foreach ($p in $byHash[$h]) {
            $dupes.Add([pscustomobject]@{
                Size = (Format-Size $size); SizeBytes = [int64]$size
                Hash = $h; Path = $p
            })
        }
    }
}

$largeSorted = $large | Sort-Object SizeBytes -Descending
$staleSorted = $stale | Sort-Object SizeBytes -Descending
$dupeSorted  = $dupes | Sort-Object Hash, SizeBytes

$largeCsv = Get-LogPath -Name 'clutter-large' -Extension 'csv'
$staleCsv = Get-LogPath -Name 'clutter-stale' -Extension 'csv'
$dupeCsv  = Get-LogPath -Name 'clutter-duplicates' -Extension 'csv'
$largeSorted | Export-Csv -LiteralPath $largeCsv -NoTypeInformation -Encoding UTF8
$staleSorted | Export-Csv -LiteralPath $staleCsv -NoTypeInformation -Encoding UTF8
$dupeSorted  | Export-Csv -LiteralPath $dupeCsv -NoTypeInformation -Encoding UTF8

Write-Log ('Large files (>{0}MB)      : {1}  -> {2}' -f $LargeMB, @($largeSorted).Count, $largeCsv) 'INFO'
Write-Log ('Stale files ({0}+ years)   : {1}  -> {2}' -f $StaleYears, @($staleSorted).Count, $staleCsv) 'INFO'
Write-Log ('Likely-duplicate files    : {0}  -> {1}' -f @($dupeSorted).Count, $dupeCsv) 'INFO'
Write-Log 'Nothing was deleted — this is a report only.' 'INFO'
