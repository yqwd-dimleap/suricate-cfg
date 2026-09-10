#!/usr/bin/env bash
# Start Suricate Agent Canvas.
# Default: docker --network host (agent shares host localhost; /data mounted rw)
# Optional: SURICATE_MODE=npm for pure host (uvx; heavier / flaky on first boot)
# Optional: SURICATE_MODE=docker-bridge for isolated network + port publish
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/env.sh"

MODE="${SURICATE_MODE:-docker-host}"   # docker-host | docker-bridge | npm
NAME="${SURICATE_CONTAINER_NAME:-suricate-canvas}"
IMAGE="${SURICATE_IMAGE:-ghcr.io/openhands/agent-canvas:1.16.0}"
PORT="${SURICATE_PORT:-8011}"
PID_FILE="$SURICATE_RUN_DIR/agent-canvas.pid"
LOG_FILE="$SURICATE_LOG_DIR/agent-canvas.log"
OH_UID="${SURICATE_UID:-0}"
OH_GID="${SURICATE_GID:-0}"

# Migrate legacy host data dir if needed
if [[ -d "${SURICATE_ROOT}/.openhands" && ! -e "${SURICATE_HOME}" ]]; then
  mv "${SURICATE_ROOT}/.openhands" "${SURICATE_HOME}"
fi

mkdir -p "$SURICATE_PROJECTS" "$SURICATE_LOG_DIR" "$SURICATE_RUN_DIR" \
  "$SURICATE_HOME/automation" "$SURICATE_HOME/agent-canvas"
# Compat symlink for tools that still look under ~/.openhands
ln -sfn "$SURICATE_HOME" /root/.openhands 2>/dev/null || true
ln -sfn "$SURICATE_HOME" /root/.suricate 2>/dev/null || true
if [[ "$OH_UID" != "0" ]]; then
  chown -R "$OH_UID:$OH_GID" "$SURICATE_HOME" "$SURICATE_PROJECTS" "$SURICATE_DEMO" 2>/dev/null || true
fi

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  if [[ "$MODE" == "npm" ]]; then
    echo "already running npm pid=$(cat "$PID_FILE")"
    exit 0
  fi
  echo "stopping leftover npm pid=$(cat "$PID_FILE")..."
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$NAME"; then
  echo "already running docker: $NAME"
  docker ps --filter "name=$NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  exit 0
fi

echo "mode=$MODE port=$PORT log=$LOG_FILE"

common_env=(
  -e "LOCAL_BACKEND_API_KEY=$LOCAL_BACKEND_API_KEY"
  -e "OH_SECRET_KEY=$OH_SECRET_KEY"
  -e "OH_ALLOW_CORS_ORIGINS_0=${OH_ALLOW_CORS_ORIGINS_0:-}"
  -e "OH_ALLOW_CORS_ORIGINS_1=${OH_ALLOW_CORS_ORIGINS_1:-}"
  -e "OH_ALLOW_CORS_ORIGINS_2=${OH_ALLOW_CORS_ORIGINS_2:-}"
  -e "OH_ALLOW_CORS_ORIGINS_3=${OH_ALLOW_CORS_ORIGINS_3:-}"
  -e "OH_ALLOW_CORS_ORIGIN_REGEX=${OH_ALLOW_CORS_ORIGIN_REGEX:-}"
  # Avoid multi-minute hang: browser-use downloads uBlock etc. from abroad (often times out here)
  -e "BROWSER_USE_DISABLE_EXTENSIONS=${BROWSER_USE_DISABLE_EXTENSIONS:-1}"
)

# Container-internal paths (/home/openhands) are fixed by upstream image user layout.
common_vols=(
  -v "$SURICATE_HOME:/home/openhands/.openhands"
  -v "${SURICATE_PROJECTS}:/projects"
  -v /data:/data
  # Host root read-only (look under /host/var/log, /host/etc, …). /data also at /data.
  -v /:/host:ro
  # CJK fonts for Chromium browser tool (avoids tofu boxes on baidu etc.)
  -v /usr/share/fonts:/usr/share/fonts:ro
)

