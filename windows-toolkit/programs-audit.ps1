<#
.SYNOPSIS
  Read-only: list installed programs with install date, estimated size and
  publisher, sorted by size (largest first).
.DESCRIPTION
  Reads the Uninstall registry keys. Removes nothing. Prints a table and CSV.
#>
param()

. "$PSScriptRoot\lib\Common.ps1"

Write-Log 'Reading installed programs (read-only)...' 'INFO'

$keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$seen = @{}
$rows = New-Object System.Collections.Generic.List[object]

foreach ($k in $keys) {
    Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.DisplayName
        if (-not $name) { return }
        if ($_.SystemComponent -eq 1) { return }
        if ($seen.ContainsKey($name)) { return }
        $seen[$name] = $true

        $sizeBytes = 0
        if ($_.EstimatedSize) { $sizeBytes = [int64]$_.EstimatedSize * 1024 }

        $installed = ''
        if ($_.InstallDate -and $_.InstallDate -match '^\d{8}$') {
            try {
                $installed = [datetime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null).ToString('yyyy-MM-dd')
            } catch { $installed = [string]$_.InstallDate }
        }

        $rows.Add([pscustomobject]@{
            Size      = if ($sizeBytes) { Format-Size $sizeBytes } else { '' }
            SizeBytes = $sizeBytes
            Name      = [string]$name
            Publisher = [string]$_.Publisher
            Installed = $installed
        })
    }
}

$sorted = $rows | Sort-Object SizeBytes -Descending
Write-Host ''
Write-Host ('Installed programs: {0}' -f @($sorted).Count) -ForegroundColor White
$sorted | Select-Object -First 40 | Format-Table -AutoSize Size, Name, Publisher, Installed | Out-Host

$csv = Get-LogPath -Name 'programs-audit' -Extension 'csv'
$sorted | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Log ('Saved programs CSV: {0}' -f $csv) 'INFO'
Write-Log 'To uninstall, use Settings > Apps. This script changes nothing.' 'INFO'
