<#
.SYNOPSIS
  Clear Desktop clutter (and stale duplicate copies of this project) safely.
.DESCRIPTION
  DRY-RUN by default; -Confirm to delete. A FAILSAFE guards every deletion: it
  refuses (and ABORTS the whole run, reporting what happened) if anything is
  about to be removed that should be protected — the toolkit copy you're running
  from, your saved MY-PC-INVENTORY file, system files, or anything outside your
  Desktop/Downloads. Each action is logged the moment it happens, so if it stops
  you have a full ledger of what was done.

  Modes:
    (default)  remove only stale project artifacts (old computa-main*, zips)
    -All       clear EVERYTHING on the Desktop except the protected items
.PARAMETER All
  Clear the whole Desktop (keeping protected items), not just project leftovers.
.PARAMETER Confirm
  Actually delete. Without it, nothing is removed.
#>
param(
    [switch]$All,
    [switch]$Confirm
)

. "$PSScriptRoot\lib\Common.ps1"

$log = New-ActionLog -Name 'safe-sweep'

$desktop   = [Environment]::GetFolderPath('Desktop')
$downloads = Join-Path $env:USERPROFILE 'Downloads'

# Zones we are even allowed to touch.
if ($All) {
    $zones = @($desktop)
} else {
    $zones = @($desktop, $downloads)
}
$zones = @($zones | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        ForEach-Object { (Resolve-Path -LiteralPath $_).Path })

# The project copy currently in use — protect it (and its ancestor folder under
# the Desktop/Downloads) so the toolkit still works after the sweep.
function Get-ActiveTopItems {
    param([string[]]$Zones)
    $tops = @()
    foreach ($z in $Zones) {
        $zn = $z.TrimEnd('\')
        if ($PSScriptRoot.StartsWith($zn + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $PSScriptRoot.Substring($zn.Length).TrimStart('\')
            $seg = ($rel -split '\\')[0]
            $tops += (Join-Path $zn $seg)
        }
    }
    return $tops
}
$activeTops = @(Get-ActiveTopItems -Zones $zones)
foreach ($a in $activeTops) { Write-Log ("PROTECTING (in use): {0}" -f $a) 'INFO' $log }

# ---- FAILSAFE: returns a reason string if a path must NOT be deleted ----
function Get-ForbiddenReason {
    param([string]$Path)
    $p = (($Path).TrimEnd('\'))
    $inSafe = $false
    foreach ($z in $zones) {
        $zn = $z.TrimEnd('\')
        if ($p -eq $zn -or $p.StartsWith($zn + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $inSafe = $true }
    }
    if (-not $inSafe) { return 'outside your Desktop/Downloads' }
    foreach ($a in $activeTops) {
        $an = $a.TrimEnd('\')
        # forbid the active copy itself, anything inside it, or any ancestor of it
        if ($p -eq $an -or
            $p.StartsWith($an + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
            $an.StartsWith($p + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'the toolkit copy you are running'
        }
    }
    if ($p -match '(?i)MY-PC-INVENTORY') { return 'your saved inventory list' }
    $leaf = Split-Path $p -Leaf
    if ($leaf -ieq 'desktop.ini') { return 'a Windows system file' }
    return $null
}

# ---- Build the candidate list ----
$candidates = New-Object System.Collections.Generic.List[object]
$activeNames = $activeTops | ForEach-Object { Split-Path $_ -Leaf }

if ($All) {
    Get-ChildItem -LiteralPath $desktop -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($activeNames -contains $_.Name) { return }
        if ($_.Name -match '(?i)MY-PC-INVENTORY') { return }
        if ($_.Name -ieq 'desktop.ini') { return }
        $candidates.Add($_)
    }
} else {
    $patterns = 'computa-main*', 'computa-*.zip', 'computa.zip'
    foreach ($z in $zones) {
        foreach ($pat in $patterns) {
            Get-ChildItem -LiteralPath $z -Filter $pat -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($activeNames -contains $_.Name) { return }
                $candidates.Add($_)
            }
        }
    }
}
$candidates = @($candidates | Sort-Object FullName -Unique)

Write-Host ''
$kind = if ($All) { 'Desktop items' } else { 'stale project leftovers' }
Write-Host ("Found {0} {1} to remove:" -f $candidates.Count, $kind) -ForegroundColor White
$candidates | ForEach-Object { Write-Host ('   {0}' -f $_.FullName) }

# ---- Process with the failsafe + running ledger ----
$removed = 0
$freed = [int64]0
foreach ($item in $candidates) {
    # FAILSAFE tripwire: re-check immediately before touching anything.
    $reason = Get-ForbiddenReason -Path $item.FullName
    if ($reason) {
        Write-Log ('FAILSAFE TRIPPED on "{0}" -> {1}. STOPPING the whole run.' -f $item.FullName, $reason) 'ERROR' $log
        Write-Host ''
        Write-Host '*** STOPPED ***' -ForegroundColor Red
        Write-Host ("Something that should be protected was about to be deleted:" ) -ForegroundColor Red
        Write-Host ("   {0}" -f $item.FullName) -ForegroundColor Red
        Write-Host ("   reason: {0}" -f $reason) -ForegroundColor Red
        Write-Host ("Nothing further was done. {0} item(s) had been removed so far. Log: {1}" -f $removed, $log) -ForegroundColor Yellow
        return
    }

    if (-not $Confirm) {
        Write-Log ('WOULD DELETE: {0}' -f $item.FullName) 'DRYRUN' $log
        continue
    }

    try {
        $size = [int64]0
        if ($item.PSIsContainer) {
            $size = [int64](Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
        } else {
            $size = [int64]$item.Length
        }
        Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        $removed++
        $freed += $size
        Write-Log ('DELETED [{0}]: {1}' -f (Format-Size $size), $item.FullName) 'ACTION' $log   # ledger as we go
    } catch {
        Write-Log ('FAILSAFE: error deleting "{0}": {1}. STOPPING.' -f $item.FullName, $_.Exception.Message) 'ERROR' $log
        Write-Host ''
        Write-Host '*** STOPPED on an error ***' -ForegroundColor Red
        Write-Host ("   {0}" -f $item.FullName) -ForegroundColor Red
        Write-Host ("   {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ("Nothing further was done. {0} item(s) removed so far. Log: {1}" -f $removed, $log) -ForegroundColor Yellow
        return
    }
}

Write-Log '------------------------------------------------------------' 'INFO' $log
if (-not $Confirm) {
    Write-Log ('DRY-RUN: {0} item(s) would be removed. The toolkit copy in use and your inventory are protected. Re-run with -Confirm to delete.' -f $candidates.Count) 'DRYRUN' $log
} else {
    Write-Log ('DONE: removed {0} item(s), freed {1}. The toolkit and your inventory were kept. Log: {2}' -f $removed, (Format-Size $freed), $log) 'ACTION' $log
}
