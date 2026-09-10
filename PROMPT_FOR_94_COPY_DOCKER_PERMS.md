你是 47.103.203.94（hostname 预期 a100-8-shanghai）上的运维助手。请把本机 OpenHands Agent Canvas Docker 权限/挂载改成与 8.152.159.194 一致，作为「被控节点」，不要当总控台。

## 目标（必须对齐 194）
- 镜像：`ghcr.io/openhands/agent-canvas:1.16.0`
- 容器名：`openhands-canvas`
- 端口：`8011`（`--network host`）
- `--network host` + `--pid host`
- **不要** `--privileged`
- `--add-host=host.docker.internal:127.0.0.1`
- 挂载：
  - `/data/openhands/.openhands` → `/home/openhands/.openhands`（rw）
  - `/data/openhands/projects` → `/projects`（rw）
  - `/data` → `/data`（**ro**）
  - `/` → `/host`（**ro**）
  - 挂载本机 `nvidia-smi` + `libnvidia-ml.so*` + `libcuda.so*`（ro）
  - 透传本机所有 NVIDIA 字符设备：`/dev/nvidia*`、`nvidiactl`、`nvidia-uvm*`、`nvidia-modeset`、`nvidia-nvlink`、`nvidia-nvswitch*`、`nvidia-caps/*`
- LLM 必须指向 194（不要用 127.0.0.1）：
  - model: `openai/qwen3-coder-next`
  - base_url: `http://8.152.159.194:8005/v1`
  - api_key: `sk-local`
- CORS 必须允许总控浏览器来源：
  - `https://agent.dimleap.cn`
  - `http://8.152.159.194:8011`
- API Key：保留本机已有 `/data/openhands/config/api_key.txt`；若没有则 `openssl rand -base64 32` 生成并写入（权限 600）。**不要**使用 194 的 key。

## 直接执行（可整段跑）

