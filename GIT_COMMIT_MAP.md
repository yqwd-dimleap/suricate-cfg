# suricate-cfg 提交范围梳理（push 前）

目标仓：[yqwd-dimleap/suricate-cfg](https://github.com/yqwd-dimleap/suricate-cfg)  
定位：**镜像运行所需的脚本 + 无密钥配置模板 + 文档**，不是 OpenHands 源码，也不是会话数据。

现网路径可暂保持 `/data/openhands`（与运行中容器挂载一致）；Git remote 指到 suricate-cfg 即可。目录改名用 symlink，另说。

---

## 一、要提交（镜像跑起来的「必要文件」）

| 路径 | 说明 |
|------|------|
| `start.sh` | 起容器：网络/pid、挂载、GPU、字体、CORS、扩展开关等 |
| `stop.sh` | 停容器 |
| `env.sh.example` | 环境变量**模板**（无真实 Key） |
| `.gitignore` | 本文件配套 |
| `README.md` | 怎么 clone、cp env、start |
| `demo/hello-agent/` | 可选：最小示例工程（无密钥） |
| 运维文档（脱敏后） | 如 `DOCKER_PERMS_CHECKLIST.md`、多机清单（**删掉真实 API Key**） |

建议文档里统一写：

```bash
cp env.sh.example env.sh
# 编辑 env.sh：LOCAL_BACKEND_API_KEY / OH_SECRET_KEY / LLM_*
./start.sh
```

---

## 二、绝不提交（运行时 / 密钥）

| 路径 | 原因 |
|------|------|
| `env.sh` | 含 API Key、Secret、本机 LLM 地址策略 |
| `config/api_key.txt` | 鉴权密钥 |
| `.openhands/` 整棵 | `secrets.json`、`settings.json`、conversations、automation DB、profiles 里可能有 key |
| `logs/`、`run/` | 日志与 pid |
| `projects/` | 用户工作区，与配置仓无关 |
| `*.bak*`、`settings.json.*` | 本地备份 |

`.openhands` 大约几十 MB 且含会话，**不属于「跑镜像的必要配置」**，属于**节点状态**；换机应本地生成或加密备份，不要进公开 Git。

---

## 三、边界说明（避免误解）

```
suricate-cfg (git)
  ├── start.sh / stop.sh / env.sh.example   ← 提交
  ├── README / 清单文档                     ← 提交（脱敏）
  └── demo/…                                ← 可选提交

同目录或同机本地（gitignore）
  ├── env.sh                                ← 不提交
  ├── config/api_key.txt                    ← 不提交
  ├── .openhands/                           ← 不提交（挂载给容器）
  ├── projects/ logs/ run/                  ← 不提交

Docker 镜像 ghcr.io/openhands/agent-canvas  ← 不在本仓，只在 env/start 里引用 tag
```

改仓名 **不会** 改镜像内 Python 包名 `openhands`；本仓只是部署配置的「马甲」。

---

## 四、`env.sh.example` 应覆盖的变量（无密钥）

- 路径：`OPENHANDS_ROOT` / `PROJECTS` / `HOME_OPENHANDS` / `LOG` / `RUN`
- 运行：`OPENHANDS_MODE`、`OPENHANDS_UID/GID`、`PORT`、`OPENHANDS_IMAGE`
- 鉴权占位：`LOCAL_BACKEND_API_KEY=<set-me>`、`OH_SECRET_KEY=<set-me>`
- CORS：`OH_ALLOW_CORS_ORIGINS_*`、`OH_ALLOW_CORS_ORIGIN_REGEX`
- LLM 占位：`LLM_BASE_URL` / `LLM_API_KEY` / `LLM_MODEL`
- 可选：`BROWSER_USE_DISABLE_EXTENSIONS=1`

真实值只写在本机 `env.sh`。

---

## 五、首次纳入 git 的检查命令

在部署目录执行：

```bash
cd /data/openhands   # 或 /data/suricate-cfg
git status -u
# 确认不会出现：
#   env.sh  config/api_key.txt  .openhands/  logs/  projects/
git check-ignore -v env.sh config/api_key.txt .openhands/secrets.json
```

人工再扫一遍将提交的 md：有无 Key、内网账号、完整 API Key 字符串。

---

## 六、推荐提交顺序

1. 落地 `.gitignore` + 更新 `env.sh.example` + 本梳理文档  
2. `git init`（若还没有）/ `git remote add origin git@github.com:yqwd-dimleap/suricate-cfg.git`  
3. `git add` 仅白名单文件 → commit → push  
4. **不要** `git add .` 一把梭  

白名单示例：

```bash
git add .gitignore env.sh.example start.sh stop.sh README.md
git add DOCKER_PERMS_CHECKLIST.md demo/hello-agent
# 文档脱敏后再：
# git add MAC_CLIENT.md REMOTE_NODE_*.md nodes/ PROMPT_*.md GIT_COMMIT_MAP.md
```