# GPU: prefer --gpus all when toolkit exists; else pass host NVIDIA devices + nvidia-smi.
build_gpu_args() {
  GPU_ARGS=()
  if docker run --help 2>/dev/null | grep -q -- '--gpus' \
    && docker info 2>/dev/null | grep -qiE 'Runtimes:.*nvidia|nvidia'; then
    GPU_ARGS=(--gpus all)
    return 0
  fi
  local f
  for f in /dev/nvidia /dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-uvm \
    /dev/nvidia-uvm-tools /dev/nvidia-modeset /dev/nvidia-nvlink \
    /dev/nvidia-nvswitch /dev/nvidia-nvswitch[0-9]* /dev/nvidia-nvswitchctl \
    /dev/nvidia-caps/*; do
    [[ -e "$f" && -c "$f" ]] || continue
    GPU_ARGS+=(--device "$f")
  done
  if [[ -x /usr/bin/nvidia-smi ]]; then
    GPU_ARGS+=(-v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi:ro)
  fi
  # Driver libs needed by nvidia-smi inside the image (no toolkit on this host)
  for f in /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1 \
    /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.[0-9]* \
    /usr/lib/x86_64-linux-gnu/libcuda.so.1 \
    /usr/lib/x86_64-linux-gnu/libcuda.so.[0-9]*; do
    [[ -e "$f" ]] || continue
    GPU_ARGS+=(-v "$f:$f:ro")
  done
}

if [[ "$MODE" == "docker-host" || "$MODE" == "docker" ]]; then
  # host network: localhost:8080 works; PORT must be 8011 (8000 is vLLM)
  if ! command -v docker >/dev/null; then
    echo "docker not found" >&2
    exit 1
  fi
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker pull "$IMAGE"
  fi
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # drop legacy container name if present
  docker rm -f openhands-canvas >/dev/null 2>&1 || true
  build_gpu_args
  # --pid host: ps/top see host processes (e.g. marmot-ai)
  # apparmor=unconfined: allow kill/signal to host PIDs (docker-default blocks it)
  # --add-host: old chats still calling host.docker.internal keep working
  cid="$(docker run -d --restart unless-stopped \
    --name "$NAME" \
    --user "${OH_UID}:${OH_GID}" \
    --network host \
    --pid host \
    --security-opt apparmor=unconfined \
    --add-host=host.docker.internal:127.0.0.1 \
    -e "PORT=$PORT" \
    -e "HOME=/home/openhands" \
    "${common_env[@]}" \
    "${common_vols[@]}" \
    "${GPU_ARGS[@]}" \
    "$IMAGE")"
  echo "$cid" | tee "$LOG_FILE" >/dev/null
  echo "started docker-host name=$NAME id=${cid:0:12} user=${OH_UID}:${OH_GID}"
  echo "http_public=http://8.152.159.194:${PORT}"
  echo "NOTE: host network+pid; apparmor=unconfined; user=${OH_UID}:${OH_GID}; /data:rw; /host = host root :ro; gpu devices mounted"
  echo "llm: ${LLM_BASE_URL} model ${LLM_MODEL}"
  exit 0
fi

if [[ "$MODE" == "docker-bridge" ]]; then
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker pull "$IMAGE"
  fi
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker rm -f openhands-canvas >/dev/null 2>&1 || true
  build_gpu_args
  cid="$(docker run -d --restart unless-stopped \
    --name "$NAME" \
    --user "${OH_UID}:${OH_GID}" \
    -p "0.0.0.0:${PORT}:8000" \
    -e PORT=8000 \
    -e "HOME=/home/openhands" \
    "${common_env[@]}" \
    --add-host=host.docker.internal:host-gateway \
    "${common_vols[@]}" \
    "${GPU_ARGS[@]}" \
    "$IMAGE")"
  echo "$cid" | tee "$LOG_FILE" >/dev/null
  echo "started docker-bridge name=$NAME user=${OH_UID}:${OH_GID} — host loopback services NOT visible as localhost"
  exit 0
fi

# npm
: >"$LOG_FILE"
nohup env \
  HOME="/root" \
  LOCAL_BACKEND_API_KEY="$LOCAL_BACKEND_API_KEY" \
  OH_SECRET_KEY="$OH_SECRET_KEY" \
  PORT="$PORT" \
  OH_ALLOW_CORS_ORIGINS_0="${OH_ALLOW_CORS_ORIGINS_0:-}" \
  OH_ALLOW_CORS_ORIGINS_1="${OH_ALLOW_CORS_ORIGINS_1:-}" \
  OH_ALLOW_CORS_ORIGINS_2="${OH_ALLOW_CORS_ORIGINS_2:-}" \
  OH_ALLOW_CORS_ORIGINS_3="${OH_ALLOW_CORS_ORIGINS_3:-}" \
  OH_ALLOW_CORS_ORIGIN_REGEX="${OH_ALLOW_CORS_ORIGIN_REGEX:-}" \
  agent-canvas --port "$PORT" --public \
  >>"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
echo "started npm pid=$(cat "$PID_FILE") WARNING: /data not forced ro"
