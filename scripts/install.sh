#!/usr/bin/env bash
# One-time setup for computa on macOS / Linux.
# Creates an isolated virtual environment and installs computa + psutil into it,
# so nothing on your system Python is touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "Python 3 was not found. Please install Python 3.8+ and re-run." >&2
  exit 1
fi

echo "Creating virtual environment in .venv ..."
"$PY" -m venv .venv

echo "Installing computa (with psutil) ..."
./.venv/bin/python -m pip install --upgrade pip >/dev/null
./.venv/bin/python -m pip install -e ".[full]"

echo
echo "Done! You can now run computa in any of these ways:"
echo "  • Double-click  Computa.command   (macOS)"
echo "  • Run           ./computa.sh      (Linux)"
echo "  • Or directly   ./.venv/bin/computa scan"