```bash
set -euo pipefail
mkdir -p /data/openhands/{projects,logs,run,config,.openhands}
if [[ ! -s /data/openhands/config/api_key.txt ]]; then
  openssl rand -base64 32 | tr -d '\n' > /data/openhands/config/api_key.txt
fi
chmod 600 /data/openhands/config/api_key.txt
KEY=$(cat /data/openhands/config/api_key.txt)
OH_SECRET_KEY=$(openssl rand -base64 32)

# 确认能访问 194 的 vLLM
curl -fsS -o /dev/null -w "vllm:%{http_code}\n" http://8.152.159.194:8005/v1/models

docker pull ghcr.io/openhands/agent-canvas:1.16.0 || true

GPU_ARGS=()
for f in /dev/nvidia /dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-uvm \
  /dev/nvidia-uvm-tools /dev/nvidia-modeset /dev/nvidia-nvlink \
  /dev/nvidia-nvswitch /dev/nvidia-nvswitch[0-9]* /dev/nvidia-nvswitchctl \
  /dev/nvidia-caps/*; do
  [[ -e "$f" && -c "$f" ]] || continue
  GPU_ARGS+=(--device "$f")
done
[[ -x /usr/bin/nvidia-smi ]] && GPU_ARGS+=(-v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi:ro)
for f in /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1 \
  /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.[0-9]* \
  /usr/lib/x86_64-linux-gnu/libcuda.so.1 \
  /usr/lib/x86_64-linux-gnu/libcuda.so.[0-9]*; do
  [[ -e "$f" ]] && GPU_ARGS+=(-v "$f:$f:ro")
done

docker rm -f openhands-canvas 2>/dev/null || true
docker run -d --restart unless-stopped \
  --name openhands-canvas \
  --network host \
  --pid host \
  --add-host=host.docker.internal:127.0.0.1 \
  -e PORT=8011 \
  -e "LOCAL_BACKEND_API_KEY=$KEY" \
  -e "OH_SECRET_KEY=$OH_SECRET_KEY" \
  -e OH_ALLOW_CORS_ORIGINS_0=https://agent.dimleap.cn \
  -e OH_ALLOW_CORS_ORIGINS_1=http://8.152.159.194:8011 \
  -e OH_ALLOW_CORS_ORIGINS_2=http://127.0.0.1:8011 \
  -e OH_ALLOW_CORS_ORIGINS_3=http://localhost:8011 \
  -e 'OH_ALLOW_CORS_ORIGIN_REGEX=https?://(agent\.dimleap\.cn|8\.152\.159\.194|localhost|127\.0\.0\.1)(:[0-9]+)?' \
  -v /data/openhands/.openhands:/home/openhands/.openhands \
  -v /data/openhands/projects:/projects \
  -v /data:/data:ro \
  -v /:/host:ro \
  "${GPU_ARGS[@]}" \
  ghcr.io/openhands/agent-canvas:1.16.0

# 等健康
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8011/health || true)
  [[ "$code" == "200" ]] && break
  sleep 2
done

# 写入/激活 LLM profile（指回 194）
curl -fsS -X POST "http://127.0.0.1:8011/api/profiles/qwen3-coder-next" \
  -H "X-API-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{
    "include_secrets": true,
    "llm": {
      "model": "openai/qwen3-coder-next",
      "api_key": "sk-local",
      "base_url": "http://8.152.159.194:8005/v1",
      "auth_type": "api_key",
      "native_tool_calling": true,
      "caching_prompt": false,
      "enable_encrypted_reasoning": false
    }
  }'
curl -fsS -X POST "http://127.0.0.1:8011/api/profiles/qwen3-coder-next/validate" \
  -H "X-API-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{
    "llm": {
      "model": "openai/qwen3-coder-next",
      "api_key": "sk-local",
      "base_url": "http://8.152.159.194:8005/v1",
      "auth_type": "api_key"
    }
  }'
curl -fsS -X POST "http://127.0.0.1:8011/api/profiles/qwen3-coder-next/activate" \
  -H "X-API-Key: $KEY"

echo "===== 回传给 194 运维 ====="
echo "URL: http://$(curl -s ifconfig.me 2>/dev/null || echo 47.103.203.94):8011"
echo "URL_fixed: http://47.103.203.94:8011"
echo "API Key: $KEY"
echo -n "LLM validate: "; curl -s -X POST "http://127.0.0.1:8011/api/profiles/qwen3-coder-next/validate" -H "X-API-Key: $KEY" -H 'Content-Type: application/json' -d '{"llm":{"model":"openai/qwen3-coder-next","api_key":"sk-local","base_url":"http://8.152.159.194:8005/v1","auth_type":"api_key"}}'
echo
echo "hostname: $(hostname)"
echo -n "GPU: "; docker exec openhands-canvas nvidia-smi -L 2>/dev/null | wc -l; docker exec openhands-canvas nvidia-smi -L 2>/dev/null | head -3
docker inspect openhands-canvas --format 'Network={{.HostConfig.NetworkMode}} Pid={{.HostConfig.PidMode}} Privileged={{.HostConfig.Privileged}}'
docker inspect openhands-canvas --format '{{range .HostConfig.Binds}}{{println .}}{{end}}'
```

## 验收标准
1. `curl http://127.0.0.1:8011/health` → 200  
2. `docker exec openhands-canvas nvidia-smi -L` 能列出 GPU  
3. 容器内 `/data` 只读、`/host/etc/os-release` 可读  
4. profile validate → `{"valid":true,...}`  
5. 从外网/194：`curl http://47.103.203.94:8011/health` → 200  

## 不要做
- 不要在 94 再部署一套公网 Canvas 域名当总控  
- 不要把 `/data` 改成 rw（除非我另行要求）  
- 不要开 privileged  
- 不要把 LLM base_url 设成 `127.0.0.1:8005`

做完把「回传给 194 运维」那几行原样发我。
