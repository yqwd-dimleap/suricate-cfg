# 被控节点安装清单 — `47.103.203.94`

目标：**194 网页 Canvas 当总控台**；本机只跑 Agent 运行时，管本机磁盘/进程/GPU。  
模型继续用 194 的 vLLM，不必在 47 上再起大模型。

| 角色 | IP | 职责 |
|------|-----|------|
| 总控 / 模型 | `8.152.159.194` | Canvas UI + `qwen3-coder-next` `:8005` |
| 被控节点（本清单） | `47.103.203.94` | OpenHands Agent Server（docker-host） |

入口（装完后在浏览器用 194）：`https://agent.dimleap.cn/canvas` 或 `http://8.152.159.194:8011/canvas`

---

## 0. 前提（两边网络）

在 **47** 上测：

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://8.152.159.194:8005/v1/models
# 期望 200
```

在 **194** 上（或你浏览器所在网络）需能访问：

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://47.103.203.94:8011/health
# 装完后期望 200
```

安全建议（有条件就做）：

- 194 防火墙：`:8005` 仅放行 `47.103.203.94`
- 47 防火墙：`:8011` 仅放行 `8.152.159.194` + 你办公出口 IP（浏览器若直连 47 的 backend）

---

## 1. 机器要求（47）

- Linux + Docker（有 GPU 则可选装驱动；无 NVIDIA Toolkit 也可用设备透传，见下）
- 磁盘建议有 `/data`（或改成你实际数据盘路径）
- 开放端口：**TCP 8011**（Agent 入口）

```bash
docker version
# 可选
nvidia-smi -L
```

---

## 2. 目录与密钥（47）

```bash
sudo mkdir -p /data/openhands/{projects,logs,run,config,.openhands}
sudo tee /data/openhands/config/api_key.txt >/dev/null <<'EOF'
请改成你自己的随机串-不要用194同款上公网
EOF
# 生成示例：
# openssl rand -base64 32 | tr -d '\n' | sudo tee /data/openhands/config/api_key.txt; echo

sudo tee /data/openhands/env.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
export OPENHANDS_ROOT="/data/openhands"
export OPENHANDS_PROJECTS="${OPENHANDS_ROOT}/projects"
export OPENHANDS_LOG_DIR="${OPENHANDS_ROOT}/logs"
export OPENHANDS_RUN_DIR="${OPENHANDS_ROOT}/run"
export HOME_OPENHANDS="${OPENHANDS_ROOT}/.openhands"

export OPENHANDS_MODE="docker-host"
export PORT="8011"
export OPENHANDS_PORT="8011"
export OPENHANDS_CONTAINER_NAME="openhands-canvas"
export OPENHANDS_IMAGE="ghcr.io/openhands/agent-canvas:1.16.0"

# 浏览器从 194 Canvas 切到本机 backend 时需要的 CORS
export OH_ALLOW_CORS_ORIGINS_0="https://agent.dimleap.cn"
export OH_ALLOW_CORS_ORIGINS_1="http://8.152.159.194:8011"
export OH_ALLOW_CORS_ORIGINS_2="http://127.0.0.1:8011"
export OH_ALLOW_CORS_ORIGINS_3="http://localhost:8011"
export OH_ALLOW_CORS_ORIGIN_REGEX='https?://(agent\.dimleap\.cn|8\.152\.159\.194|localhost|127\.0\.0\.1)(:[0-9]+)?'

export LOCAL_BACKEND_API_KEY="$(cat /data/openhands/config/api_key.txt)"
export OH_SECRET_KEY="$(openssl rand -base64 32)"

# LLM 指回 194（不是 127.0.0.1）
export LLM_BASE_URL="http://8.152.159.194:8005/v1"
export LLM_API_KEY="sk-local"
export LLM_MODEL="openai/qwen3-coder-next"
EOF
sudo chmod 700 /data/openhands/env.sh
sudo chmod 600 /data/openhands/config/api_key.txt
```

把 `api_key.txt` 里的值记下来，后面在 194 Canvas「Add backend」要用。

---

## 3. 拉取镜像（47）

```bash
docker pull ghcr.io/openhands/agent-canvas:1.16.0
```

若拉不动 GHCR，从 194 导出再导入：

```bash
# 在 194：
docker save ghcr.io/openhands/agent-canvas:1.16.0 | gzip > /tmp/agent-canvas-1.16.0.tar.gz
# scp 到 47 后：
gunzip -c agent-canvas-1.16.0.tar.gz | docker load
```

---

## 4. start / stop 脚本（47）

可从 194 直接拷：

```bash
# 在 47 上（能 SSH 到 194 时）：
scp root@8.152.159.194:/data/openhands/start.sh /data/openhands/
scp root@8.152.159.194:/data/openhands/stop.sh  /data/openhands/
chmod +x /data/openhands/start.sh /data/openhands/stop.sh
```

若暂时拷不了，最低启动命令（与 194 同模式）：

