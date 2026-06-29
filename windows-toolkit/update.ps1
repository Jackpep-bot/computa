<#
.SYNOPSIS
  Update the toolkit in place — pull the latest scripts from GitHub straight
  into THIS folder, so you never have to re-download the ZIP.
.DESCRIPTION
  Self-contained on purpose: it does NOT depend on any other toolkit file, so it
  works even in an empty folder (true bootstrap). Reads the repo's files.txt
  manifest over the raw CDN (no API, no rate limits) and fetches each listed
  file. Never touches your logs\ or MY-PC-INVENTORY files.

  Public repo: works with no setup. Private repo: pass -Token.
.PARAMETER Token
  Optional GitHub personal access token (needed only for a private repo).
#>
param(
    [string]$Repo   = 'Jackpep-bot/computa',
    [string]$Branch = 'main',
    [string]$Token
)

# Old PCs often default to TLS 1.0; GitHub needs 1.2.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Say { param([string]$Msg, [string]$Color = 'Gray') Write-Host $Msg -ForegroundColor $Color }

$headers = @{ 'User-Agent' = 'computa-toolkit-updater' }
if ($Token) { $headers['Authorization'] = "token $Token" }
$base = "https://raw.githubusercontent.com/$Repo/$Branch/windows-toolkit/"

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

Say 'Checking GitHub for the latest toolkit files...' 'Cyan'
try {
    $manifest = (Invoke-WebRequest -Uri ($base + 'files.txt') -Headers $headers -UseBasicParsing -ErrorAction Stop).Content
} catch {
    Say ('Could not reach the repo: ' + $_.Exception.Message) 'Red'
    Say 'Check your internet, that the repo is public, or pass -Token for a private repo.' 'Yellow'
    return
}

$files = $manifest -split "`r?`n" | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -notmatch '^#' }

$updated = 0
$failed = 0
foreach ($rel in $files) {
    if ($rel -match '^logs/' -or $rel -match '(?i)MY-PC-INVENTORY') { continue }
    $dest = Join-Path $root ($rel -replace '/', '\')
    $dir = Split-Path $dest -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    try {
        Invoke-WebRequest -Uri ($base + $rel) -Headers $headers -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Say ('  updated ' + $rel) 'Green'
        $updated++
    } catch {
        Say ('  FAILED  ' + $rel + ' : ' + $_.Exception.Message) 'Yellow'
        $failed++
    }
}

Say ''
Say ("Done — $updated file(s) updated, $failed failed.") 'Green'
Say 'Run  .\menu.ps1  to use the latest.' 'Green'
