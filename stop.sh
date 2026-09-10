#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/env.sh"
NAME="${SURICATE_CONTAINER_NAME:-suricate-canvas}"
PID_FILE="$SURICATE_RUN_DIR/agent-canvas.pid"

stop_docker() {
  local n="$1"
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$n"; then
    docker rm -f "$n" >/dev/null 2>&1 || true
    echo "stopped docker $n"
  fi
}

stop_docker "$NAME"
# legacy name during rename
stop_docker openhands-canvas

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
rm -f "$SURICATE_RUN_DIR/agent-canvas.pid.docker-logs"
echo "done"
