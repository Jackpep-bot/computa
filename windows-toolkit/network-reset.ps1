<#
.SYNOPSIS
  Flush DNS and report adapter/IP state (default). Reset Winsock/TCP-IP only
  with -Confirm (needs a reboot).
.DESCRIPTION
  By default this flushes the DNS resolver cache (harmless) and prints the
  current network adapters and IP configuration. With -Confirm it ALSO resets
  the Winsock catalog and TCP/IP stack — a bigger change that REQUIRES A REBOOT
  and needs Administrator.
#>
param(
    [switch]$Confirm
)

. "$PSScriptRoot\lib\Common.ps1"

$log = New-ActionLog -Name 'network-reset'

# Flush DNS (safe).
try {
    & ipconfig.exe '/flushdns' 2>&1 | Out-Null
    Write-Log 'Flushed DNS resolver cache.' 'ACTION' -Path $log
} catch {
    Write-Log ('Could not flush DNS: {0}' -f $_.Exception.Message) 'WARN' -Path $log
}

# Report adapter / IP state (read-only).
Write-Host ''
Write-Host 'Network adapters / IP configuration:' -ForegroundColor White
try {
    Get-NetIPConfiguration -ErrorAction Stop |
        Format-Table -AutoSize InterfaceAlias, InterfaceDescription,
            @{ N = 'IPv4'; E = { ($_.IPv4Address.IPAddress -join ', ') } },
            @{ N = 'Gateway'; E = { ($_.IPv4DefaultGateway.NextHop -join ', ') } } | Out-Host
} catch {
    (& ipconfig.exe '/all' 2>&1 | Out-String) | Write-Host
}

if (-not $Confirm) {
    Write-Log 'DRY-RUN: DNS flushed + state reported. Re-run with -Confirm to RESET the stack (needs reboot).' 'DRYRUN' -Path $log
    return
}

if (-not (Test-IsAdmin)) {
    Write-Log 'Winsock/TCP-IP reset needs Administrator. Run PowerShell as admin and re-run with -Confirm.' 'ERROR' -Path $log
    return
}

Write-Log 'Resetting Winsock catalog and TCP/IP stack...' 'ACTION' -Path $log
(& netsh.exe 'winsock' 'reset' 2>&1 | Out-String) | Add-Content -LiteralPath $log
(& netsh.exe 'int' 'ip' 'reset' 2>&1 | Out-String) | Add-Content -LiteralPath $log
Write-Log 'DONE. *** You must REBOOT for the network reset to take effect. ***' 'WARN' -Path $log
