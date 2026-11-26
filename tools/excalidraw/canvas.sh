#!/usr/bin/env bash
# Start, stop, or check the Excalidraw canvas server (Docker).
#
# The `excalidraw` MCP server in .mcp.json is a stdio container that talks to
# this canvas over the shared Docker network below. Start the canvas first,
# then open http://127.0.0.1:${EXCALIDRAW_PORT:-3000} to watch Claude draw.
#
# Usage: canvas.sh start|stop|status
# Env:   EXCALIDRAW_PORT  host port for the canvas UI (default 3000; bound to 127.0.0.1 only)

set -euo pipefail

CANVAS_IMAGE="ghcr.io/yctimlin/mcp_excalidraw-canvas@sha256:9aa7adaabc049bcdc75c27feed20d1d5f89ef15ae9fe8c5346f8fa8269e1ee13"
CONTAINER="aichemist-excalidraw-canvas"
NETWORK="aichemist-excalidraw"
PORT="${EXCALIDRAW_PORT:-3000}"
URL="http://127.0.0.1:${PORT}"

usage() {
  echo "Usage: $(basename "$0") start|stop|status" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage

if ! command -v docker &>/dev/null; then
  echo "Error: docker is not installed or not in PATH" >&2
  exit 1
fi

is_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" == "true" ]]
}

healthy() {
  command -v curl &>/dev/null && curl -fsS -m 3 "${URL}/health" &>/dev/null
}

case "$1" in
  start)
    if is_running; then
      echo "Canvas already running: ${URL}"
      exit 0
    fi
    docker rm -f "$CONTAINER" &>/dev/null || true
    docker network inspect "$NETWORK" &>/dev/null || docker network create "$NETWORK" >/dev/null
    docker run -d --name "$CONTAINER" --network "$NETWORK" \
      -p "127.0.0.1:${PORT}:3000" "$CANVAS_IMAGE" >/dev/null
    for _ in $(seq 1 20); do
      if healthy; then
        echo "Canvas running: ${URL}"
        exit 0
      fi
      sleep 1
    done
    echo "Error: canvas did not become healthy at ${URL}. Last logs:" >&2
    docker logs --tail 20 "$CONTAINER" >&2 || true
    exit 1
    ;;
  stop)
    docker rm -f "$CONTAINER" &>/dev/null || true
    echo "Canvas stopped"
    ;;
  status)
    if is_running && healthy; then
      echo "Canvas running: ${URL}"
    elif is_running; then
      echo "Canvas container is running but not healthy at ${URL}" >&2
      exit 1
    else
      echo "Canvas not running (start it with: $(basename "$0") start)" >&2
      exit 1
    fi
    ;;
  *)
    usage
    ;;
esac
