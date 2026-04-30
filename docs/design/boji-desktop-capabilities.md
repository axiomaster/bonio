# BoJi Desktop 能力清单

## 概述

BoJi Desktop 是一个跨平台（Windows / macOS）的 AI 伴侣桌面客户端，通过 WebSocket 连接到 HiClaw/OpenClaw 网关服务器，提供聊天、记忆、桌面自动化等功能。本文档按层级列出所有当前能力。

---

## 1. 基础通信层

### 1.1 Gateway 双会话 (`GatewaySession`)

| 会话 | 角色 | 用途 |
|------|------|------|
| `operatorSession` | 用户指令通道 | 聊天、配置、技能管理、会话管理 |
| `nodeSession` | 服务端调用通道 | 工具调用（相机、设备信息等） |

- 协议版本 v3，帧类型：`req` / `res` / `event`
- Ed25519 设备签名认证 + 可选 token/password
- 自动重连机制
- Profile 区分：OpenClaw（公共网关）vs HiClaw（私有部署）

### 1.2 配置管理 (`ConfigRepository`)

| 方法 | 说明 |
|------|------|
| `getConfig()` | 通过 `config.get` 获取服务端配置（默认模型、模型列表、providers、gateway 配置） |
| `setConfig()` | 通过 `config.set` 更新配置（`default_model`、`models`） |

### 1.3 技能管理 (`SkillRepository`)

| 方法 | RPC | 说明 |
|------|-----|------|
| `listSkills()` | `skills.list` | 列出已安装技能 |
| `enableSkill(id)` | `skills.enable` | 启用技能 |
| `disableSkill(id)` | `skills.disable` | 禁用技能 |
| `installSkill(id, content)` | `skills.install` | 安装技能（SKILL.md 内容） |
| `removeSkill(id)` | `skills.remove` | 删除技能 |

---

## 2. AI 交互层

### 2.1 聊天 (`ChatController`)

| 能力 | 说明 |
|------|------|
| 发送消息 | `sendMessage(text, {attachments})` 支持文本 + 图片附件 |
| 流式响应 | 实时接收 LLM 回复（`agent` 事件），支持 tool call 状态 |
| 思考级别 | `setThinkingLevel` 支持 off/low/medium/high |
| 中止请求 | `abort()` 中止正在进行的请求 |
| 历史记录 | `chat.history` 加载会话历史 |
| 会话管理 | `sessions.list` / `sessions.delete` 多会话支持 |
| 幂等性 | 每条消息带 `idempotencyKey` 防重复 |

### 2.2 语音识别 STT (`SherpaOnnxSpeechManager`)

| 能力 | 说明 |
|------|------|
| 引擎 | Sherpa-ONNX 流式中英双语 paraformer |
| 输入 | PCM16 16kHz 单声道，通过平台麦克风 |
| 输出 | 实时 partial + final 结果回调 |
| 平台 | Windows (Win32 mic) / macOS (CoreAudio mic) |

### 2.3 语音合成 TTS (`DesktopTts`)

| 平台 | 实现 |
|------|------|
| Windows | PowerShell + System.Speech.Synthesis |
| macOS | `/usr/bin/say` + 临时 UTF-8 文件 |
| Linux | `spd-say` / `espeak-ng` / `espeak` |

---

## 3. 桌面自动化层 (GUI Agent)

### 3.1 屏幕捕获 (`ScreenAgent`)

| 方法 | 说明 |
|------|------|
| `captureScreen()` | 全屏截图（BGRA 像素 + DPI） |
| `captureWindow(hwnd)` | 窗口截图（PrintWindow + BitBlt 回退） |
| `getDpiScale(hwnd)` | 获取窗口所在显示器 DPI 缩放比 |

实现：Win32 `Win32ScreenAgent` / macOS `MacScreenAgent`（存根）

### 3.2 窗口管理 (`WindowAgent`)

| 方法 | 说明 |
|------|------|
| `getForegroundWindow()` | 获取前台窗口句柄 |
| `getWindowTitle(handle)` | 窗口标题 |
| `getWindowClassName(handle)` | 窗口类名 |
| `getWindowRect(handle)` | 窗口矩形（物理像素） |
| `isBrowserWindow(handle)` | 是否为浏览器窗口（Chrome/Edge/Firefox 等） |
| `isNormalAppWindow(handle)` | 是否为普通应用窗口（排除系统窗口） |
| `getMonitorWorkArea(handle)` | 窗口所在显示器工作区（排除任务栏） |
| `resizeWindow(handle, x, y, w, h)` | 调整窗口位置和大小 |

实现：Win32 `Win32WindowAgent` / macOS `MacWindowAgent`（存根）

### 3.3 浏览器自动化 (`BrowserAgent` / CDP)

| 方法 | 说明 |
|------|------|
| `ensureConnected()` | 自动发现并连接 Chrome/Edge（CDP 协议） |
| `getCurrentUrl()` | 获取当前页面 URL |
| `getPageTitle()` | 获取页面标题 |
| `extractPageContent({maxLength})` | 提取页面正文、标题、URL、标题层级 |
| `extractHeadings()` | 提取页面标题层级 |
| `executeScript(js)` | 在页面执行任意 JavaScript |
| `navigate(url)` | 导航到指定 URL |
| `takeScreenshot()` | 页面截图（PNG） |

---

## 4. 宠物/Avatar 层

