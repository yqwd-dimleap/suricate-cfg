# suricate-cfg

OpenHands / Suricate **部署配置仓**（脚本 + 无密钥模板 + 文档）。  
**不是** Agent Canvas 源码；运行镜像仍为 `ghcr.io/openhands/agent-canvas`。

仓库：<https://github.com/yqwd-dimleap/suricate-cfg>  
现网目录可保持：`/data/openhands`（与容器挂载一致；Git remote 指向本仓）。

## 快速开始

```bash
git clone https://github.com/yqwd-dimleap/suricate-cfg.git
cd suricate-cfg
cp env.sh.example env.sh
# 编辑 env.sh：LOCAL_BACKEND_API_KEY、OH_SECRET_KEY、LLM_*、CORS
mkdir -p config projects logs run .openhands
# 可选：printf '%s' 'your-key' > config/api_key.txt && chmod 600 config/api_key.txt
./start.sh
```

UI：`http://<host>:8011/canvas`  
健康检查：`curl -s http://127.0.0.1:8011/health`

## 目录说明

| 路径 | 是否进 git | 说明 |
|------|------------|------|
| `start.sh` / `stop.sh` | ✅ | 启停容器 |
| `env.sh.example` | ✅ | 环境模板 |
| `env.sh` | ❌ | 本机密钥与实参 |
| `config/api_key.txt` | ❌ | API Key |
| `.openhands/` | ❌ | 会话 / settings / secrets |
| `projects/` `logs/` `run/` | ❌ | 工作区与运行产物 |

详见 `GIT_COMMIT_MAP.md`。

## 默认镜像

`ghcr.io/openhands/agent-canvas:1.16.0`（可用 `OPENHANDS_IMAGE` 覆盖）
