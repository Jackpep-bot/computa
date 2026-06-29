@echo off
REM Double-clickable launcher for Windows. No install needed: computa runs on
REM Python's standard library alone. We optionally add the small "psutil" helper
REM for deeper scans, but never fail if it can't be installed.
cd /d "%~dp0"
title computa - PC health helper

echo ============================================
echo    computa
echo ============================================
echo.

REM --- Find a Python interpreter (py launcher, then python, then python3) ---
set "PY="
py -3 --version >nul 2>nul && set "PY=py -3"
if not defined PY (python --version >nul 2>nul && set "PY=python")
if not defined PY (python3 --version >nul 2>nul && set "PY=python3")

if not defined PY (
  echo Python was not found on this PC. To fix:
  echo.
  echo    1^) Open  https://www.python.org/downloads/
  echo    2^) Run the installer and TICK "Add python.exe to PATH"
  echo    3^) Double-click this file again.
  echo.
  pause
  exit /b 1
)

echo Using %PY%.
echo.

REM --- Best effort only: deeper scans via psutil. Ignored if it can't install. ---
%PY% -c "import psutil" >nul 2>nul || (
  echo Adding an optional helper for deeper scans ^(this is fine to skip^)...
  %PY% -m pip install --quiet --user psutil >nul 2>nul
)

REM --- Run it. Works with or without the helper above. ---
%PY% -m computa menu

echo.
echo computa has closed. Double-click this file anytime to run it again.
pause
