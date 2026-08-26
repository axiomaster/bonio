# DSH 重构 Bonio Agent 架构方案

> 日期：2026-08-26
> 状态：方案设计（待评审）
> 范围：HarmonyOS 优先

## 1. 背景与目标

### 1.1 现状

Bonio Agent 项目分为三部分：

| 部分 | 现状 | 职责 |
|------|------|------|
| **avatar** | HarmonyOS 浮窗（`FloatWindowPage.ets`）/ Android 浮窗（`FloatingWindowService.kt` + `avatar/`） | 悬浮窗虚拟形象，点击/长按/拖拽交互，展示 agent 状态 |
| **bonio-app** | HarmonyOS `entry`（ArkTS）：`NodeRuntime`、`GatewaySession`、`InvokeDispatcher`、`ChatController`、`TalkModeManager` 等 | avatar 载体；对接系统服务（相机/定位/短信/屏幕/语音）；对接 agent 后端 |
| **hiclaw** | `server/`（C++17）：WebSocket gateway（端口 10724）+ agent 循环 + 工具路由 + 微信/来电/cron 等子系统 | agent 后端：大模型对接、会话管理、工具调用路由、事件推送 |

当前通信拓扑：

```
avatar ⇄（同进程）⇄ bonio-app ⇄（WebSocket, hiclaw 自定义协议）⇄ hiclaw (C++ gateway :10724) ⇄ LLM
```

hiclaw 协议帧格式（`GatewaySession.ets` / `gateway.cpp`）：
- 请求：`{type:'req', id, method, params}`
- 响应：`{type:'res', id, ok, payload, error}`
- 事件：`{type:'event', event, payload}`
- 认证：`connect.challenge`（nonce）→ `connect`（Ed25519 签名）
- 双连接：`operatorSession`（role=operator，聊天/配置）+ `nodeSession`（role=node，服务端发起的工具调用）
- 关键方法：`chat.send/abort/subscribe`、`config.get/set`、`sessions.*`、`node.invoke.request/result`、`voicewake.get/set`、`tick`
- 关键事件：`agent`（流式增量）、`chat`（状态更新）、`avatar.command`、`connect.challenge`、`node.invoke.request`、`notifications.changed`

### 1.2 目标

用 **dsh（DeepSeek Harness，运行在 ohos 设备上）** 完全替代 hiclaw 后端：

```
avatar ⇄（同进程）⇄ bonio-app ⇄（协议桥）⇄ dsh（本机 :10724）⇄ DeepSeek LLM
```

- dsh 提供：agent 循环、大模型对接、会话管理、工具系统、记忆/存储、插件体系
- bonio-app 作为 dsh 的 client（协议层兼容，业务代码最小改动）
- avatar 职责不变，继续与 bonio-app 通信
- **优先完成 HarmonyOS 侧重构**

## 2. 已确认的决策

1. **dsh 运行位置**：手机本机运行（与 bonio-app 同机，loopback 通信）
2. **hiclaw 处置**：dsh 完全替代 hiclaw（微信/来电/cron 等子系统由 dsh 插件或 bonio-app 承接）
3. **第一优先级**：通信链路先行——先打通 bonio-app ↔ dsh，跑通聊天/工具调用，再迁移子系统

## 3. 总体架构

### 3.1 目标架构

