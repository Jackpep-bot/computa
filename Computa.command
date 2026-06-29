#!/usr/bin/env bash
# Double-clickable launcher for macOS. Sets things up on first run, then
# opens the interactive computa menu.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -x ".venv/bin/python" ]; then
  echo "First run: setting up computa..."
  bash scripts/install.sh
  echo
fi

exec ./.venv/bin/python -m computa menu
