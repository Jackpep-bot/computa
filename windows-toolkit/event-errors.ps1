<#
.SYNOPSIS
  Read-only: summarize recurring errors/critical events (last 14 days) from the
  System and Application logs, grouped by source, with counts and most recent time.
.DESCRIPTION
  Changes nothing. Prints a summary table and writes a CSV.
#>
param(
    [int]$Days = 14
)

. "$PSScriptRoot\lib\Common.ps1"

Write-Log ('Reading System + Application errors from the last {0} days...' -f $Days) 'INFO'
$start = (Get-Date).AddDays(-1 * $Days)

$events = New-Object System.Collections.Generic.List[object]
foreach ($logName in 'System', 'Application') {
    try {
        Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 1, 2; StartTime = $start } -ErrorAction Stop |
            ForEach-Object { $events.Add($_) }
    } catch {
        Write-Log ('  (no matching events in {0}, or log unavailable)' -f $logName) 'INFO'
    }
}

if (@($events).Count -eq 0) {
    Write-Log 'No error/critical events found in the period. That is good news.' 'INFO'
    return
}

$rows = $events | Group-Object ProviderName, Id | ForEach-Object {
    $recent = ($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1)
    $sample = ''
    if ($recent.Message) { $sample = ($recent.Message -split "`r?`n")[0] }
    [pscustomobject]@{
        Count      = $_.Count
        Source     = $recent.ProviderName
        EventId    = $recent.Id
        Level      = $recent.LevelDisplayName
        MostRecent = $recent.TimeCreated
        Sample     = $sample
    }
} | Sort-Object Count -Descending

$rows = @($rows)
Write-Host ''
Write-Host ('Recurring errors/critical events (last {0} days): {1} distinct sources' -f $Days, $rows.Count) -ForegroundColor White
$rows | Select-Object -First 20 | Format-Table -AutoSize Count, Source, EventId, Level, MostRecent | Out-Host

$csv = Get-LogPath -Name 'event-errors' -Extension 'csv'
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Log ('Saved event summary CSV: {0}' -f $csv) 'INFO'
