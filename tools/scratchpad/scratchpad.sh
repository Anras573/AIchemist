#!/usr/bin/env bash
# Launcher for scratchpad.py: finds a usable Python (3.7+) and runs the tool.
# Usage: scratchpad.sh <command> [options]   (see `scratchpad.sh --help`)
set -euo pipefail

python_cmd=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 \
     && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' >/dev/null 2>&1; then
    python_cmd="$candidate"
    break
  fi
done

if [[ -z "$python_cmd" ]]; then
  echo "scratchpad: Python 3.7+ is required but was not found (tried python3, python)." >&2
  echo "Install it with 'brew install python' (macOS), your package manager (Linux), or 'winget install Python.Python.3' (Windows)." >&2
  exit 1
fi

# Resolve the real location of this script so symlinks (e.g. from a mod) still find scratchpad.py.
# realpath first, then Python (already verified above); never assume either is present.
source_path="${BASH_SOURCE[0]}"
if command -v realpath >/dev/null 2>&1; then
  source_path="$(realpath "$source_path")"
else
  source_path="$("$python_cmd" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$source_path")"
fi
script_dir="$(cd "$(dirname "$source_path")" && pwd)"

exec "$python_cmd" "$script_dir/scratchpad.py" "$@"
