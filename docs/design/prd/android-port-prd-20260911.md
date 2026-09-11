# Android 商用版移植 — 精化 PRD

- 日期：2026-09-11
- 源需求：[rr/android-port-20260911.md](../rr/android-port-20260911.md)
- 状态：已确认

## 1. 背景与目标

将 `harmonyos/` 平台的 bonio 体验功能移植为无 root、可上架国内应用商店的 Android 商用 app。后端采用两阶段方案（Phase 1 FGS 内嵌 hiclaw 二进制 → Phase 2 Kotlin 原生替换），app 与后端仅以 gateway 协议耦合。

## 2. 现状基线（调研结论）

Android app（`ai.axiomaster.boji`）**已具备**：

| 能力 | 实现 |
|---|---|
| 悬浮窗宠物 | `FloatingWindowService`（SYSTEM_ALERT_WINDOW + Lottie + 气泡 + 克隆窗） |
| 常驻前台服务 | `NodeForegroundService`（START_STICKY，dataSync/mic/mediaProjection 类型） |
| 无障碍 | `BonioAccessibilityService`（节点遍历、文本缓存、input.type/find 注入） |
| 截屏/录屏 | MediaProjection（ScreenCaptureManager / ScreenRecordManager） |
| 通知监听 | `DeviceNotificationListenerService`（快照/事件/回复） |
| 来电 | CallStateMonitor + TelephonyHandler（接听/挂断） |
| 相机/定位/设备状态 | CameraHandlerImpl / LocationHandlerImpl / DeviceHandlerImpl |
| 双 WS 会话 | NodeRuntime（operator + node）、Ed25519 设备身份、mDNS 发现 |
| 语音 | Sherpa-ONNX 离线 STT + 系统 TTS |
| Canvas/A2UI、技能市场 | 已实现 |

**缺口**：

1. 本地引擎（现依赖远程 hiclaw 服务器）
2. SMS / 通讯录 / 日历 handler 为 stub
3. Magic Cue / 伴随记忆 / 层级 RAG / 充电触发向量化（鸿蒙侧新功能）
4. 无障碍树全量 dump 与 screen.context（MSDP 替代）

## 3. 需求清单

### P0 — Phase 1 本地引擎打通（本 PRD 的实施范围）

| ID | 需求 | 说明 |
|---|---|---|
| R1 | hiclaw 打包 | android-arm64 二进制以 `libhiclaw.so` 进 jniLibs；`useLegacyPackaging` 保证解包到 nativeLibraryDir 可执行 |
| R2 | 引擎生命周期 | FGS 内拉起（`--config-dir` 指向 app 私有目录）、端口探活、崩溃重启、service destroy 时终止 |
| R3 | 配置注入 | `<filesDir>/hiclaw/hiclaw.json`；app 现有配置 UI（config.get/set）对本地引擎生效 |
| R4 | 本机双会话 | operator + node 连 `127.0.0.1:<port>`，token + Ed25519 握手，TLS 关闭；自动连接/重连 |
| R5 | 真机验证 | 无 root 商用机 adb 安装；日志确认引擎启动、双会话连上、聊天/截屏链路可用 |

### P1 — 体验移植（后续迭代）

| ID | 需求 | 路线 |
|---|---|---|
| R6 | contacts/calendar 实装 | ContactsContract（PhoneLookup）/ CalendarContract 替换 stub |
| R7 | 短信能力 | SmsManager 发送；Telephony.Sms 读取 + 运营商账单正则解析（移植 `dsh-plugins/bonio-bridge/src/sms_store.ts`）；可选模块 + 降级开关 |
| R8 | 无障碍树增强 | 全树 dump（文本/坐标/可点击）→ `screen.context`；输入框/发送键坐标解析（UiTreeParser 等价） |
| R9 | Magic Cue | 双击识屏 → 截屏 + screen.context → 隐藏会话 `system:magic-cue` vision 分析 → 胶囊条 → 无障碍注入回填（移植 MagicCueController） |
| R10 | 记忆体系 | MemoryService + CompanionMemoryController + MemoryTab 移植；memo 走 RPC |
| R11 | 充电触发向量化 | ACTION_BATTERY_CHANGED 广播替代 30s 轮询；`memory.incremental_sync` RPC |
| R12 | 层级 RAG 域预检 | L1 域正则预取（sms.bill / contacts.search → `<端侧已知事实>` 注入） |

### P2 — 打磨上架（后续迭代）

| ID | 需求 |
|---|---|
| R13 | 后台存活：厂商自启/电池白名单引导（MIUI/EMUI/ColorOS 适配） |
| R14 | 隐私合规：敏感权限单独同意弹窗、用途说明、功能降级开关、软著资质 |
| R15 | 皮肤素材对齐：cat/kun/mario/messi 8×9 WebP 精灵图 |
| R16 | 授权引导页：无障碍 / 通知监听 / 悬浮窗 / 电池白名单统一引导 |

## 4. 关键约束

- **无 root**：一切能力走公开 API + 用户授权
- **协议边界原则**：app 功能代码只走 gateway RPC；不得绕过协议直连后端实现细节（保证 Phase 2 可替换）
- **国内商店优先**：READ_SMS/SEND_SMS 等在国内商店可申请；Google Play 为非目标（P2 评估）
- **一致性测试**：Phase 2 原生后端必须通过同一套协议用例（以 `dsh-plugins/bonio-bridge/test/smoke-*.mjs` 为基）方可替换

## 5. 验收标准

**Phase 1（本次）**：
1. 商用真机（SM-S9380，无 root）`adb install` 成功
2. 启动 app 后 logcat 可见本地引擎进程拉起、gateway 监听、双会话 connect 成功
3. 发送一条聊天消息走通（配置了模型 key 的前提下）；screen.capture 返回截图
4. 杀引擎进程后 FGS 自动重启之；stop service 后引擎退出

**Phase 2**：原生后端通过协议一致性用例；切换后 app 代码零改动。

## 6. 风险

| 风险 | 缓解 |
|---|---|
| 厂商 ROM 杀后台 | 白名单引导 + START_STICKY + 引擎进程与 FGS 分离（进程死可重启） |
| 无障碍树在部分 app 信息稀疏（微信部分页面） | 以截图喂 vision 为主、树仅做坐标定位；接受降级 |
| AGP 不解包 so 导致 exec 失败 | `useLegacyPackaging true` + CI 真机验证 |
| 引擎端口被占用 | 探活失败时换端口重试（上限 N 次），或提示用户 |
