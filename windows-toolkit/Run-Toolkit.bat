@echo off
REM Double-click this to launch the computa Windows toolkit menu.
REM It runs PowerShell with an execution-policy bypass for this one launch only,
REM so you never have to change any system settings.
cd /d "%~dp0"
title computa Windows toolkit

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0menu.ps1"

echo.
echo The toolkit has closed. Double-click this file anytime to open it again.
pause
