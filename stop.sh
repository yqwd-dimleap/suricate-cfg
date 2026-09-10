#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/env.sh"
NAME="${OPENHANDS_CONTAINER_NAME:-openhands-canvas}"
PID_FILE="$OPENHANDS_RUN_DIR/agent-canvas.pid"

if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  echo "stopped docker $NAME"
fi
if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
    echo "stopped npm pid=$pid"
  fi
  rm -f "$PID_FILE"
fi
rm -f "$OPENHANDS_RUN_DIR/agent-canvas.pid.docker-logs"
echo "done"
