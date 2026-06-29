#!/usr/bin/env bash
# Double-clickable launcher for macOS. No install needed: computa runs on
# Python's standard library alone. psutil is added best-effort, never required.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "Python 3 was not found. Install it from https://www.python.org/downloads/"
  echo "and double-click this file again."
  read -r -p "Press Enter to close..." _
  exit 1
fi

# Best effort only — ignored if it can't install.
"$PY" -c "import psutil" 2>/dev/null || "$PY" -m pip install --quiet --user psutil 2>/dev/null || true

"$PY" -m computa menu
