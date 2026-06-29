#!/usr/bin/env bash
# Launcher for Linux. No install needed: computa runs on Python's standard
# library alone. psutil is added best-effort for deeper scans, never required.
cd "$(dirname "$0")" || exit 1

PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "Python 3 was not found. Install it from your package manager or"
  echo "https://www.python.org/downloads/ and run this again."
  read -r -p "Press Enter to close..." _
  exit 1
fi

# Best effort only — ignored if it can't install.
"$PY" -c "import psutil" 2>/dev/null || "$PY" -m pip install --quiet --user psutil 2>/dev/null || true

"$PY" -m computa menu
