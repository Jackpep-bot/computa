@echo off
REM Double-clickable launcher for Windows. Sets up computa on first run,
REM then opens the interactive menu.
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
  echo First run: setting up computa...
  powershell -ExecutionPolicy Bypass -File "scripts\install.ps1"
  if errorlevel 1 (
    echo Setup failed. See the message above.
    pause
    exit /b 1
  )
)

".venv\Scripts\python.exe" -m computa menu
pause
