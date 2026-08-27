# Bonio Agent DSH 重构 — 实现文档（阶段 1）

> 日期：2026-08-26
> 分支：dsh
> 范围：HarmonyOS 优先；用 DeepSeek Harness (dsh) 完全替代 hiclaw 后端

## 1. 目标

用运行在 ohos 设备本机的 **dsh（DeepSeek Harness）** 替代原 hiclaw（C++ WebSocket gateway）作为 Bonio Agent 的 agent 后端：

```
重构前:  avatar ⇄ bonio-app ⇄ (WebSocket hiclaw 协议) ⇄ hiclaw(C++ :10724) ⇄ LLM
重构后:  avatar ⇄ bonio-app ⇄ (WebSocket hiclaw 协议) ⇄ dsh 进程内 bonio-bridge(:10724) ⇄ dsh agent ⇄ DeepSeek LLM
```

- bonio-app 作为 dsh 的 client（协议兼容，业务代码最小改动）
- avatar 职责不变，继续与 bonio-app 同进程通信
- **工具由 dsh 本地执行**（决策 1）、**独立常驻服务**（决策 2）、**token 简化认证**（决策 3）、**删除 hiclaw**（决策 4）、**仅 HarmonyOS**（决策 5）

## 2. 环境与前置

### 2.1 设备

- HUAWEI Mate 80 RS（SGU-AL10，HarmonyOS，aarch64，musl libc）
- hdc：`/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc`
- 需 `hdc target mount` 使 `/usr/local` 可写（根文件系统 erofs 只读，实际写入系统 overlay upper）

### 2.2 Node.js（ohos 平台）

- 来源：https://github.com/hqzing/ohos-node （node-openharmony 预编译包，`node-v26.7.0-openharmony-arm64.tar.gz`）
- 部署到设备 `/usr/local/`（实际存储于 `/mnt/overlay_merge/usr/upper/usr/local`，持久分区）
- 需创建 `/usr/bin/env`、`/usr/bin/node` 链接修复 npm shebang（`#!/usr/bin/env node`）
- 详见 `tools/deploy-node-ohos.sh`

### 2.3 DeepSeek Harness (dsh)

- 版本 0.1.1-rc.2，设备上 npm 全局安装（`/system/usr/local/lib/node_modules/@deepseek-ai/dsh`）
- API key 配置于 `/data/local/home/.dsh/.credentials.yaml`（`DEEPSEEK_API_KEY`）
- 启动器 `/usr/local/bin/dsh`（HOME 感知 wrapper，见 `tools/deploy-node-ohos.sh`）

## 3. bonio-bridge 插件

### 3.1 位置与结构

```
dsh-plugins/bonio-bridge/
├── package.json          # @bonio/dsh-bonio-bridge（dsh.bundle 声明）
├── cordis.patch.yml      # bundle patch（插入 bonio-bridge 行）
├── build/                # 部署产物（ESM JS，免编译）
│   ├── index.js          # cordis 插件入口（apply + inject）
│   ├── gateway.js        # ws WebSocket 服务端 + hiclaw 协议解析
│   ├── driver.js         # dsh Agent 驱动（chat 映射、流式、工具桥）
│   ├── sessions.js       # operator/node 双 session 注册表 + pending invoke
│   └── protocol.js       # 帧格式工具（req/res/event）
├── src/                  # TypeScript 参考实现（与 build 同步）
└── test/                 # smoke 测试客户端
```

### 3.2 协议实现

bonio-bridge 在 `127.0.0.1:10724` 暴露 hiclaw 兼容 WebSocket 协议：

| 方法/事件 | 实现 |
|---|---|
| `connect.challenge` (event) | 连接即下发 nonce |
| `connect` (req) | token 认证；响应结构匹配客户端（`server.host` + `snapshot.sessionDefaults.mainSessionKey`） |
| `chat.send` (req) | **立即返回 runId**（复用客户端 idempotencyKey），agent 后台运行 |
| `agent` (event) | 流式 assistant 增量（**累计文本**，`stream:'assistant', data:{text}`） |
| `chat` (event) | 最终状态（`state:'final'/'error'`） |
| `chat.abort` (req) | 取消运行 |
| `chat.history` (req) | 从 dsh session log 读取（user/assistant 消息） |
| `sessions.list` (req) | 活跃会话列表（key/updatedAt/displayName） |
| `node.invoke.request` (event) | dsh 工具调用 → 路由到 node session |
| `node.invoke.result` (req) | 工具结果回填 dsh agent 循环 |
| `node.event` (req) | chat.subscribe 等（接受） |
| `health` (req) | 心跳检查 |
| `voicewake.get/set` (req) | 空唤醒词（阶段 1） |
| `config.get` (req) | 基础配置 |
| `tick` (event) | 30s 心跳 |

### 3.3 关键设计

