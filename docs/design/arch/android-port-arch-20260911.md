# Android 商用版移植 — 架构设计

- 日期：2026-09-11
- 源需求：[rr/android-port-20260911.md](../rr/android-port-20260911.md)
- 精化 PRD：[android-port-prd-20260911.md](../prd/android-port-prd-20260911.md)
- 状态：实施中（Phase 1）

## 1. 总体架构

```
Phase 1（本次）                          Phase 2（后续）
┌─────────────────────────────┐      ┌─────────────────────────────┐
│ Android App (Kotlin)        │      │ Android App (Kotlin)        │
│  ├ UI / Chat / Avatar 悬浮窗 │      │  ├ 同左（零改动）             │
│  ├ InvokeDispatcher handlers│      │  ├ 同左                     │
│  └ GatewaySession ×2        │      │  └ GatewaySession ×2        │
└──────────┬──────────────────┘      └──────────┬──────────────────┘
           │ ws://127.0.0.1:10724                │ 进程内直调 / 同协议
┌──────────▼──────────────────┐      ┌──────────▼──────────────────┐
│ hiclaw (android-arm64 二进制) │      │ Kotlin 原生 agent 后端        │
│  以 libhiclaw.so 打进 APK，   │      │ (参考 bonio-bridge driver.ts │
│  FGS 从 nativeLibraryDir 拉起 │      │  裁剪移植，OkHttp SSE)        │
└─────────────────────────────┘      └─────────────────────────────┘
```

**边界原则**：app 与后端唯一耦合面 = gateway 协议（v3，WebSocket）。app 功能代码只走 RPC；Phase 2 只替换"会说同一协议的后端"，app 侧零改动。

**认证事实**（server 端调研结论，gateway.cpp:174-230）：connect 认证 = `params.auth.token|password` 与 `gateway.pairing_code` 的共享密钥比对；空 pairing_code = 无认证开箱即连；服务端不校验 Ed25519（app 端设备签名照发，服务端忽略）。

## 2. Phase 1 详细设计

### 2.1 二进制打包

| 项 | 方案 |
|---|---|
| 产物 | `server/build/android-arm64-v8a/hiclaw`（全静态第三方库，仅依赖系统 libc/liblog，见 CMakeLists.txt:75-198） |
| 打包 | 复制为 `android/app/src/main/jniLibs/arm64-v8a/libhiclaw.so`（`lib*.so` 命名才会被打进 APK） |
| 解包 | AGP 默认不解包 so；`app/build.gradle.kts` 增加 `packaging { jniLibs { useLegacyPackaging = true } }`，使 so 落地 `<nativeLibraryDir>` |
| 执行 | Android 10+ 禁止 exec 可写目录（W^X）；从 `applicationInfo.nativeLibraryDir/libhiclaw.so` exec 是唯一合法路径 |
| ABI | 仅 arm64-v8a（目标设备均为 arm64；app 已只带 arm64 sherpa so） |

### 2.2 引擎生命周期（LocalEngineController）

新文件 `android/app/src/main/java/ai/axiomaster/boji/local/LocalEngineController.kt`，单例由 `BonioApp` 持有（与 NodeRuntime 同级，FGS 与 Activity 共享）。

**拉起**（幂等）：
```
ProcessBuilder(nativeLibraryDir/libhiclaw.so,
               "gateway", "--port", port, "--config-dir", filesDir/hiclaw,
               "--log-level", "info")
  environment()["HOME"] = filesDir/hiclaw   // 修正 memo_tool 硬编码 $HOME/.bonio/memos
```
- 启动就绪探活：TCP 连 `127.0.0.1:port`，300ms 间隔，15s 超时
- stdout/stderr 由协程泵入 `<filesDir>/hiclaw/engine.log`（截断保留 ~512KB），可用 `adb shell run-as ai.axiomaster.boji` 查看
- **watchdog**：进程意外退出 → 2s 退避重启，连续 3 次失败后停止并置错误状态（防 crash 循环）

**停止**：FGS `ACTION_STOP` → controller.stop() → `Process.destroy()`。

**触发点**：FGS `onCreate` 与 MainActivity（本地模式开启时）调 `ensureStarted()`；不随 Activity 销毁。

**端口**：默认 **10724**（与鸿蒙拓扑对齐）；探活失败（端口占用且非本引擎）时递增重试（上限 5），最终端口写回 SecurePrefs。

### 2.3 安全

