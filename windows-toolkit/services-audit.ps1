<#
.SYNOPSIS
  Read-only: list Automatic-start services with status and publisher, flagging
  common safe-to-delay ones as "consider Manual".
.DESCRIPTION
  Changes nothing. Prints a table and writes a CSV. The "consider Manual" flag
  is only a suggestion for you to review — no service is modified.
#>
param()

. "$PSScriptRoot\lib\Common.ps1"

Write-Log 'Reading Automatic-start services (read-only)...' 'INFO'

# Conservative list of services often safe to set to Manual on a home PC.
$delayCandidates = @(
    'Fax','XblGameSave','XboxNetApiSvc','XboxGipSvc','MapsBroker','RetailDemo',
    'DiagTrack','dmwappushservice','WMPNetworkSvc','RemoteRegistry','SysMain',
    'WerSvc','PrintNotify','TabletInputService','PhoneSvc','SharedAccess',
    'lfsvc','SCardSvr','WbioSrvc'
)

$rows = New-Object System.Collections.Generic.List[object]
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.StartMode -eq 'Auto' } | ForEach-Object {
        $exe = Get-ExePath $_.PathName
        $pub = Get-FilePublisher $exe
        $flag = ''
        if ($delayCandidates -contains $_.Name) { $flag = 'consider Manual' }
        $rows.Add([pscustomobject]@{
            Suggestion  = $flag
            Name        = $_.Name
            DisplayName = $_.DisplayName
            State       = $_.State
            Publisher   = $pub
        })
    }

$rows = @($rows)
Write-Host ''
Write-Host ('Automatic services: {0} total, {1} flagged "consider Manual"' -f $rows.Count, @($rows | Where-Object { $_.Suggestion }).Count) -ForegroundColor White
$rows | Sort-Object Suggestion -Descending | Format-Table -AutoSize Suggestion, Name, DisplayName, State, Publisher | Out-Host

$csv = Get-LogPath -Name 'services-audit' -Extension 'csv'
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Log ('Saved services CSV: {0}' -f $csv) 'INFO'
Write-Log 'Nothing was changed — this is a report only.' 'INFO'
