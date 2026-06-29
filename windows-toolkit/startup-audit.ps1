<#
.SYNOPSIS
  Read-only: list everything that launches at startup (Run keys, startup
  folders, logon scheduled tasks) with name, publisher and path.
.DESCRIPTION
  Flags entries with no publisher, or living in Temp/AppData, as "review".
  Changes nothing. Prints a table and saves a CSV.
#>
param()

. "$PSScriptRoot\lib\Common.ps1"

Write-Log 'Collecting startup entries (read-only)...' 'INFO'

$rows = Get-StartupEntries | ForEach-Object {
    $review = $false
    if (-not $_.Publisher) { $review = $true }
    if ($_.Path -and ($_.Path -match '(?i)\\Temp\\' -or $_.Path -match '(?i)\\AppData\\')) { $review = $true }
    [pscustomobject]@{
        Review    = if ($review) { 'REVIEW' } else { '' }
        Name      = $_.Name
        Publisher = $_.Publisher
        Path      = $_.Path
        Source    = $_.Source
    }
}

$rows = @($rows)
Write-Host ''
Write-Host ('Startup entries: {0} total, {1} flagged for review' -f $rows.Count, @($rows | Where-Object { $_.Review }).Count) -ForegroundColor White
$rows | Sort-Object Review -Descending | Format-Table -AutoSize Review, Name, Publisher, Path | Out-Host

$csv = Get-LogPath -Name 'startup-audit' -Extension 'csv'
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Log ('Saved startup audit CSV: {0}' -f $csv) 'INFO'
Write-Log 'Nothing was disabled — this is a report only.' 'INFO'