| 项 | 方案 |
|---|---|
| 绑定地址 | **需 server 小改**：gateway.cpp:2085 现为 `server.listen(port)`（绑全网卡）。改为：`cfg.gateway.host` 为可解析具体地址（如 `127.0.0.1`）时 `listen(host, port)`，为空/`0.0.0.0`/`*` 时保持原行为（桌面端不受影响） |
| 认证 | 首次引导生成 128-bit 随机 `pairing_code` 写入 hiclaw.json，并同步存 SecurePrefs 作为 app 连接 token；杜绝空码裸奔 |
| 传输 | 明文 ws 仅 loopback（引擎只绑 127.0.0.1），无网络暴露面；远程连接继续走 wss+指纹 |

### 2.4 配置注入

`<filesDir>/hiclaw/hiclaw.json` 首次引导写入：

```json
{
  "gateway": { "enabled": true, "host": "127.0.0.1", "port": 10724,
               "pairing_code": "<random>" }
}
```

- 文件缺失对 hiclaw 不是错误（回落默认 + ollama 假模型），但显式写 gateway 块保证端口/认证可控
- 模型/LLM key 由 app 现有配置 UI 走 `config.get`/`config.set` RPC 写入（复用 desktop 同款流程），**app 不直接编辑 hiclaw.json**（除首次引导）
- 数据目录（sessions/、memory/、cron/、logs/）由引擎自管，app 全走 RPC

### 2.5 本机连接（app 侧改动）

- `SecurePrefs` 新增键：`local.enabled`（默认 false）、`local.port`（默认 10724）、`local.token`（secure 存储，= pairing_code）
- 连接分支（ServerTab）：本地模式开启时 Connect → `GatewayEndpoint.manual("127.0.0.1", localPort)` + TLS off（`ConnectionManager.resolveTlsParamsForEndpoint` 对 manual+关 TLS 已返回 null → 纯 ws）+ token = `local.token`
- NodeRuntime.connect（NodeRuntime.kt:299）加本地模式取 token 分支
- 断线重连：现有 `GatewaySession.runLoop` 指数退避直接复用；引擎重启后 15s 内自动重连成功
- Node 会话（tool call → InvokeDispatcher：相机/截屏/定位/通知等）与远程模式完全同构，零改动

### 2.6 Server 端变更清单

| 文件 | 变更 |
|---|---|
| `server/src/net/gateway.cpp`（:2085 附近） | listen 按上述 2.3 规则支持 host 绑定 |

其余 server 代码零改动。变更后交叉编译 android-arm64 并在本机 macOS 构建回归。

## 3. 验证方案（真机）

1. `adb install -r android/app/build/outputs/apk/debug/app-debug.apk`（SM-S9380，无 root）
2. logcat 过滤 `LocalEngine`：进程拉起、探活成功
3. `adb shell run-as ai.axiomaster.boji cat files/hiclaw/engine.log`：gateway 启动横幅、监听端口
4. app 内本地模式 Connect → 状态 Connected；`chat.history` bootstrap 置 healthOk
5. 发送聊天（需已配模型 key）；screen.capture 返回截图
6. `adb shell run-as ... kill <engine pid>` → watchdog 2s 重启 → app 自动重连
7. FGS ACTION_STOP → 引擎进程退出

## 4. Phase 2 边界（Kotlin 原生后端）

- 参考实现：`dsh-plugins/bonio-bridge/src/driver.ts`（为 app 场景裁剪过的 TS 版，比 C++ 源近）
- 范围：agent 循环（LLM 流式 + tool call）、隐藏会话（magic-cue / companion-memory）、memo、（可选）cron；OkHttp SSE 做 provider 流式
- 增量替换：先聊天+cue，cron/微信通道可留远程 hiclaw 兜底；协议一致
- **一致性测试**：以 `dsh-plugins/bonio-bridge/test/smoke-*.mjs` 为基抽协议用例，原生后端全绿方可替换
- Phase 1 的 FGS、controller、配置流、连接层全部保留，仅替换子进程为进程内引擎

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 厂商 ROM 杀后台/杀子进程 | FGS + watchdog 重启 + 白名单引导（P2） |
| so 未解包导致 exec ENOENT | useLegacyPackaging + 真机验收项 2 |
| 端口被占/孤儿进程 | 探活 + 端口递增 + 进程 pid 记录 |
| 引擎 crash 循环耗电 | 连续 3 次失败熔断 + 错误状态上报 UI |
| 明文 loopback 被本机恶意 app 盗连 | 随机 pairing_code 认证；Phase 2 可加 per-connect nonce |

## 6. 后续里程碑（对应 PRD P1/P2）

1. P1：contacts/calendar/sms 实装（标准 API 替换 Stubs.kt）
2. P1：无障碍树 dump → screen.context；UiTreeParser 等价
3. P1：MagicCue / CompanionMemory / MemoryTab 移植
4. P1：充电触发（ACTION_BATTERY_CHANGED）+ 层级 RAG 域预检
5. P2：后台存活适配、隐私合规、皮肤素材、授权引导页
