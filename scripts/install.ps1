# One-time setup for computa on Windows (PowerShell).
# Creates an isolated virtual environment and installs computa + psutil into it.
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$py = (Get-Command py -ErrorAction SilentlyContinue) ??
      (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) {
    Write-Error "Python 3 was not found. Please install Python 3.8+ from python.org and re-run."
    exit 1
}

Write-Host "Creating virtual environment in .venv ..."
& $py.Source -m venv .venv

Write-Host "Installing computa (with psutil) ..."
& ".venv\Scripts\python.exe" -m pip install --upgrade pip | Out-Null
& ".venv\Scripts\python.exe" -m pip install -e ".[full]"

Write-Host ""
Write-Host "Done! Double-click Computa.bat to open the menu, or run:"
Write-Host "  .venv\Scripts\computa.exe scan"
