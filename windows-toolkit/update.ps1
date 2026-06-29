<#
.SYNOPSIS
  Update the toolkit in place — pull the latest scripts from GitHub straight
  into THIS folder, so you never have to re-download the ZIP.
.DESCRIPTION
  Auto-discovers every file in the repo's windows-toolkit folder (including new
  ones) via the GitHub API and writes them into $PSScriptRoot, overwriting older
  copies. Never touches your logs\ or MY-PC-INVENTORY files.

  Public repo: works with no setup. Private repo: pass a GitHub token with
  -Token, or make the repo public (repo Settings -> Danger Zone).
.PARAMETER Token
  Optional GitHub personal access token (needed only for a private repo).
#>
param(
    [string]$Repo   = 'Jackpep-bot/computa',
    [string]$Branch = 'main',
    [string]$Token
)

. "$PSScriptRoot\lib\Common.ps1"

# Old PCs often default to TLS 1.0; GitHub needs 1.2.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$log = New-ActionLog -Name 'update'
$headers = @{ 'User-Agent' = 'computa-toolkit-updater' }
if ($Token) { $headers['Authorization'] = "token $Token" }

# Pull everything via the raw CDN (no API -> no rate limits). The repo ships a
# files.txt manifest listing every toolkit file; we read it, then fetch each.
$base = "https://raw.githubusercontent.com/$Repo/$Branch/windows-toolkit/"

Write-Log 'Checking GitHub for the latest toolkit files...' 'INFO' $log
try {
    $manifest = (Invoke-WebRequest -Uri ($base + 'files.txt') -Headers $headers -UseBasicParsing -ErrorAction Stop).Content
} catch {
    Write-Log ('Could not reach the repo: {0}' -f $_.Exception.Message) 'ERROR' $log
    Write-Host ''
    Write-Host 'Update failed to reach the repository.' -ForegroundColor Yellow
    Write-Host 'Check your internet, that the repo is public, or pass -Token for a private repo.' -ForegroundColor Yellow
    return
}

$files = $manifest -split "`r?`n" | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -notmatch '^#' }

$root = $PSScriptRoot
$updated = 0
foreach ($rel in $files) {
    if ($rel -match '^logs/' -or $rel -match '(?i)MY-PC-INVENTORY') { continue }
    $dest = Join-Path $root ($rel -replace '/', '\')
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    try {
        Invoke-WebRequest -Uri ($base + $rel) -Headers $headers -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Write-Log ('updated {0}' -f $rel) 'ACTION' $log
        $updated++
    } catch {
        Write-Log ('FAILED {0}: {1}' -f $rel, $_.Exception.Message) 'WARN' $log
    }
}

Write-Log ('Done. Updated {0} file(s) into {1}' -f $updated, $root) 'ACTION' $log
Write-Host ''
Write-Host ('Toolkit updated in place ({0} files). Re-open the menu to use the latest.' -f $updated) -ForegroundColor Green
