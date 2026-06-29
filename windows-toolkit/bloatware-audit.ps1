<#
.SYNOPSIS
  Read-only: list Store / preinstalled apps (AppxPackages), flagging common
  bloat as "review".
.DESCRIPTION
  Removes nothing. Prints a table and writes a CSV so you can decide what to
  remove yourself (Settings > Apps, or Remove-AppxPackage).
#>
param()

. "$PSScriptRoot\lib\Common.ps1"

Write-Log 'Listing installed Store/preinstalled apps (read-only)...' 'INFO'

# Name fragments commonly considered bloat on a home PC.
$bloatPatterns = @(
    'Xbox','Bing','Zune','SolitaireCollection','CandyCrush','BubbleWitch','Disney',
    'Spotify','Facebook','TikTok','3DBuilder','MixedReality','OfficeHub','SkypeApp',
    'GetHelp','Getstarted','Microsoft.People','YourPhone','Wallet','FeedbackHub',
    'Todos','PowerAutomate','Clipchamp','News','Weather','Teams','LinkedIn'
)

$apps = @()
try { $apps = Get-AppxPackage -ErrorAction Stop } catch {
    Write-Log 'Could not read AppxPackages (try a normal user PowerShell window).' 'WARN'
    return
}

$rows = $apps | ForEach-Object {
    $name = $_.Name
    $review = ''
    foreach ($pat in $bloatPatterns) {
        if ($name -like ('*' + $pat + '*')) { $review = 'review'; break }
    }
    [pscustomobject]@{
        Review    = $review
        Name      = $name
        Publisher = $_.Publisher
        Version   = $_.Version
    }
}

$rows = @($rows)
Write-Host ''
Write-Host ('Store/preinstalled apps: {0} total, {1} flagged for review' -f $rows.Count, @($rows | Where-Object { $_.Review }).Count) -ForegroundColor White
$rows | Sort-Object Review -Descending | Format-Table -AutoSize Review, Name, Publisher | Out-Host

$csv = Get-LogPath -Name 'bloatware-audit' -Extension 'csv'
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Log ('Saved bloatware CSV: {0}' -f $csv) 'INFO'
Write-Log 'Nothing was removed — this is a report only.' 'INFO'