```bash
source /data/openhands/env.sh
KEY="$(cat /data/openhands/config/api_key.txt)"

# GPU 设备（有卡再加；无卡可删掉 --device 与 nvidia-smi 挂载）
GPU_ARGS=()
for f in /dev/nvidia /dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-uvm \
  /dev/nvidia-uvm-tools /dev/nvidia-modeset /dev/nvidia-caps/*; do
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
  -e "PORT=8011" \
  -e "LOCAL_BACKEND_API_KEY=$KEY" \
  -e "OH_SECRET_KEY=$OH_SECRET_KEY" \
  -e "OH_ALLOW_CORS_ORIGINS_0=$OH_ALLOW_CORS_ORIGINS_0" \
  -e "OH_ALLOW_CORS_ORIGINS_1=$OH_ALLOW_CORS_ORIGINS_1" \
  -e "OH_ALLOW_CORS_ORIGINS_2=$OH_ALLOW_CORS_ORIGINS_2" \
  -e "OH_ALLOW_CORS_ORIGINS_3=$OH_ALLOW_CORS_ORIGINS_3" \
  -e "OH_ALLOW_CORS_ORIGIN_REGEX=$OH_ALLOW_CORS_ORIGIN_REGEX" \
  -v /data/openhands/.openhands:/home/openhands/.openhands \
  -v /data/openhands/projects:/projects \
  -v /data:/data:ro \
  -v /:/host:ro \
  "${GPU_ARGS[@]}" \
  ghcr.io/openhands/agent-canvas:1.16.0
```

说明（与 194 对齐）：

- `/data:ro` + `/:/host:ro`：能读本机；默认不能改 `/data`（要下模型再改 `:rw` 或单独挂可写目录）
- `--network host` + `--pid host`：本机端口/进程可见
- **不要**把 LLM 写成 `127.0.0.1:8005`（那是 47 自己，没有模型）

启动：

```bash
/data/openhands/start.sh
# 或跑完上面的 docker run 后：
curl -s http://127.0.0.1:8011/health
# 期望 ok / 200
```

---

## 5. 在 47 上配置 LLM（指回 194）

容器起来后，用本机 API Key：

```bash
KEY=$(cat /data/openhands/config/api_key.txt)

# 保存并激活 profile
curl -s -X POST "http://127.0.0.1:8011/api/profiles/qwen3-coder-next" \
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
echo
curl -s -X POST "http://127.0.0.1:8011/api/profiles/qwen3-coder-next/validate" \
  -H "X-API-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{
    "llm": {
      "model": "openai/qwen3-coder-next",
      "api_key": "sk-local",
      "base_url": "http://8.152.159.194:8005/v1",
      "auth_type": "api_key"
    }
  }'
echo
curl -s -X POST "http://127.0.0.1:8011/api/profiles/qwen3-coder-next/activate" \
  -H "X-API-Key: $KEY"
echo
```

`validate` 必须 `"valid": true`。若失败：先查 47→194:8005 网络/安全组。

---

## 6. 在 194 Canvas 里挂上这台（总控）

浏览器打开：`https://agent.dimleap.cn/canvas`（或 `http://8.152.159.194:8011/canvas`）

1. **Manage backends / 添加后端**
2. 填写：
   - **Name**：`node-47`（随意）
   - **Host / URL**：`http://47.103.203.94:8011`
   - **API Key**：47 上 `/data/openhands/config/api_key.txt` 的内容
3. 保存，切到 `node-47`
4. 新建对话，试：`nvidia-smi -L` 或 `hostname` / `ls /host/etc`  
   应看到的是 **47** 的主机名与资源，不是 194

若浏览器报 CORS：检查第 2 步 CORS 环境变量并重启 47 容器。

---

## 7. 验收清单（勾选）

- [ ] `47 → http://8.152.159.194:8005/v1/models` = 200
- [ ] `curl http://127.0.0.1:8011/health`（在 47）= 200
- [ ] `curl http://47.103.203.94:8011/health`（在 194）= 200
- [ ] profile validate = true（LLM 用 194）
- [ ] 194 Canvas 能添加并切换到 `http://47.103.203.94:8011`
- [ ] 对话里 `hostname` 显示 47 侧主机名
- [ ] （可选）`nvidia-smi -L` 有输出
- [ ] （可选）`ls /data`、`ls /host/var/log` 可读

---

## 8. 权限速览（装完后 47 上 Agent 能干什么）

| 能力 | 默认 |
|------|------|
| 读 `/data`、`/host` | ✅ 只读 |
| 写 `/projects`（`/data/openhands/projects`） | ✅ |
| `ps` / `top` / 本机端口 | ✅ |
| `nvidia-smi` | ✅（有卡且按上面挂了设备） |
| 出网下模型到 `/data` | ❌（`/data` ro；要下模型改 rw 或加可写挂载） |
| `systemctl restart` 本机服务 | ❌（需另做受限重启接口） |

---

## 9. 回传给 194 运维的信息

装完请回传：

```text
URL: http://47.103.203.94:8011
API Key: <api_key.txt 内容>
LLM validate: ok / fail
hostname: <hostname>
GPU: yes/no
```

194 侧无需改代码；只要在 Canvas 加 backend 即可。
