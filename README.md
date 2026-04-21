# Bonio (BoJi / HiClaw)

Bonio 是一个跨平台 AI 桌面伴侣系统，由一个悬浮动画猫咪角色（BoJi）和 C++ WebSocket 网关服务器（HiClaw）组成，提供智能对话、语音交互、桌面效率工具等能力。

## 核心功能

### 桌面宠物（Avatar）

- 基于 Lottie 动画的悬浮猫咪角色，作为系统级置顶窗口常驻桌面
- 自动锚定到当前活跃窗口顶部，跟随窗口移动（弹性弹簧物理效果）
- 丰富的动画状态：11 种活动状态、3 种运动状态、7 种动作手势
- 空闲时沿窗口边缘自主漫步
- 支持服务端远程控制动画、位置、气泡文字、TTS 等
- 交互方式：单击（随机动画）、双击（文字输入）、长按（语音输入）、右键（功能菜单）、拖拽（调整位置）

### 智能对话

- 多轮对话，持久化会话历史
- 流式响应（WebSocket 逐 token 推送）
- 流式模式下支持工具执行（shell、文件读写、网页抓取、Memory 操作等）
- 系统提示词支持，可定义 BoJi 人设
- 可配置多种模型提供商（Ollama、OpenAI、Anthropic、GLM、MiniMax、Qwen、Kimi、Gemini 及自定义兼容端点）
- 思考深度（Thinking Level）可调

### 语音交互

- 客户端语音识别：Android SpeechRecognizer / macOS `say` / 桌面端 Sherpa-ONNX 离线 ASR（中英双语）
- 语音合成：Windows PowerShell SAPI / macOS `say` / Linux `spd-say` / Android TTS
- 长按宠物进行语音输入，实时显示部分识别结果
- 端到端语音对话延迟目标 1-3 秒

### 伴读（Reading Companion）

- 70/30 分屏布局：浏览器占 70%，伴读窗口占 30%
- 自动提取文章标题结构，生成可导航的目录
- AI 生成文章摘要，预填充到 Markdown 编辑器
- 支持用户内联编辑摘要内容
- 保存到 Memory，带原文 URL 和 `#伴读` 标签

### 记一记（Smart Capture）

- 右键「记一记」一键截取当前窗口，AI 自动分类打标签并保存
- 拖拽「投喂」：将文件、文本、图片拖到宠物身上，触发吃食动画后自动保存和分析
- AI 自动分类通过专用 `boji-notes` 会话完成
- 文件化存储：`index.json` + `attachments/` + `thumbnails/`
- 可浏览的 Memory UI：搜索、标签筛选、卡片网格、详情查看

### 搜同款（Visual Search）

- 右键触发十字光标，在屏幕上框选区域
- 自动截图裁剪选中区域，跳转淘宝以图搜货结果页面

### AI Lens（屏幕标注）

- 全屏截图叠加层，用户绘制标注矩形
- 截图 + 标注发送给 AI 进行分析

### 会议转录 & 双语字幕

- 系统音频环路采集（WASAPI），实时流式转写
- 模板化摘要生成（会议/赛事/课堂），保存到 Memory
- 实时双语字幕浮层，原文 + 翻译，延迟 < 500ms，静默时自动隐藏

## 系统架构

```
┌─────────────────────────────────────────────────┐
│                   HiClaw Server (C++)            │
│         WebSocket Gateway / Agent Loop           │
│    ┌──────────┐ ┌──────────┐ ┌───────────────┐  │
│    │  Chat     │ │  Agent   │ │  Tool Router  │  │
│    │ Handler   │ │  Loop    │ │ (node.invoke) │  │
│    └──────────┘ └──────────┘ └───────────────┘  │
└──────────────────┬──────────────────────────────┘
                   │ WebSocket (Protocol v3)
       ┌───────────┼───────────────┐
       ▼           ▼               ▼
┌──────────┐ ┌──────────┐  ┌──────────────┐
│ Android  │ │HarmonyOS │  │   Desktop    │
│ (Kotlin) │ │ (ArkTS)  │  │  (Flutter)   │
└──────────┘ └──────────┘  └──────────────┘
```

所有客户端维护**双 WebSocket 会话**：
- **operatorSession**：用户命令（聊天、配置）
- **nodeSession**：服务端发起的工具调用（摄像头、截屏、定位等）

## 项目结构

| 目录 | 说明 |
|------|------|
| `server/` | C++ WebSocket 网关服务器（CMake, C++17） |
| `android/` | Kotlin / Jetpack Compose 安卓客户端 |
| `harmonyos/` | ArkTS / HarmonyOS 客户端 |
| `desktop/` | Flutter 桌面客户端（Windows + macOS） |
| `design/` | 功能设计文档（PRD） |

## 快速开始

### 服务器构建

```bash
# Windows x64
cd server && scripts\build-win-x64.bat

# Linux amd64
cd server && scripts/build-linux-amd64.sh

# Android (需要 ANDROID_NDK_HOME)
cd server && scripts/build-android.sh

# HarmonyOS (需要 OHOS_NDK_HOME)
cd server && scripts/build-ohos.sh
```

### 桌面客户端

```bash
cd desktop && flutter pub get && flutter run -d windows
# 或 macOS:
cd desktop && flutter pub get && flutter run -d macos
```

### 安卓客户端

```bash
cd android && ./gradlew assembleDebug
```

## 服务器命令参考

| 命令 | 说明 |
|------|------|
| `hiclaw run "prompt"` | 单轮对话 |
| `hiclaw gateway [--port 18789]` | 启动 WebSocket 网关 |
| `hiclaw serve [port]` | HTTP 服务（POST `{"prompt":"..."}`) |
| `hiclaw agent` | 交互式 REPL 模式 |
| `hiclaw config` | 交互式配置 |
| `hiclaw model list` | 列出已配置模型 |

## 网关协议

WebSocket 协议版本 3，帧类型：`req`（请求）、`res`（响应）、`event`（事件）。

主要 RPC 方法：

| 方法 | 方向 | 说明 |
|------|------|------|
| `connect` | 客户端→服务器 | 认证握手（Ed25519 签名） |
| `config.get/set` | 客户端→服务器 | 获取/更新配置 |
| `chat.send` | 客户端→服务器 | 发送消息，返回 runId（异步流式） |
| `chat.abort` | 客户端→服务器 | 取消进行中的请求 |
| `sessions.list/delete/reset/patch` | 客户端→服务器 | 会话管理 |
| `node.invoke.result` | 客户端→服务器 | 返回工具调用结果 |

主要事件：

| 事件 | 说明 |
|------|------|
| `agent` | LLM 流式 delta（助手文本/工具调用） |
| `chat` | 聊天状态更新 |
| `node.invoke.request` | 服务端请求客户端执行工具 |
| `tick` | 心跳（每 30s） |

## 环境变量

| 变量 | 说明 |
|------|------|
| `HICLAW_WORKSPACE` | 从指定目录读取 `hiclaw.json` 配置 |
| `hiclaw_log` | 日志级别：off/error/warn/info/debug |
| `hiclaw_default_model` | 覆盖配置中的 `default_model` |

## 许可证

私有项目，未公开授权。
