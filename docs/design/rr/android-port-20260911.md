# Android 商用版移植（无 root 可上架）— 原始需求

- 日期：2026-09-11
- 来源：用户口述（2026-09-11 讨论确认，本文档为忠实转述）
- 状态：已确认

## 背景

`harmonyos/` 目录已实现 bonio 的完整体验功能（悬浮宠物 avatar、Magic Cue 双击识屏、伴随记忆、微信通道、设备控制等），但它是**技术验证项目**，实际落地存在障碍：

1. 依赖 root 工程机上的 DSH daemon（Node.js 进程，root 权限运行，承担 agent 后端）
2. app 需要 `system_core` ACL 签名 profile 才能安装（悬浮窗 / CAPTURE_SCREEN / GET_SCREEN_CONTENT / SIMULATE_USER_INPUT / NOTIFICATION_CONTROLLER 等 7 项特权权限）
3. 后端通过 root 直读系统短信 / 通讯录 SQLite 数据库
4. MSDP 屏幕感知是系统级 API，普通签名不可用
5. 综上：不可分发给普通用户

## 目标

将 harmonyos 平台的 bonio 体验功能移植到 Android 平台，成为**可独立上架应用市场的商用 app**：

- 目标设备：无 root 商用 Android 手机（当前验证机：Mac 有线连接的三星商用真机）
- 全部能力走 Android 公开 API + 用户标准授权流程
- 目标市场：国内应用商店优先；Google Play 政策限制另行评估

## 用户原始设想（5 点）

1. 悬浮窗：Android 平台可以有
2. 数据授权：调用 Android 平台标准 API 接口，用户进行授权
3. 后端：实现一个 Android Service，用户授权常驻，代替 DSH
4. View tree：分析 Android 无障碍或其它可行技术路线
5. 截屏：申请标准截屏接口

## 架构决策（讨论确认）

**后端两阶段：**

- **Phase 1**：FGS 内嵌 hiclaw —— android-arm64 二进制以 `libhiclaw.so` 打进 APK，由前台服务拉起，app 双会话连接 `127.0.0.1`，打通全链路
- **Phase 2**：用原生 Android（Kotlin）代码替换 agent 后端（参考 `dsh-plugins/bonio-bridge/src/driver.ts` 裁剪移植）

**边界原则**：app 与后端的唯一耦合面是 gateway 协议（WebSocket）；app 侧功能代码只走 RPC，不感知后端是 hiclaw 子进程还是原生实现，保证 Phase 2 替换时 app 零改动。

**功能路线**：无障碍服务替代 MSDP 屏幕感知；标准 runtime 权限替代 ACL 特权；微信通道维持云端 bot API（与设备特权无关）。

## 验收标准（Phase 1）

- 无 root 商用真机直接安装 APK（debug 签名即可）
- FGS 自动拉起本机 hiclaw 引擎进程，operator + node 双会话连接本机 gateway
- 悬浮窗宠物、截屏、聊天基础链路在本地引擎下可用
- 每完成一个阶段 adb 安装到真机验证

## 非目标

- Talk 全双工语音模式（鸿蒙侧自身未完成，无 parity 压力）
- Avatar 皮肤工厂端侧生成（已挂起，仅保留预置皮肤）
- Google Play 上架合规（国内商店优先；Play 需无障碍用途声明、短信权限不可用等另行评估）