### 4.1 Avatar 控制 (`AvatarController`)

| 能力 | 说明 |
|------|------|
| 位置控制 | `setPosition` / `userDragTo` / `walkTo` / `runTo` |
| 活动状态 | `setActivity` / `showTemporaryState`（idle, thinking, listening, speaking, happy 等） |
| 气泡对话 | `setBubble(text)` / `clearBubble`，支持倒计时和自定义颜色 |
| 颜色滤镜 | `setColorFilter` 整体色调 |
| 手势动作 | `performAction(type, x, y)` 支持 tap/swipe/longpress/doubletap 等 |
| 输入框 | `toggleInput` / `hideInput` 浮动文本输入 |
| 跨窗口同步 | `toSnapshot()` 序列化状态推送到独立浮动窗口 |

### 4.2 Avatar 命令 (`AvatarCommandExecutor`)

通过 gateway `avatar.command` 事件接收服务端控制指令：

| 命令 | 说明 |
|------|------|
| `setState` / `moveTo` / `setPosition` | 控制位置和状态 |
| `setBubble` / `clearBubble` | 气泡管理 |
| `tts` / `stopTts` | 语音合成 |
| `playSound` | 系统提示音 |
| `setColorFilter` | 颜色滤镜 |
| `performAction` | 手势执行 |
| `sequence` | 命令序列（支持延迟） |

---

## 5. 业务功能层（右键菜单）

### 5.1 记一记 (`note_capture`)

| 项目 | 说明 |
|------|------|
| 触发 | 右键菜单 → 记一记 |
| 流程 | 捕获锚定窗口截图 → 保存为笔记 → LLM 分析标签/摘要 |
| 依赖能力 | 屏幕捕获、窗口信息、笔记存储、聊天（LLM 分析） |
| 关键文件 | `avatar_window_app.dart`, `app_state.dart`, `note_service.dart` |

### 5.2 圈一圈 (`ai_lens`)

| 项目 | 说明 |
|------|------|
| 触发 | 右键菜单 → 圈一圈 |
| 流程 | 窗口截图 → Lens 标注覆盖层 → 用户画矩形 → 截图+标注发送给 LLM |
| 依赖能力 | 屏幕捕获、窗口信息、聊天（LLM 分析） |
| 关键文件 | `avatar_window_app.dart`（LensAnnotationOverlay）, `app_state.dart` |

### 5.3 搜同款 (`search_similar`)

| 项目 | 说明 |
|------|------|
| 触发 | 右键菜单 → 搜同款 |
| 流程 | Lens 模式裁剪商品图 → 淘宝图片搜索 WebView → JS 注入自动上传 |
| 依赖能力 | 屏幕捕获、窗口信息、多窗口管理、WebView |
| 关键文件 | `avatar_window_app.dart`, `app_state.dart`, `search_similar_screen.dart` |

### 5.4 伴读 (`start_reading`)

| 项目 | 说明 |
|------|------|
| 触发 | 右键菜单 → 伴读（需锚定浏览器窗口） |
| 流程 | CDP 提取页面内容 → 调整浏览器窗口布局 → 伴读窗口（目录+摘要+Markdown 编辑器） |
| 依赖能力 | 浏览器自动化(CDP)、窗口管理、多窗口、笔记存储 |
| 关键文件 | `avatar_window_app.dart`, `app_state.dart`, `reading_companion_screen.dart` |

---

## 6. 记忆/笔记层 (`NoteService`)

| 能力 | 说明 |
|------|------|
| 本地存储 | 文件系统持久化 (`boji-notes/`)，索引 + 附件 + 缩略图 |
| 窗口截图保存 | `captureWindow(hwnd)` 截图后自动创建笔记 |
| 拖放保存 | 文本/图片/文件拖入 avatar 自动保存 |
| 阅读笔记保存 | 伴读 Markdown 内容入库 |
| LLM 分析 | 独立会话 `boji-notes` 自动分析标签和摘要 |
| 增删改查 | `saveNote` / `updateNote` / `deleteNote` |

---

## 7. 设备能力层

### 7.1 相机 (`CameraService`)

| 能力 | 说明 |
|------|------|
| 列出相机 | `listCameras()` |
| 拍照 | `snap({cameraId?, facing?})` → JPEG base64 |
| Node 命令 | `camera.list` / `camera.snap` |

### 7.2 设备信息

| Node 命令 | 说明 |
|-----------|------|
| `device.info` | 返回 OS + 版本 JSON |
| `device.platform` | 返回平台标识 |

---

## 8. 市场 (`MarketplaceTab`)

| 页签 | 数据源 | 状态 |
|------|--------|------|
| Skills | ClawHub (`https://clawhub.ai`) | 完整：搜索、详情、下载安装 |
| Models | GitHub Pages (`boji-market/releases/providers.json`) | 浏览型：列表展示 |
| Themes | GitHub Pages (`boji-market/themes.json`) | 浏览型：列表 + 跳转下载 |

---

## 9. 应用壳层

| 组件 | 说明 |
|------|------|
| 主导航 | NavigationRail：Chat / Server / Memory / Market / Settings |
| 多窗口管理 | `desktop_multi_window` 管理 avatar、伴读、搜同款窗口 |
| 系统托盘 | `system_tray` 最小化到托盘 |
| 本地化 | 中文/英文双语（`app_strings.dart`） |
| 窗口管理 | `window_manager` 主窗口属性控制 |
