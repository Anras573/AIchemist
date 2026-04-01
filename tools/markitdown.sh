#!/usr/bin/env bash
# Convert a local file to markdown using the markitdown Docker image.
# Mounts the file's parent directory into the container so markitdown
# can access it via a file:// URI.
#
# Usage: markitdown.sh <absolute-or-relative-file-path>
# Output: markdown printed to stdout
#
# Note: the entire parent directory of the file is mounted into the container
# as /data (read-only). Avoid pointing this script at files in sensitive
# directories (e.g. ~, ~/.ssh).

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <file-path>" >&2
  exit 1
fi

# Check existence before resolving to avoid set -e killing the process before
# our own error message runs.
if [[ ! -e "$1" ]]; then
  echo "Error: file not found: $1" >&2
  exit 1
fi

# Resolve to absolute path. realpath(1) is not available on stock macOS
# (requires GNU coreutils), so fall back to a POSIX-compatible alternative.
if command -v realpath &>/dev/null; then
  FILE_PATH="$(realpath "$1")"
else
  FILE_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
fi

if [[ ! -f "$FILE_PATH" ]]; then
  echo "Error: not a regular file: $FILE_PATH" >&2
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo "Error: docker is not installed or not in PATH" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is not installed or not in PATH (required for percent-encoding filenames)" >&2
  exit 1
fi

FILE_DIR="$(dirname "$FILE_PATH")"
FILE_NAME="$(basename "$FILE_PATH")"

# Percent-encode the filename for safe embedding in a file:// URI.
# Characters like spaces, #, ?, and & are special in URIs and must be encoded.
# Unreserved characters (RFC 3986: A-Z a-z 0-9 - . _ ~) are left unencoded so
# the container sees a filename that matches the on-disk name exactly.
FILE_NAME_ENCODED="$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe='-_.~'))" "$FILE_NAME")"

docker run --rm -i \
  --network none \
  --entrypoint markitdown \
  -v "${FILE_DIR}:/data:ro" \
  mcp/markitdown@sha256:1cef3bf502503310ed0884441874ccf6cdaac20136dc1179797fa048269dc4cb \
  "file:///data/${FILE_NAME_ENCODED}"
