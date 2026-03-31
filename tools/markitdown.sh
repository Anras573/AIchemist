#!/usr/bin/env bash
# Convert a local file to markdown using the markitdown Docker image.
# Mounts the file's parent directory into the container so markitdown
# can access it via a file:// URI.
#
# Usage: markitdown.sh <absolute-or-relative-file-path>
# Output: markdown printed to stdout

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <file-path>" >&2
  exit 1
fi

FILE_PATH="$(realpath "$1")"

if [[ ! -f "$FILE_PATH" ]]; then
  echo "Error: file not found: $FILE_PATH" >&2
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo "Error: docker is not installed or not in PATH" >&2
  exit 1
fi

FILE_DIR="$(dirname "$FILE_PATH")"
FILE_NAME="$(basename "$FILE_PATH")"

docker run --rm -i \
  -v "${FILE_DIR}:/data:ro" \
  mcp/markitdown:latest \
  "file:///data/${FILE_NAME}"
