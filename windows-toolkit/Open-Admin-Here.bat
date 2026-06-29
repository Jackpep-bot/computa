@echo off
REM One-click: open an elevated (Administrator) PowerShell in THIS folder.
REM Double-click it -> click Yes on the UAC prompt -> admin PowerShell, ready.

REM Are we already admin? (net session only succeeds when elevated.)
net session >nul 2>&1
if errorlevel 1 (
    REM Not admin yet: relaunch this file elevated, then exit this copy.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

REM Elevated now: open PowerShell that stays open, in this folder.
cd /d "%~dp0"
powershell -NoProfile -NoExit -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '%~dp0'; Write-Host 'Admin PowerShell ready in the toolkit folder.' -ForegroundColor Green; Write-Host 'Type  .\menu.ps1  to start the toolkit, or run any command.' -ForegroundColor Gray"