- **双 session**：operator（聊天/配置）+ node（服务端工具调用），与 hiclaw 架构一致
- **会话连续性**：同 sessionKey 复用同一 dsh agent（`Map<sessionKey, agent>`），多轮对话有上下文
- **工具路由**：注册 dsh 工具 `bonio_node_invoke`（注意：**下划线**命名，DeepSeek API 不接受点号工具名），模型调用 → `node.invoke.request` → node session 执行 → 结果回填
- **流式时序**：`chat.send` 立即返回（客户端 30s 超时约束），agent 事件用客户端 runId（pendingRuns 过滤），流式文本发累计值（客户端是替换语义）

### 3.4 依赖注入

插件声明 `inject: ['tools', 'agents', 'sessions', 'agentDefaultModel']`，确保这些 service 在 `apply` 时已就绪（工具注册直接在 apply 中执行）。

## 4. 常驻服务

设备上 `/data/local/bin/dsh-daemon.sh`（见 `tools/dsh-daemon.sh`）每 15s 检查 dsh 进程，未运行则重启：

```bash
/data/local/bin/dsh-daemon.sh start|stop|restart|status   # 显式命令
/data/local/bin/dsh-daemon.sh                              # 守护循环（nohup 运行）
```

- 已实测：kill dsh 后 15s 内自动重启，端口恢复
- 开机自启：由 bonio-app（载体）在启动时拉起（`EntryAbility` 已实现自动连接）

## 5. bonio-app（HarmonyOS 客户端）改动

| 文件 | 改动 |
|---|---|
| `common/SecurePrefs.ets` | 默认网关改为 `127.0.0.1:10724`、manual 默认开启、默认 token `bonio-local-token` |
| `entryability/EntryAbility.ets` | 启动时自动 `connectManual()`（manual 开启时） |
| `node/chat/ChatController.ets` | `handleGatewayEvent` 增加 `avatar.command` 分支，暴露 `onAvatarCommand` 回调 |
| `pages/FloatWindowPage.ets` | 消费 `avatar.command`（setBubble 气泡 / setState / clearBubble） |

构建：DevEco Studio hvigor（`assembleHap`），产物 `entry/build/default/outputs/default/entry-default-signed.hap`。

## 6. 部署脚本

| 脚本 | 用途 |
|---|---|
| `tools/deploy-node-ohos.sh` | node + dsh 基础部署（含 HOME wrapper） |
| `tools/deploy-bonio-bridge-ohos.sh` | bonio-bridge 一键部署（打包→推送→双位置解压→profile→daemon） |
| `tools/dsh-daemon.sh` | 设备守护脚本模板 |

## 7. 验证结果

### 7.1 协议层（Mac 经 hdc fport 连设备 bridge）

- ✅ connect.challenge → connect（token）→ sessionKey
- ✅ chat.send 29ms 返回，runId 与 idempotencyKey 匹配
- ✅ 流式 agent 事件（累计文本）+ chat final 完整回答
- ✅ 多轮对话：记住名字 → 追问名字 → 正确回答
- ✅ chat.history 返回完整消息列表；sessions.list 返回活跃会话
- ✅ 工具调用：模型调用 bonio_node_invoke(camera.snap) → node.invoke.request → result 回填

### 7.2 真机 UI 层（bonio-app on device）

- ✅ 自动连接本机 dsh（UI 显示 "Connected"）
- ✅ 用户消息 "7乘以8等于多少？" → dsh agent → LLM → **UI 显示答案 "56"**
- ✅ 流式回复完整渲染（修复累计文本后不再截断为 "Hey"）
- ✅ 守护自愈（kill dsh → 自动重启）

## 8. 已知限制（阶段 1）

- `chat.history` 返回**当前进程内**的 dsh 会话历史（dsh 重启后丢失；持久化待接 dsh session 持久层）
- token 简化认证（未实现 Ed25519 验签）
- `voicewake` 空实现（唤醒词未同步）
- 单 operator session（多客户端连接时后者覆盖）
- bonio-app UI 在多次强杀/重连后有状态显示抖动（客户端生命周期问题）

## 9. 阶段 2 完成情况

> 决策：**不删除 hiclaw 代码**，仅移除 harmonyos 平台对 hiclaw 的依赖（mac/pc/android 后续逐步迁移）。

### 9.1 已完成 ✅

| 工作 | 实现 |
|---|---|
| 移除 harmonyos UI 对 hiclaw 端点引用 | `ServerTab/LoginPage/Index` 默认值改为 `127.0.0.1:10724` + `bonio-local-token` |
| 记忆系统 → dsh | `memo_save`/`memo_list` 工具（`~/.bonio/memos` JSON 存储，与 hiclaw 同布局）；修复设备 `HOME=/root` 问题 |
| 定时任务 → dsh | `cron_add`/`cron_list`/`cron_remove`/`cron_runs` 工具（`~/.bonio/cron/jobs.json` 持久化调度器，支持 every/at/cron 表达式，30s tick 触发 agent 运行） |
| 设备信息 | `device_info` 工具（平台/架构/版本） |
| 工具契约修复 | `output.render(args, value)` 与 `execute(args, exec)` 签名对齐 dsh ToolRuntime；DeepSeek 工具调用后可能直接 turn/end，工具结果回退为最终文本 |

