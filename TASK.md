项目名称：OpenClaw 桌面拟人助手 (Desktop Agent Frontend) MVP 阶段
1. 项目背景与目标
本项目旨在开发一款运行在 Android 设备上的“桌面级拟人/玩偶型 AI 助手”（如小螃蟹、机器人或猫咪）。它是 OpenClaw 后端大模型系统的前端/客户端入口。
该助手将以全局系统悬浮窗的形式存在于手机桌面上，用户可以直接点击它进行语音对话。它具有丰富的状态表现（动画、文字气泡），并能处理来自后端的长耗时任务。

2. 核心状态与交互逻辑 (State Machine)
请在前端架构中维护一个清晰的 Agent 状态机：

Idle (待机): 悬浮窗停留在屏幕边缘，播放待机动画（如呼吸、眨眼）。根据定时器或后端推送，偶尔在头顶显示类似漫画效果的文字气泡（纯文本 UI）。

Listening (聆听): 用户单点（Click）悬浮窗触发。麦克风开启，录制音频流，播放“聆听”动画。

Thinking (思考): 语音输入结束，等待后端响应，播放“思考/加载”动画。

Speaking (回复): 接收到后端的语音流或文本，播放合成语音，同步显示文字气泡，并播放“说话/动作”动画。

Working (执行长任务): 当后端下发长耗时任务状态时，主助手恢复 Idle/聊天状态；同时在 UI 上生成一个**较小的子悬浮窗（分身）**展示打工动画。收到 Task_Completed 消息后，销毁子悬浮窗，主助手通过气泡提醒用户。

3. 技术栈与架构要求
目标平台: Android (API Level 24+)。

开发语言: Kotlin + 现代 Android 架构 (建议使用 Coroutines 处理并发)。

UI 渲染: * 核心 UI: 优先考虑原生 View 配合 Lottie (用于加载不同状态的 .json 动画文件)，保证轻量和性能。

布局: 悬浮窗内包含：动画载体 (ImageView/LottieAnimationView) + 气泡框 (TextView/CardView，默认隐藏)。

通信协议: WebSocket (OkHttp 方案)。需要实现长连接、心跳保活、断线重连机制。

4. 核心技术实现指引 (关键 API)
悬浮窗权限与窗口管理:

需申请并检查 android.permission.SYSTEM_ALERT_WINDOW 权限。若无权限，需引导用户跳转至 Settings.ACTION_MANAGE_OVERLAY_PERMISSION。

使用 WindowManager 和 WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY 创建全局悬浮窗。

实现触摸事件 (onTouchEvent) 以支持用户拖拽悬浮窗位置。

音频采集与播放:

需申请 android.permission.RECORD_AUDIO 权限。

使用 AudioRecord 采集 PCM 裸流（方便后续通过 WebSocket 分片上传）。

使用 AudioTrack 或 MediaPlayer 播放后端返回的语音流。

5. 开发阶段划分 (Phases)
请 Antigravity 严格按照以下阶段逐步实现，每完成一个阶段请向我确认并请求进入下一阶段：

Phase 1: 基础悬浮窗与权限闭环

搭建 Android 工程基础。

实现悬浮窗权限的检查、申请与引导跳转逻辑。

使用一个简单的静态图片 (Icon) 作为悬浮窗内容，实现 WindowManager 的添加、拖拽移动、点击事件监听。

Phase 2: Lottie 动画集成与状态机

引入 Lottie 依赖，预留 idle, listen, think, speak 四个占位动画加载逻辑。

实现状态机类 (AgentStateManager)，管理状态切换，并同步更新 Lottie 动画和头顶的“文字气泡” (TextView) 的显示与隐藏。

Phase 3: WebSocket 通信模块

使用 OkHttp 封装 WebSocket 客户端。

定义并解析前端与 OpenClaw 交互的 JSON 数据结构（包含：对话文本、气泡推送指令、长任务开始/结束指令）。

Phase 4: 录音与分身 UI 逻辑

实现麦克风权限申请与音频采集逻辑，将音频流与 Phase 3 的 WebSocket 打通。

实现“长任务分身”逻辑：监听特定 WebSocket 指令，动态创建并销毁第二个较小的悬浮窗。


## android

android平台代码实现

## harmonyos

harmonyos平台代码实现，目录下已经实现了openclaw客户端的功能，能够连接openclaw客户端，并进行语音对话，但是没有实现悬浮窗功能，请将harmonyos目录下的代码进行优化，实现悬浮窗功能，并能够进行语音对话并能够进行长任务执行

## assets

assets目录下是资源文件，请将assets目录下的资源文件进行优化，实现悬浮窗功能，并能够进行语音对话并能够进行长任务执行