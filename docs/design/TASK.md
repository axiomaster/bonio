# 项目名称：BoJi 桌面拟人助手 (BoJi Desktop Agent) 客户端开发文档

## 1. 项目背景与当前状态
本项目旨在开发一款跨平台的“桌面级拟人/玩偶型 AI 助手”。前端核心表现形态为**全局系统悬浮窗**，具备丰富的状态表现（Lottie 动画、文字气泡），并能创建“分身”处理长耗时任务。

**【当前系统架构与进度状态】请务必仔细阅读：**
* **Server 端 (HiClaw)：** 已使用 **C++** 开发完毕。目标是对标并参考 OpenClaw/ZeroClaw 的架构，但专为移动平台（Android/HarmonyOS）做了更轻量化的优化。**（注意：本次开发不需要修改 Server 端代码）。**
* **通信协议：** Client 与 Server 之间的 WebSocket 通信协议**要求尽量与 OpenClaw/ZeroClaw 兼容**，以保证 Client 未来可以独立、无缝对接标准的 OpenClaw 后端。
* **Android 端：** 基础 App 框架已完成，**全局悬浮窗已经在桌面成功运行**。
* **HarmonyOS 端：** 基础 App 框架已完成，**但当前的全局悬浮窗实现存在 Bug，需要修复**。

## 2. 工程目录结构
请严格按照以下 `boji/` 目录树进行客户端代码的开发与修复：
* **android/**: 【当前重点】Android 平台代码（Kotlin）。已有悬浮窗基础，需在此基础上增加 Lottie 状态机、音频录制播放以及 OpenClaw 兼容协议对接。
* **harmonyos/**: 【当前重点】HarmonyOS 平台代码（ArkTS）。已有基础通信代码，**首要任务是修复现存的悬浮窗 Bug**，随后对齐 Android 端的功能。
* **server/**: C++ 实现的轻量级后端服务。（仅供查阅，**禁止修改**）。
* **assets/**: 存放跨平台共用的 Lottie `.json` 动画素材（Idle, Listening, Thinking, Speaking, Working）及 Icon。
* **design/**: 存放 OpenClaw/ZeroClaw 兼容的 WebSocket JSON 协议定义文档。

## 3. 核心状态机与交互逻辑 (State Machine)
客户端必须在本地维护一个 Agent 状态机，根据用户的触摸事件或后端下发的 OpenClaw 兼容信令进行状态流转：

| 状态名称 | 触发条件 | 视觉与交互表现 |
| :--- | :--- | :--- |
| **Idle (待机)** | 默认状态 / 任务结束 | 悬浮窗播放待机动画。偶尔根据后端推送显示“文字气泡”。 |
| **Listening (聆听)** | 用户单点悬浮窗 | 开启麦克风录制音频流，播放“聆听”动画。 |
| **Thinking (思考)** | 语音输入结束 | 等待后端响应，播放“思考/加载”动画。 |
| **Speaking (回复)** | 接收到后端语音/文本流 | 播放合成语音，同步显示文字气泡，播放“说话”动画。 |
| **Working (长任务)** | 后端下发长耗时任务指令 | 主助手恢复 Idle。UI 动态生成**较小的子悬浮窗（分身）**展示打工动画。收到任务完成消息后销毁分身。 |

## 4. 核心技术要求与协议对齐
* **通信协议兼容：** 请在 `design/` 目录下查阅或生成兼容 OpenClaw 规范的 WebSocket JSON 协议格式（例如：音视频流分片格式、Action 信令格式）。
* **HarmonyOS 悬浮窗 Bug 修复：** 鸿蒙系统（API 12 / Next 6.0+）对于全局悬浮窗（`window.WindowType.TYPE_FLOAT` 或 `window.WindowType.TYPE_SYSTEM_ALERT`）有严格的权限和生命周期限制，请重点检查 `ohos.permission.SYSTEM_FLOAT_WINDOW` 权限申请流程、WindowStage 的创建时机以及后台保活机制。

## 5. 开发阶段划分 (Phases)
**执行指令：请基于目前已有的代码基础，严格按照以下阶段逐步迭代。每完成一个阶段请向我确认，并在我允许后进入下一阶段。**

* **Phase 1: 协议对齐与 HarmonyOS 悬浮窗 Bug 修复**
    * 梳理并输出兼容 OpenClaw/ZeroClaw 的 WebSocket 协议文档（至 `design/`）。
    * **审查 `harmonyos/` 目录下的悬浮窗代码，定位并修复无法正常显示或闪退的 Bug，确保其能像 Android 一样在桌面上稳定存在并可拖拽。**
* **Phase 2: Android 端 Lottie 状态机与 UI 增强**
    * 在已成功运行的 Android 悬浮窗基础上，引入 Lottie 依赖加载 `assets/` 中的动画。
    * 实现 `AgentStateManager` 管理状态切换。
    * 增加头顶“文字气泡”的动态显示与隐藏逻辑。
* **Phase 3: Android 端 OpenClaw 协议对接与语音链路**
    * 实现 WebSocket 客户端，按照 Phase 1 的协议与 C++ Server 连接。
    * 实现麦克风录音采集，将 PCM 流分片上传；接收后端音频流并使用 AudioTrack 播放。
    * 将 WebSocket 收发状态与 Phase 2 的 Lottie 状态机打通（如：收到音频流切至 Speaking，等待时切至 Thinking）。
* **Phase 4: Android 端长任务分身机制**
    * 监听 OpenClaw 协议中的长任务信令。
    * 触发时，动态创建第二个较小的“打工分身”悬浮窗，任务完成后销毁分身并气泡提醒。
* **Phase 5: HarmonyOS 端功能对齐**
    * 在修复好悬浮窗的鸿蒙项目中，对齐 Android 端 Phase 2 ~ Phase 4 的所有功能（Lottie 渲染、OpenClaw WebSocket 通信、语音录播、分身悬浮窗）。