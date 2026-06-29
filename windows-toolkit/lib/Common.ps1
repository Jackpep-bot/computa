# Common.ps1 — shared helpers for the computa Windows cleanup toolkit.
# Dot-sourced by every script:   . "$PSScriptRoot\lib\Common.ps1"
#
# No state is changed by anything in here except the log helpers, which only
# ever write into the toolkit's own logs\ folder.

function Get-Timestamp {
    (Get-Date).ToString('yyyy-MM-dd_HHmmss')
}

function Get-ToolkitRoot {
    # lib\ -> toolkit root
    Split-Path -Parent $PSScriptRoot
}

function Get-LogDir {
    $dir = Join-Path (Get-ToolkitRoot) 'logs'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-LogPath {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Extension = 'txt'
    )
    Join-Path (Get-LogDir) ('{0}_{1}.{2}' -f $Name, (Get-Timestamp), $Extension)
}

function New-ActionLog {
    # A log file we append to as actions happen (used by cleanup).
    param([Parameter(Mandatory)][string]$Name)
    $path = Get-LogPath -Name $Name
    ('== computa Windows toolkit :: {0} :: {1} ==' -f $Name, (Get-Date)) |
        Out-File -LiteralPath $path -Encoding UTF8
    return $path
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ACTION','DRYRUN','ERROR')][string]$Level = 'INFO',
        [string]$Path,
        [switch]$NoConsole
    )
    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('HH:mm:ss'), $Level, $Message
    if ($Path) { Add-Content -LiteralPath $Path -Value $line }
    if (-not $NoConsole) {
        switch ($Level) {
            'WARN'   { Write-Host $line -ForegroundColor Yellow }
            'ERROR'  { Write-Host $line -ForegroundColor Red }
            'ACTION' { Write-Host $line -ForegroundColor Green }
            'DRYRUN' { Write-Host $line -ForegroundColor Cyan }
            default  { Write-Host $line -ForegroundColor Gray }
        }
    }
}

