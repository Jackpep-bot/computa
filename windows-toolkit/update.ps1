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

function Get-RepoFiles {
    param([string]$ApiPath)
    $url = "https://api.github.com/repos/$Repo/contents/$ApiPath" + "?ref=$Branch"
    $items = Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
    $files = @()
    foreach ($it in $items) {
        if ($it.type -eq 'dir') { $files += Get-RepoFiles -ApiPath $it.path }
        elseif ($it.type -eq 'file') { $files += $it }
    }
    return $files
}

Write-Log 'Checking GitHub for the latest toolkit files...' 'INFO' $log
try {
    $files = Get-RepoFiles -ApiPath 'windows-toolkit'
} catch {
    Write-Log ('Could not reach the repo: {0}' -f $_.Exception.Message) 'ERROR' $log
    Write-Host ''
    Write-Host 'Update failed to reach the repository.' -ForegroundColor Yellow
    Write-Host 'If the repo is PRIVATE, either:' -ForegroundColor Yellow
    Write-Host '  - make it public (repo Settings -> Danger Zone -> Change visibility), or' -ForegroundColor Yellow
    Write-Host '  - run:  .\update.ps1 -Token <your GitHub personal access token>' -ForegroundColor Yellow
    return
}

$root = $PSScriptRoot
$updated = 0
foreach ($f in $files) {
    $rel = $f.path -replace '^windows-toolkit/', ''
    if ($rel -match '^logs/' -or $rel -match '(?i)MY-PC-INVENTORY') { continue }
    $dest = Join-Path $root ($rel -replace '/', '\')
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    try {
        Invoke-WebRequest -Uri $f.download_url -Headers $headers -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Write-Log ('updated {0}' -f $rel) 'ACTION' $log
        $updated++
    } catch {
        Write-Log ('FAILED {0}: {1}' -f $rel, $_.Exception.Message) 'WARN' $log
    }
}

Write-Log ('Done. Updated {0} file(s) into {1}' -f $updated, $root) 'ACTION' $log
Write-Host ''
Write-Host ('Toolkit updated in place ({0} files). Re-open the menu to use the latest.' -f $updated) -ForegroundColor Green