### 9.2 实测验证

- ✅ memo_save 保存"会议提醒/购物清单"2 条 → memo_list 读取并格式化"共有 1 条备忘: - 会议提醒: 明天下午3点开会"
- ✅ cron_add "every 1m" → jobs.json 持久化 → 60s 后调度器触发（`cron firing` + runs 计数）
- ✅ 基础聊天流式正常（修复后回归）

### 9.3 阶段 3：历史持久化（已完成 ✅）

bonio-app 聊天历史**跨 dsh 重启持久化**：

- dsh session 持久层：JSONL 后端（`~/.dsh/sessions/--root--/<id>/session.jsonl.zstd`），dsh-base 默认启用
- bridge：`sessionKey → dsh sessionId` 映射持久化到 `~/.bonio/session-map.json`
- `getOrCreateAgent`：有持久化映射时用 `agents.resume()` 恢复（保留多轮上下文），否则新建并记录映射
- `getHistory`：无活跃 agent 时从 `sessionPersistence.load()` 恢复事件 → hiclaw 消息
- `listSessions`：合并活跃 agent + 持久化 session-map 条目
- 实测：发"1+1" → 重启 dsh → 历史返回原对话 → 追问"刚才的问题答案"→ 回答"2"（会话连续）

### 9.4 待后续（不阻塞 HarmonyOS 使用）

- ~~意图路由/健康提醒/通知处理~~（阶段 4 已实现，见 §10）
- 微信通道（wechat/wecom/ilink）：保留 hiclaw 侧实现，HarmonyOS 场景暂不迁移（需独立 dsh 插件）
- Android/桌面端接入（mac/pc/android 后续按同样模式迁移）

## 10. 阶段 4：功能类需求（已完成 ✅）

bonio-app 客户端本地功能（`harmonyos/entry/src/main/ets/intent/`），替代 hiclaw 服务器端子系统的功能决策：

| 功能 | 实现 | 状态 |
|---|---|---|
| 语音意图路由 | `IntentRouter.ets` — STT 转录本地分类（Chat/截屏/总结，中英文关键词） | ✅ 已实现并接入 TalkModeManager |
| 健康提醒 | `HealthMonitor.ets` + `HealthScheduler.ets` — 屏幕时间累积 + 深夜检测 + 分级提醒（gentle/strong，avatar.command 序列） | ✅ 已实现并接入 NodeRuntime |
| 通知处理 | `NotificationHandler.ets` — 重要通知（微信/短信/钉钉等）→ avatar 反应 | ✅ handler 已实现，系统订阅待特权权限 |
| avatar 命令增强 | `AvatarCommand.ets`（共享类型）+ FloatWindowPage `sequence`/`moveTo` 支持 | ✅ |
| 协调器 | `FeatureManager.ets` — 统一接入 NodeRuntime/TalkModeManager | ✅ |

**构建**：DevEco hvigor 编译通过（`BUILD SUCCESSFUL`），HAP 含全部功能。

## 11. 特权 API 清单（需隔离环境系统签名）

> bonio-app 将在隔离机器开发，具备全部 HarmonyOS 特权 API 权限。以下功能**已实现代码框架 + 注释标记**，需在隔离环境补齐系统签名后启用：

| 功能 | 所需特权能力 | 位置 | 状态 |
|---|---|---|---|
| 全屏截图（截屏/总结意图动作） | `ohos.permission.CAPTURE_SCREEN`（系统签名）+ 截屏扩展能力 | `NodeRuntime.ets handleCaptureIntent()`（注释标记 PRIVILEGED API） | 框架就绪，待特权签名 |
| 系统通知监听 | `ohos.permission.NOTIFICATION_CONTROLLER`（系统签名）或通知订阅能力 | `NotificationHandler.ets onNotificationChanged()` | handler 就绪，订阅接入待特权 |
| 悬浮窗增强 | 悬浮窗显示权限（系统签名） | `FloatWindowManager.ets` | 已有基础实现 |
| 无障碍屏幕读取 | `ohos.permission.READ_SCREEN_CONTENT`（辅助功能） | 截屏/总结可选路径 | 待评估 |

**迁移指引**：在隔离环境（DevEco + 系统签名）：
1. 配置 `build-profile.json5` 的签名材料（当前文件已 revert 避免泄露密码）
2. 在 `handleCaptureIntent()` 的 PRIVILEGED 标记处实现实际截图（AVScreenCapture 或无障碍）
3. 在 `NotificationHandler` 接入 `notificationManager.on('notification')` 系统订阅
4. 重新构建部署

## 12. 参考

- 架构方案：`docs/design/arch/20260826-dsh-refactor-arch.md`
- bridge 详细文档：`dsh-plugins/bonio-bridge/README.md`
- hiclaw 原实现：`server/`（待删除）
- node 来源：https://github.com/hqzing/ohos-node
