# bonio-bridge — hiclaw 兼容网关（dsh 插件）

将 DeepSeek Harness (dsh) 作为 Bonio Agent 的后端，替代原 hiclaw（C++ server）。
bonio-app 客户端**零业务代码改动**，仅将连接地址指向本机 dsh（`127.0.0.1:10724`）。

## 架构

```
avatar ⇄（同进程）⇄ bonio-app ⇄（WebSocket hiclaw 协议）⇄ dsh 进程内 bonio-bridge ⇄ dsh agent ⇄ DeepSeek LLM
                                                     （:10724，token 认证，双 session）
```

- **operator session**：聊天（`chat.send` → dsh agent，流式 `agent` 事件 + 最终 `chat` 事件）
- **node session**：设备工具调用（dsh 工具 `bonio_node_invoke` → `node.invoke.request` → node session 执行 → `node.invoke.result` 回填）

## 已实现 dsh 工具

| 工具 | 用途 | 执行位置 |
|---|---|---|
| `bonio_node_invoke` | 设备能力（相机/屏幕/定位/短信/输入等）→ node session | dsh 路由 |
| `memo_save` / `memo_list` | 记忆系统（`~/.bonio/memos` JSON 存储） | dsh 本地 |
| `cron_add` / `cron_list` / `cron_remove` / `cron_runs` | 定时任务（`~/.bonio/cron/jobs.json`，every/at/cron 表达式，30s 触发） | dsh 本地 |
| `device_info` | 设备/运行时信息 | dsh 本地 |

## 已实现协议方法

| 方法/事件 | 状态 | 说明 |
|---|---|---|
| `connect.challenge` (event) | ✅ | 连接即下发 nonce |
| `connect` (req) | ✅ | token 认证（Ed25519 签名忽略，token 简化） |
| `chat.send` (req) | ✅ | 创建 dsh agent，流式返回 runId |
| `agent` (event) | ✅ | 流式 assistant 增量（`stream:'assistant', data:{text}`） |
| `chat` (event) | ✅ | 最终状态（`state:'final'/'error'`） |
| `chat.abort` (req) | ✅ | 取消运行 |
| `chat.history` (req) | ✅ | 返回空历史（阶段 1） |
| `sessions.list` (req) | ✅ | 返回空列表（阶段 1） |
| `node.invoke.request` (event) | ✅ | 工具调用路由到 node session |
| `node.invoke.result` (req) | ✅ | 工具结果回填 agent |
| `node.event` (req) | ✅ | chat.subscribe 等（接受，阶段 1 no-op） |
| `health` (req) | ✅ | 心跳检查 |
| `voicewake.get/set` (req) | ✅ | 空唤醒词（阶段 1） |
| `config.get` (req) | ✅ | 基础配置 |
| `tick` (event) | ✅ | 30s 心跳 |

## 构建

```bash
cd dsh-plugins/bonio-bridge
# 无需 TypeScript 编译：build/ 下为可直接运行的 ESM（与 src/ 同步的 JS 参考实现）。
# 修改 src/*.ts 后需手动同步到 build/*.js，或未来接入 tsc。
```

## 部署到 ohos 设备

```bash
HDC=/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc

# 1. 打包并推送
cd dsh-plugins/bonio-bridge
tar -czf /tmp/bonio-bridge.tgz build/ package.json cordis.patch.yml
$HDC file send /tmp/bonio-bridge.tgz /data/local/bonio-bridge.tgz

# 2. 解压到 dsh 安装目录（使插件可被解析）
$HDC shell "
  mkdir -p /system/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@bonio/dsh-bonio-bridge
  cd /system/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@bonio/dsh-bonio-bridge
  tar -xzf /data/local/bonio-bridge.tgz
"

# 3. 创建 bonio profile
$HDC shell "mkdir -p /data/local/home/.dsh/profiles/bonio/node_modules/@bonio"
$HDC shell "cp -r /system/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@bonio/dsh-bonio-bridge /data/local/home/.dsh/profiles/bonio/node_modules/@bonio/"
# 写入 package.json（bundles 含 @bonio/dsh-bonio-bridge）、cordis.yml、cordis.patch.yml
# 见部署脚本 tools/deploy-bonio-bridge-ohos.sh

# 4. 启动（守护脚本自动重启）
$HDC shell "HOME=/data/local/home LD_LIBRARY_PATH=/usr/local/lib nohup /data/local/bin/dsh-daemon.sh > /dev/null 2>&1 &"
```

## 常驻守护

`/data/local/bin/dsh-daemon.sh`（设备上）每 15s 检查 dsh 进程，未运行则重启：

```bash
/data/local/bin/dsh-daemon.sh start     # 启动 dsh bonio profile
/data/local/bin/dsh-daemon.sh stop      # 停止
/data/local/bin/dsh-daemon.sh status    # 状态
/data/local/bin/dsh-daemon.sh           # 守护循环（默认，nohup 运行）
```

**开机自启**：设备只读分区无法注册 init 服务；由 bonio-app 在启动时调用
`/data/local/bin/dsh-daemon.sh`（bonio-app 是载体，负责拉起后端）——
见重构方案 `docs/design/arch/20260826-dsh-refactor-arch.md` 阶段 2 待办。

## bonio-app 连接配置

- Host：`127.0.0.1`（默认值已改，见 `SecurePrefs.ets`）
- Port：`10724`（默认值已改）
- TLS：关闭
- Token：与 profile `cordis.patch.yml` 的 `token` 一致（默认 `bonio-local-token`）

bonio-app 侧改动（已提交）：
- `SecurePrefs.ets`：默认网关地址改为 `127.0.0.1:10724`
- `ChatController.ets`：`handleGatewayEvent` 增加 `avatar.command` 分支，暴露 `onAvatarCommand` 回调
- `FloatWindowPage.ets`：消费 `avatar.command`（setBubble 气泡 / setState / clearBubble）

> 构建部署 HAP 需要签名证书（build-profile.json5 当前指向 Windows 路径）；
> 有签名环境后构建安装即可，客户端代码无需再改。

## 测试

```bash
# 从 Mac（需先 hdc fport tcp:10724 tcp:10724）
cd dsh-plugins/bonio-bridge/test
BRIDGE_TOKEN=bonio-local-token node smoke-client.mjs chat       # 纯聊天（含多轮+历史）
BRIDGE_TOKEN=bonio-local-token node smoke-tool.mjs              # 工具调用
BRIDGE_TOKEN=bonio-local-token node smoke-avatar.mjs            # 事件流
```

## 已知限制（阶段 1）

- `chat.history` 返回**当前进程内**的 dsh 会话历史（dsh 进程重启后丢失；持久化历史待接 dsh session 持久层）
- 认证为 token 简化（未实现 Ed25519 验签）
- `voicewake` 空实现（唤醒词未同步）
- 单 operator session（多个客户端连接时后者覆盖前者）
