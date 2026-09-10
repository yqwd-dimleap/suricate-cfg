# 194 `openhands-canvas` Docker 权限配置清单（供 94 复制）

镜像：`ghcr.io/openhands/agent-canvas:1.16.0`  
容器名：`openhands-canvas`  
模式：`docker-host`（与 `/data/openhands/start.sh` 一致）

---

## 1. 运行时权限（HostConfig）

| 项 | 194 现值 | 说明 |
|----|----------|------|
| `--network host` | ✅ | 共用宿主机网络，可访问本机端口 |
| `--pid host` | ✅ | `ps`/`top` 看宿主机进程 |
| `--privileged` | ❌ **不要开** | |
| `--restart unless-stopped` | ✅ | |
| `CapAdd` / `CapDrop` | 无 | |
| `--add-host host.docker.internal:127.0.0.1` | ✅ | 兼容旧 LLM URL |
| Runtime | `runc` | 无 NVIDIA Container Toolkit 时用设备透传 |

---

## 2. 卷挂载（Binds）

| 宿主机 | 容器内 | 权限 |
|--------|--------|------|
| `/data/openhands/.openhands` | `/home/openhands/.openhands` | **rw**（会话/settings） |
| `/data/openhands/projects` | `/projects` | **rw**（可写工作区） |
| `/data` | `/data` | **ro** |
| `/` | `/host` | **ro**（系统盘只读视图） |
| `/usr/bin/nvidia-smi` | 同路径 | **ro** |
| `libnvidia-ml.so*` / `libcuda.so*`（见下） | 同路径 | **ro** |

容器内用户：`openhands` uid **10001**（镜像默认）。

---

## 3. GPU 设备（Devices，`rwm`）

有什么挂什么（94 同样 8 卡可照挂）：

```
/dev/nvidia0 … /dev/nvidia7
/dev/nvidiactl
/dev/nvidia-uvm
/dev/nvidia-uvm-tools
/dev/nvidia-modeset
/dev/nvidia-nvlink
/dev/nvidia-nvswitch0 … /dev/nvidia-nvswitch5
/dev/nvidia-nvswitchctl
/dev/nvidia-caps/nvidia-cap0
/dev/nvidia-caps/nvidia-cap1
/dev/nvidia-caps/nvidia-cap2
```

驱动库（版本号以本机 `ls` 为准，194 当前是 `580.126.09`）：

```
/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1
/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.<VER>
/usr/lib/x86_64-linux-gnu/libcuda.so.1
/usr/lib/x86_64-linux-gnu/libcuda.so.<VER>
```

---

## 4. 环境变量

| 变量 | 194 | 94 建议 |
|------|-----|---------|
| `PORT` | `8011` | `8011` |
| `LOCAL_BACKEND_API_KEY` | 本机 key | **94 自己的 key** |
| `OH_SECRET_KEY` | 本机 secret | **94 自己生成** |
| `OH_ALLOW_CORS_ORIGINS_*` | localhost 开发源 | **必须含总控来源**（见下） |
| `OH_ALLOW_CORS_ORIGIN_REGEX` | localhost | 放宽含 `agent.dimleap.cn` / `8.152.159.194` |
| `OH_ENABLE_VNC` | `false` | `false` |

**94 CORS 建议（总控在 194 浏览器）：**

```bash
OH_ALLOW_CORS_ORIGINS_0=https://agent.dimleap.cn
OH_ALLOW_CORS_ORIGINS_1=http://8.152.159.194:8011
OH_ALLOW_CORS_ORIGINS_2=http://127.0.0.1:8011
OH_ALLOW_CORS_ORIGINS_3=http://localhost:8011
OH_ALLOW_CORS_ORIGIN_REGEX='https?://(agent\.dimleap\.cn|8\.152\.159\.194|localhost|127\.0\.0\.1)(:[0-9]+)?'
```

---

## 5. 能力对照（装完后 Agent 能做什么）

| 能力 | |
|------|--|
| 读 `/data`、`/host` | ✅ 只读 |
| 写 `/projects`、`.openhands` | ✅ |
| `ps` / `top` / 本机 localhost 服务 | ✅ |
| `nvidia-smi` | ✅ |
| 改 `/data` 其它目录 / 宿主机系统文件 | ❌ |
| `systemctl` 管宿主机服务 | ❌ |

---

## 6. 等价 `docker run` 模板（94 可直接改 key 后用）

```bash
# 在 94 上执行；先准备目录与 key
# /data/openhands/{projects,logs,run,config,.openhands}
# echo 'YOUR_API_KEY' > /data/openhands/config/api_key.txt

KEY=$(cat /data/openhands/config/api_key.txt)
OH_SECRET_KEY=$(openssl rand -base64 32)

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
```

更省事：从 194 拷 `start.sh` + 按上面改 `env.sh` 的 CORS / LLM：

```bash
scp root@8.152.159.194:/data/openhands/start.sh /data/openhands/
# LLM 在 Canvas/profile 里设为 http://8.152.159.194:8005/v1（不要用 127.0.0.1）
```

---

## 7. 与 194 的差异（94 务必改）

| | 194 | 94 |
|--|-----|-----|
| LLM `base_url` | `http://127.0.0.1:8005/v1` | `http://8.152.159.194:8005/v1` |
| CORS | 本机开发源即可 | 必须含 `agent.dimleap.cn` |
| API Key | 194 自己的 | **不要共用**，用 94 自己的 |

验收：

```bash
curl -s http://127.0.0.1:8011/health
docker exec openhands-canvas nvidia-smi -L | head
docker exec openhands-canvas sh -c 'test -r /host/etc/os-release && test ! -w /data && echo perms_ok'
```