function Format-Size {
    param([Parameter(Mandatory)][double]$Bytes)
    $units = 'B','KB','MB','GB','TB','PB'
    $i = 0
    $n = [math]::Abs($Bytes)
    while ($n -ge 1024 -and $i -lt ($units.Count - 1)) {
        $n = $n / 1024
        $i++
    }
    return ('{0:N1} {1}' -f $n, $units[$i])
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-DiskHealth {
    # Read-only SMART / disk health. Returns objects; never throws.
    $out = @()
    try {
        foreach ($d in (Get-PhysicalDisk -ErrorAction Stop)) {
            $out += [pscustomobject]@{
                Name              = $d.FriendlyName
                MediaType         = [string]$d.MediaType
                SizeBytes         = [int64]$d.Size
                HealthStatus      = [string]$d.HealthStatus
                OperationalStatus = ($d.OperationalStatus -join ', ')
            }
        }
    } catch {
        try {
            $pred = Get-CimInstance -Namespace 'root\wmi' `
                -ClassName 'MSStorageDriver_FailurePredictStatus' -ErrorAction Stop
            foreach ($p in $pred) {
                $status = 'Healthy'
                if ($p.PredictFailure) { $status = 'Unhealthy' }
                $out += [pscustomobject]@{
                    Name              = [string]$p.InstanceName
                    MediaType         = 'Unknown'
                    SizeBytes         = $null
                    HealthStatus      = $status
                    OperationalStatus = ('Reason={0}' -f $p.Reason)
                }
            }
        } catch {
            # leave $out empty -> unknown
        }
    }
    return $out
}

function Test-DiskHealthy {
    # $true = all healthy, $false = a problem found, $null = unknown.
    $disks = Get-DiskHealth
    if (-not $disks -or @($disks).Count -eq 0) { return $null }
    foreach ($d in $disks) {
        if ($d.HealthStatus -and $d.HealthStatus -ne 'Healthy') { return $false }
    }
    return $true
}

function Get-JunkTargets {
    # Known-safe junk locations ONLY. Each: Label, Path, NeedsAdmin.
    $list = New-Object System.Collections.Generic.List[object]
    $list.Add([pscustomobject]@{ Label='User TEMP'; Path=$env:TEMP; NeedsAdmin=$false })
    $list.Add([pscustomobject]@{ Label='Windows TEMP'; Path=(Join-Path $env:SystemRoot 'Temp'); NeedsAdmin=$false })

    $local = $env:LOCALAPPDATA
    if ($local) {
        $list.Add([pscustomobject]@{ Label='Chrome cache'; Path=(Join-Path $local 'Google\Chrome\User Data\Default\Cache'); NeedsAdmin=$false })
        $list.Add([pscustomobject]@{ Label='Edge cache'; Path=(Join-Path $local 'Microsoft\Edge\User Data\Default\Cache'); NeedsAdmin=$false })
        $list.Add([pscustomobject]@{ Label='Windows INetCache'; Path=(Join-Path $local 'Microsoft\Windows\INetCache'); NeedsAdmin=$false })
        $list.Add([pscustomobject]@{ Label='Crash dumps'; Path=(Join-Path $local 'CrashDumps'); NeedsAdmin=$false })

        $ffRoot = Join-Path $local 'Mozilla\Firefox\Profiles'
        if (Test-Path -LiteralPath $ffRoot) {
            Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $c = Join-Path $_.FullName 'cache2'
                if (Test-Path -LiteralPath $c) {
                    $list.Add([pscustomobject]@{ Label=('Firefox cache (' + $_.Name + ')'); Path=$c; NeedsAdmin=$false })
                }
            }
        }
    }

    $list.Add([pscustomobject]@{ Label='Windows Update cache'; Path=(Join-Path $env:SystemRoot 'SoftwareDistribution\Download'); NeedsAdmin=$true })

    return $list | Where-Object { $_.Path -and (Test-Path -LiteralPath $_.Path) }
}

function Get-RecycleBinSize {
    # Bytes currently in the Recycle Bin (read-only estimate), or $null.
    try {
        $shell = New-Object -ComObject Shell.Application
        $rb = $shell.NameSpace(0x0a)
        $sum = [int64]0
        foreach ($item in $rb.Items()) {
            try { $sum += [int64]$item.ExtendedProperty('System.Size') } catch { }
        }
        return $sum
    } catch {
        return $null
    }
}

function Get-ExePath {
    param([string]$CommandLine)
    if (-not $CommandLine) { return $null }
    $c = $CommandLine.Trim()
    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 1) { return $c.Substring(1, $end - 1) }
    }
    $idx = $c.ToLower().IndexOf('.exe')
    if ($idx -ge 0) { return $c.Substring(0, $idx + 4) }
    return ($c -split '\s+')[0]
}

function Get-FilePublisher {
    param([string]$Path)
    if (-not $Path) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not (Test-Path -LiteralPath $expanded)) { return '' }
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $expanded -ErrorAction Stop
        if ($sig -and $sig.SignerCertificate) {
            $cn = ($sig.SignerCertificate.Subject -split ',')[0] -replace '^CN=', ''
            if ($cn) { return $cn.Trim() }
        }
    } catch { }
    try {
        $co = (Get-Item -LiteralPath $expanded -ErrorAction Stop).VersionInfo.CompanyName
        if ($co) { return $co.Trim() }
    } catch { }
    return ''
}

function Get-StartupEntries {
    # Registry Run keys + startup folders + logon scheduled tasks (read-only).
    $entries = New-Object System.Collections.Generic.List[object]

    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($k in $runKeys) {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        $props = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $exe = Get-ExePath $p.Value
            $entries.Add([pscustomobject]@{
                Name      = $p.Name
                Command   = [string]$p.Value
                Path      = $exe
                Publisher = (Get-FilePublisher $exe)
                Source    = $k
            })
        }
    }

    $folders = @(
        [Environment]::GetFolderPath('Startup'),
        [Environment]::GetFolderPath('CommonStartup')
    )
    foreach ($f in $folders) {
        if (-not $f -or -not (Test-Path -LiteralPath $f)) { continue }
        Get-ChildItem -LiteralPath $f -File -ErrorAction SilentlyContinue | ForEach-Object {
            $target = $_.FullName
            if ($_.Extension -eq '.lnk') {
                try {
                    $sh = New-Object -ComObject WScript.Shell
                    $target = $sh.CreateShortcut($_.FullName).TargetPath
                } catch { }
            }
            $entries.Add([pscustomobject]@{
                Name      = $_.Name
                Command   = $target
                Path      = $target
                Publisher = (Get-FilePublisher $target)
                Source    = ('Startup folder: ' + $f)
            })
        }
    }

    try {
        Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }
        } | ForEach-Object {
            $action = $_.Actions | Select-Object -First 1
            $exe = $null
            if ($action -and $action.Execute) {
                $exe = [Environment]::ExpandEnvironmentVariables($action.Execute)
            }
            $entries.Add([pscustomobject]@{
                Name      = $_.TaskName
                Command   = $exe
                Path      = $exe
                Publisher = (Get-FilePublisher $exe)
                Source    = ('Scheduled task (logon): ' + $_.TaskPath)
            })
        }
    } catch { }

    return $entries
}