```
┌────────────────────────────── HarmonyOS 设备 ─────────────────────────────┐
│                                                                            │
│  ┌──────────────┐    同进程      ┌──────────────────────────────────┐     │
│  │    avatar    │ ◄────────────► │           bonio-app              │     │
│  │  (浮窗)      │   AppStorage   │  NodeRuntime (双 session)        │     │
│  └──────────────┘                │  GatewaySession (hiclaw 协议)    │     │
│                                  │  InvokeDispatcher (工具执行器)    │     │
│                                  │  ChatController / TalkMode       │     │
│                                  └───────────────┬──────────────────┘     │
│                                                  │ WebSocket               │
│                                                  │ ws://127.0.0.1:10724    │
│                                                  ▼                        │
│  ┌──────────────────────────────────────────────────────────────────┐     │
│  │                        dsh (Node.js)                            │     │
│  │  ┌───────────────────────────────────────────────────────────┐  │     │
│  │  │ bonio-bridge 插件 (新增)                                 │  │     │
│  │  │  · hiclaw 兼容 WebSocket gateway (:10724)                │  │     │
│  │  │  · connect 认证 (Ed25519 校验)                           │  │     │
│  │  │  · req/res/event 帧适配                                  │  │     │
│  │  │  · chat.send → dsh agent prompt                          │  │     │
│  │  │  · node.invoke.request ⇄ dsh 工具调用                    │  │     │
│  │  │  · avatar.command ← dsh 事件                             │  │     │
│  │  └───────────────────────────────────────────────────────────┘  │     │
│  │  ┌───────────────────────────────────────────────────────────┐  │     │
│  │  │ dsh 核心                                                   │  │     │
│  │  │  · agent loop / LLM (DeepSeek official)                   │  │     │
│  │  │  · session / workspace / storage                          │  │     │
│  │  │  · 工具系统 (tool 注册表)                                 │  │     │
│  │  │  · 插件体系 (cordis)                                      │  │     │
│  │  └───────────────────────────────────────────────────────────┘  │     │
│  └──────────────────────────────────────────────────────────────────┘     │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 关键设计原则

1. **协议兼容优先**：bonio-bridge 插件完整实现 hiclaw 的 WebSocket 协议（帧格式、双 session、认证、工具路由），bonio-app 的 `GatewaySession.ets` **零改动**（仅连接地址从远端 IP 改为 `127.0.0.1:10724`）。
2. **dsh 原生能力为上**：agent 循环、LLM 对接、会话/记忆、工具注册全部用 dsh 原生机制，bridge 只做协议翻译，不做业务逻辑。
3. **渐进式迁移**：第一阶段 bridge 兼容旧协议；后续阶段可让 bonio-app 逐步切换到 dsh 原生 Typert RPC（更丰富的事件模型），bridge 作为过渡层保留。

## 4. 分阶段实施计划

### 阶段 0：环境与基线（已完成）

- dsh 部署到 ohos 设备（node v26.7.0 + dsh 0.1.1-rc.2，headless/web 均验证通过）
- API key 配置（`DEEPSEEK_API_KEY`）
- 验证 `dsh --profile headless "..."` 与 `dsh web` 可用

### 阶段 1：bonio-bridge 插件（通信链路打通）★ 核心

**目标**：bonio-app 通过旧协议连上本机 dsh，聊天 + 工具调用跑通。

#### 1.1 插件结构

新建 `dsh-plugins/bonio-bridge/`（Node.js cordis 插件，独立 npm 包）：

```
dsh-plugins/bonio-bridge/
├── package.json          # @bonio/dsh-bonio-bridge
├── src/
│   ├── index.ts          # cordis 插件入口 (apply)
│   ├── gateway.ts        # ws WebSocket server, hiclaw 协议解析
│   ├── auth.ts           # connect.challenge + Ed25519 校验
│   ├── sessions.ts       # operator/node 双 session 管理
│   ├── chat.ts           # chat.send → dsh agent, 流式转发
│   ├── tools.ts          # node.invoke.request 路由
│   ├── config.ts         # config.get/set → dsh settings
│   └── events.ts         # avatar.command / agent / chat 事件
├── cordis.patch.yml      # dsh profile 补丁层（注册插件）
└── build/                # 编译产物
```

#### 1.2 协议映射表

| hiclaw 方法/事件 | dsh 侧实现 |
|---|---|
| `connect.challenge` (event) | gateway 生成 nonce 下发 |
| `connect` (req) | 校验 Ed25519 签名（用设备公钥白名单）；或阶段 1 简化：token 认证 |
| `chat.send` (req) | 调 dsh agent prompt → 返回 runId |
| `agent` (event) | dsh agent 流式增量 → 转发 |
| `chat` (event) | dsh 会话状态 → 转发 |
| `chat.abort` (req) | dsh 取消当前 run |
| `chat.subscribe` (req) | 会话事件订阅 |
| `sessions.list/delete/reset/patch` (req) | dsh session API |
| `config.get/set` (req) | dsh settings/credentials API |
| `node.invoke.request` (event→nodeSession) | dsh 工具调用 → 路由给 nodeSession |
| `node.invoke.result` (req) | 工具结果回填 dsh agent 循环 |
| `voicewake.get/set` (req) | dsh storage 持久化唤醒词 |
| `tick` (event) | 心跳 |
| `avatar.command` (event) | dsh 事件 → avatar 命令（走 chat 事件通道）|

#### 1.3 工具路由（核心机制）

hiclaw 的工具执行模式：agent 发出 tool_call → gateway 向 nodeSession 发 `node.invoke.request` → 客户端执行 → 回 `node.invoke.result`。

dsh 的等价机制：
1. bridge 向 dsh 注册**桥接工具**（如 `bonio.camera.snap`、`bonio.screen.capture`、`bonio.sms.send`、`bonio.location.get`、`bonio.canvas.*`），工具 schema 与 hiclaw 注册的一致（`camera.snap` 等）。
2. dsh agent 调用工具时 → bridge 拦截 → 向 nodeSession 发 `node.invoke.request`（原 hiclaw 格式）。
3. 客户端执行完回 `node.invoke.result` → bridge 把结果返回给 dsh 工具调用。
4. 工具清单通过 `config` 或 bridge 初始化时声明。

工具能力清单（从 hiclaw `agent.cpp` 提取）：
- `camera.snap/clip`、`screen.capture/record`、`sms.send`、`location.get`
- `canvas.present/hide/navigate/eval/snapshot`、`canvas.a2ui.*`
- `input.type/find`、`system.notify`、`calendar.events`、`contacts.search`
- `memo.save/list`（→ dsh storage）、`cron.add/list/remove`（→ dsh 或 bonio-app）
- `shell`（→ dsh bash 工具）、`skill.read`（→ dsh skill）

#### 1.4 认证方案（阶段 1）

- **推荐**：复用 dsh 现有机制，bridge 配置一个共享 token；bonio-app 连接时带 `auth.token`，bridge 校验后放行（跳过 Ed25519 签名，阶段 1 简化）。
- **后续**：实现 Ed25519 校验插件（node 有 `crypto` 支持 Ed25519 验签，与 `DeviceIdentityStore` 的签名算法兼容）。

#### 1.5 avatar.command 事件流

hiclaw 通过 `avatar.command` 事件驱动 avatar（`setState/moveTo/setBubble/tts` 等）。重构后：
- dsh agent 的工具调用（如 `input.type` 的动画）或子系统事件 → bridge 转为 `avatar.command` 事件 → bonio-app 转发给 avatar（现有 `AvatarCommandExecutor` 逻辑不变）。

### 阶段 2：子系统迁移

| hiclaw 子系统 | 迁移目标 | 说明 |
|---|---|---|
| 微信通道（wechat_adapter/wecom/ilink） | dsh 插件（独立 cordis 插件，复用现有协议客户端逻辑） | 可留在 hiclaw 或迁移；建议后续 |
| 来电处理（call_handler） | bonio-app 侧或 dsh 插件 | 依赖电话系统 API，建议留在客户端侧 |
| 定时任务（cron） | dsh 插件（dsh 已有 `cordis-plugin-timer`） | 低风险 |
| 健康提醒（health_monitor） | dsh 插件 | 纯逻辑，易迁移 |
| 意图路由（intent_router） | bonio-app 侧（本地分类）或 dsh 插件 | 语音 STT 已在客户端，分类可留本地 |
| 记忆（file_memory） | dsh storage / 工具 `memo.save` → dsh 原生记忆 | dsh 有完整存储体系 |
| 通知处理（notification_handler） | bonio-app 侧 → dsh 事件 | 客户端感知通知更直接 |

### 阶段 3：bonio-app 协议演进（可选）

- bonio-app 的 `GatewaySession` 增加 **dsh 原生 Typert RPC 模式**（HTTP POST + WebSocket downlink），获得 dsh 完整的事件模型（session/projections/approval 等）。
- bridge 兼容层保留，作为旧客户端（Android 等）的接入点。

### 阶段 4：桌面端与 Android 端（后续）

- Android 端同 bonio-app 协议，连本机 dsh（如手机）或远端 dsh。
- 桌面端（Flutter）可接入 dsh web（dsh 自带 web GUI），或走 bridge 协议。

## 5. 目录与代码组织

### 5.1 新增目录（仓库内）

```
dsh-plugins/                    # dsh 侧自定义插件（monorepo 或独立包）
├── bonio-bridge/               # hiclaw 协议桥（阶段 1）
├── bonio-wechat/               # 微信通道（阶段 2，可选）
├── bonio-cron/                 # 定时任务（阶段 2，可选）
└── bonio-health/               # 健康提醒（阶段 2，可选）
```

### 5.2 修改点（HarmonyOS 侧）

| 文件 | 改动 |
|---|---|
| `ServerTab.ets` / 配置 UI | 默认地址改为 `127.0.0.1:10724`（或自动检测本机 dsh） |
| `GatewaySession.ets` | 原则上零改动；仅认证流程按阶段 1 方案微调 |
| （新增）dsh 生命周期管理 | bonio-app 启动时拉起 dsh（或独立服务常驻） |

### 5.3 dsh 部署形态

- dsh 以常驻进程运行在设备上（`nohup dsh web --port 13080` 或系统服务）。
- 建议：bonio-app 内置 dsh 进程管理（启动/守护/崩溃重启），或设备上独立服务 + 开机自启。
- bridge 插件通过 dsh profile 的 `cordis.patch.yml` 注册：新增 `bonio` profile 或扩展 `web` profile。

## 6. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 双 session 语义差异（hiclaw 的 operator/node 拆分 vs dsh 单 agent 模型） | 工具调用路由复杂 | bridge 层显式维护 node session 表，工具调用绑定对应 session |
| 认证兼容（Ed25519） | 阶段 1 简化 token；后续实现验签 | node:crypto 支持 Ed25519，算法与客户端一致即可 |
| dsh 事件模型与 hiclaw `agent/chat` 事件差异 | 流式 UI 需适配 | bridge 翻译层隔离差异；阶段 3 可切换到原生协议获得完整模型 |
| 本机运行资源（内存/CPU） | 手机资源有限 | dsh 进程常驻约 ~200MB（含 sharp/koffi）；监控并优化 |
| 微信/来电等强系统耦合子系统 | 迁移工作量大 | 阶段 2 逐项评估，留在客户端侧优先 |
| dsh web 信任围栏（loopback only） | bonio-app 本机连接不受影响；远端连接受限 | 符合"本机运行"决策 |

## 7. 验收标准

### 阶段 1 验收
- [ ] bonio-app 连接 `127.0.0.1:10724` 成功，双 session 建立
- [ ] 聊天发送 → dsh agent 响应 → 流式回显到 bonio-app UI
- [ ] 工具调用链路：LLM 请求相机/屏幕 → nodeSession 执行 → 结果回填 → LLM 继续
- [ ] avatar.command 事件驱动 avatar 状态变化
- [ ] 会话历史持久化（dsh session/storage）
- [ ] 重启 dsh 后 bonio-app 自动重连

### 阶段 2 验收
- [ ] cron/健康提醒迁移到 dsh 插件
- [ ] 记忆系统接入 dsh storage
- [ ] 微信通道可用（如已迁移）

## 8. 待确认事项

1. **工具执行归属**：`shell`、`input.type` 等工具当前由 bonio-app 端执行（node session 路由）。重构后这些工具是通过 bridge 路由回 bonio-app 执行，还是迁移到 dsh 本机执行（dsh 有 bash 工具）？（推荐：能本机执行的用 dsh 原生工具，涉及系统 API 的仍路由回 bonio-app）
2. **dsh 进程管理**：由 bonio-app 拉起并守护 dsh，还是设备上独立服务？（推荐：独立服务 + bonio-app 检测）
3. **认证**：阶段 1 是否接受 token 简化认证（跳过 Ed25519）？（推荐：接受，快速打通）
4. **hiclaw 保留**：阶段 2 迁移完成后，hiclaw（server/）是删除还是保留作为 fallback？（推荐：保留一段时间，双轨运行）
5. **Android/桌面端**：是否纳入本方案后续阶段，还是本次只做 HarmonyOS？

## 9. 参考

- hiclaw 协议实现：`server/src/net/gateway.cpp`、`server/include/hiclaw/net/avatar_command.hpp`
- bonio-app 客户端：`harmonyos/entry/src/main/ets/gateway/GatewaySession.ets`、`node/NodeRuntime.ets`、`node/InvokeDispatcher.ets`
- avatar：`harmonyos/entry/src/main/ets/pages/FloatWindowPage.ets`、`common/FloatWindowManager.ets`、`android/.../avatar/`
- dsh：`@deepseek-ai/dsh` 0.1.1-rc.2（cordis 插件体系、Typert RPC、ws 包）
