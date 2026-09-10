# Mac 本地 OpenHands Canvas → 服务器 Agent 配置

服务器已反代：`https://agent.dimleap.cn` → `127.0.0.1:8010`（OpenHands Agent Server + Canvas ingress）

## 0. 你先做：DNS

在域名控制台给 **A 记录**：

| 主机记录 | 类型 | 值 |
|----------|------|-----|
| `agent` | A | `8.152.159.194` |

生效后本机验证：

```bash
dig +short agent.dimleap.cn
# 应返回 8.152.159.194

curl -sk https://agent.dimleap.cn/health
# {"status":"ok"}
```

> 当前证书是**自签**（浏览器会告警）。DNS 通后可在服务器执行  
> `certbot --nginx -d agent.dimleap.cn` 换成 Let’s Encrypt。  
> Electron 可用 `webSecurity` / 信任自签，或先忽略证书错误做联调。

---

## 1. 后端连接（Manage Backends / 写死配置）

**推荐（免 TLS，HTTP 直连）：**

| 配置项 | 值 |
|--------|-----|
| **Backend name** | `dimleap` |
| **Host / Base URL** | `http://8.152.159.194:8011` |
| **API Key** | 本机 `config/api_key.txt` / `env.sh` 中的 `LOCAL_BACKEND_API_KEY`（勿写入公开文档） |
| **类型** | 云端（或按 IDE 要求选能填自定义 URL 的那项） |

本机验证：

```bash
curl -s http://8.152.159.194:8011/health
# {"status":"ok"}
```

备用（HTTPS 域名，自签证可能告警）：`https://agent.dimleap.cn`  
UI：`http://8.152.159.194:8011/canvas`

环境变量等价（若你的二开支持）：

```bash
export LOCAL_BACKEND_API_KEY='<from-env.sh-or-config/api_key.txt>'
# 或前端启动参数 / Electron config：
# backendBaseUrl = 'https://agent.dimleap.cn'
# backendApiKey  = 同上
```

**不要**在 Mac 上再起一套 Agent Server；Mac 只跑你二开的 Canvas UI。

---

## 1b. 服务端默认 LLM（已配好，DMG 零配置）

运维已在 `agent.dimleap.cn` 上挂好：

| 项 | 值 |
|----|-----|
| active profile | `qwen3-coder-next` |
| model | `openai/qwen3-coder-next` |
| provider_connection_id | `2c3520b59c9b429a9ed6e19e186f2972` |
| base_url（connection） | `http://host.docker.internal:8005/v1` |

Mac 连上后端后应直接可用；若仍提示 Add API Key，刷新/重开 IDE，并**新开对话**。

---

## 2. LLM（仅当需要手动改时）

这些地址是**服务器容器访问 vLLM** 用的（已切到 coder-next）：

| 配置项 | 值 |
|--------|-----|
| Custom Model | `openai/qwen3-coder-next` |
| Base URL | `http://host.docker.internal:8005/v1` |
| API Key | `sk-local` |

备用（旧）：`openai/qwen3-32b` @ `http://host.docker.internal:8000/v1`

---

## 3. Workspace（沙箱项目）

| 配置项 | 值 |
|--------|-----|
| 容器内路径 | `/projects/hello-agent` |
| 服务器宿主机 | `/data/openhands/projects/hello-agent` |
| 冒烟提示词 | 见该目录 `README.md`（给 `mathutil.py` 加 `add` + pytest） |

新项目：放到服务器 `/data/openhands/projects/<name>`，Canvas 里 Open Workspace → `/projects/<name>`。

---

## 4. Electron / 内嵌二开建议

```js
// 示例：桌面端默认后端
module.exports = {
  agentBackend: {
    baseUrl: 'https://agent.dimleap.cn',
    apiKey: process.env.MARMOT_OH_API_KEY, // 勿把 key 打进公开安装包
    canvasPath: '/canvas',
  },
}
```

- 入口：新窗口 `loadURL('https://agent.dimleap.cn/canvas')`，或本地 UI 只把 API/WS 指到 `baseUrl`
- 需支持：**HTTPS、WebSocket Upgrade**（nginx 已开）
- 自签阶段：开发可 `session.setCertificateVerifyProc` 放行 `agent.dimleap.cn`，或临时用系统信任该 crt

健康检查（Mac）：

```bash
curl -sk https://agent.dimleap.cn/health
curl -sk https://agent.dimleap.cn/server_info | head
```

---

## 5. 联调检查清单

1. DNS → `8.152.159.194`
2. `curl -sk https://agent.dimleap.cn/health` → `ok`
3. Canvas 填 Base URL + API Key，backend 显示 connected
4. Settings → LLM 按第 2 节保存
5. Open `/projects/hello-agent`，发一条改代码任务

---

## 6. 服务器侧运维（备忘）

```bash
/data/openhands/start.sh
/data/openhands/stop.sh
docker ps --filter name=openhands-canvas
nginx -t && systemctl reload nginx
```

nginx 配置：`/etc/nginx/sites-available/agent-dimleap`
