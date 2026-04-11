# 产品需求文档 (PRD)：BoJi 桌面伴随助手 —— "记一记"核心功能版

**文档版本:** V4.1 (含实现状态)
**优先级:** **P0（最高优先级）**
**核心目标:** 打造极低门槛的碎片化信息收集工具，通过拟人化的"投喂"交互实现信息的自动分类、理解与智能检索，让 BoJi 成为用户的数字化随从。

---

## 实现状态

| 功能模块 | 状态 | 说明 |
|---------|------|------|
| 右键智能截屏记 | ✅ 已完成 | "记一记"为右键菜单第一项，截屏 → 保存 → AI 分析全链路打通 |
| 拖拽"喂食"记 | ✅ 已完成 | Win32 IDropTarget COM 实现，支持文件/文本/位图拖放 |
| AI 自动分类 | ✅ 已完成 | 通过 OpenClaw 专用 `boji-notes` 会话，多模态 AI 分析 |
| 动画状态机 | ✅ 已完成 (占位动画) | openmouth/eating/satisfied/refuse 已映射到现有 Lottie 动画 |
| Memory 管理界面 | ✅ 已完成 | 主窗口新增 Memory 标签页，含搜索、标签过滤、卡片网格 |
| 对话式调取 | ⏳ 延后 | 依赖 server 端改造，`boji-notes` 会话已有上下文积累 |
| 数据存储 | ✅ 已完成 | 文件存储 (index.json + attachments/ + thumbnails/)，非 SQLite |

---

## 1. 核心交互场景设计

### 1.1 场景一：右键智能截屏记 (Right-Click Smart Capture)

**功能描述：** 用户通过右键菜单快速捕捉当前窗口内容，由 BoJi 进行自动化归档。

* **交互流程：**
    1. **触发：** 用户在 BoJi 身上点击 **右键**，选择菜单首项 **[记一记]**。
    2. **执行：** App 立即截取当前伴随窗口（Active Window）的图像。BoJi 播放 `happy` 动画。
    3. **处理：** 后台启动多模态 AI 分析（通过 OpenClaw `boji-notes` 专用会话），提取页面文本、图片主体及上下文（窗口标题）。**自动分类：** 根据内容语义自动判定主题标签（如：#购物、#美食、#技术文档）。
    4. **反馈：** BoJi 头顶弹出气泡："已存入 [#tags] 喵！"

**实现细节：**
- 菜单通过 Win32 `TrackPopupMenuEx` 原生渲染
- `avatar_window_app.dart` → `_handleNoteCapture()` 获取 `_anchoredHwnd`
- 通过 `avatarMenuActionWithData` MethodChannel 发送 `{action: 'note_capture', hwnd}` 到主引擎
- `app_state.dart` → `_handleNoteCaptureWithData()` 调用 `NoteService.captureWindow(hwnd)`
- 截图使用 `Win32ScreenCapture.captureWindow(hwnd)` → PNG 编码 → 文件存储
- 缩略图自动生成（200px 宽）

### 1.2 场景二：拖拽"喂食"记 (Drag & Drop Feeding)

**功能描述：** 模拟真实喂食动作，通过物理拖拽将碎片化内容（文字、图片、文件）快速同步给 BoJi。

* **交互流程：**
    1. **准备：** 用户在当前页面或文件夹中选中一段文字、一张图片或一个本地文件。
    2. **触发：** 用户将选中的内容直接 **拖拽** 至 BoJi 的 Avatar 身上。
    3. **视觉反馈：**
        * **感应期（DragEnter/DragOver）：** BoJi 切换至 `openmouth` 动画状态。
        * **吸入期（Drop）：** BoJi 播放 `eating` 动画（2 秒），然后 `satisfied` 动画（1 秒）。
    4. **处理：** App 接收内容流，存储到本地文件系统，异步触发 AI 分析分类。
    5. **反馈：** 气泡显示："已消化 [#tags] 喵！"

**实现细节：**
- Win32 COM `AvatarDropTarget` 类实现 `IDropTarget` 接口
- 支持格式：`CF_HDROP`（文件路径列表）、`CF_UNICODETEXT`（文本）、`CF_DIB`（位图）
- `OleInitialize` + `RegisterDragDrop` 在子窗口创建时注册
- `RevokeDragDrop` 在子窗口移除时注销
- 数据通过 `avatarDrop` MethodChannel 事件从 C++ → Dart → 主引擎

---

## 2. 实体状态机与交互细则 (State Machine)

为了增强"记一记"的趣味性，执行以下动画流转逻辑：

| 状态/动作 | 触发事件 | 当前动画映射 | 理想动画 |
| :--- | :--- | :--- | :--- |
| **IDLE** | 默认状态 | `cat-idle.lottie` | 正常呼吸、偶尔踱步、眨眼 |
| **OPEN_MOUTH** | 外部元素拖入碰撞区 | `cat-happy.lottie` (占位) | 嘴巴张大，身体前倾 |
| **EATING** | 元素被释放（Drop） | `cat-working.lottie` (占位) | 闭嘴咀嚼 |
| **SATISFIED** | 数据成功写入 | `cat-happy.lottie` (占位) | 满足表情，摸摸肚子 |
| **REFUSE** | 格式不支持/文件过大 | `cat-angry.lottie` (占位) | 皱眉、推手 |

> 注：当前使用现有 Lottie 动画作为占位。待设计师提供专用动画后，只需更新 `theme.json` 中的 `motionStates` 映射即可替换。

---

## 3. 信息管理与智能检索 (Data & Recall)

### 3.1 自动分类与主题系统

* **智能标记：** 每条记录自动打标：`时间`、`来源应用`（窗口标题）、`AI 标签`、`AI 摘要`。
* **聚类逻辑：** 通过 OpenClaw LLM（`boji-notes` 专用会话）分析内容并返回 JSON `{"tags": [...], "summary": "..."}`。
* **手动管理：** 用户可在主窗口 Memory 标签页中搜索、按标签过滤、点击查看详情、长按删除。

### 3.2 对话式调取 (Conversation Recall) — ⏳ 延后

"记一记"不仅是为了存储，更是为了随时调用：
* **操作路径：** 用户 **双击** BoJi 打开对话框。
* **提问示例：**
    * *事实查询：* "我昨天记的那家火锅店叫什么名字？"
    * *主题汇总：* "把最近记的 #购物 相关的图片都给我看看。"
    * *模糊定位：* "帮我找找那个关于红色背包的记录。"
* **展示方式：** BoJi 在对话气泡中展示精简的记录卡片，点击可溯源至原始窗口或文件路径。

> **当前状态：** `boji-notes` 会话已在 server 端积累分析历史，具备基本上下文记忆。完整的对话式调取需要 server 端实现 `notes.search` tool 或系统 prompt 注入，延后实现。

---

## 4. 技术实施细节

### 4.1 拖拽接口 (Drag & Drop)

* **Windows:** ✅ 已实现 `IDropTarget` COM 接口（`drop_target.h` / `drop_target.cpp`），支持 `CF_HDROP`（文件）、`CF_UNICODETEXT`（文本）及 `CF_DIB`（位图）。
* **macOS:** 待实现。需支持 `NSDraggingDestination` 协议。

### 4.2 截屏

* **局部截图：** ✅ 通过 `Win32ScreenCapture.captureWindow(hwnd)` 仅截取当前伴随窗口。
* **异步处理：** ✅ 截图立即保存并返回 UI 成功状态，AI 分析在后台异步完成。

### 4.3 数据存储

* **本地文件系统：** ✅ 使用 `index.json` + `attachments/` + `thumbnails/` 目录结构。
* **存储路径：** `{getApplicationSupportDirectory()}/boji-notes/`
* **关联上下文：** ✅ 每条记录存储 `sourceApp`（窗口标题）和 `createdAt`（时间戳）。

> 注：PRD 原定使用 SQLite，实际采用轻量的 JSON 文件存储。当数据量增大后可考虑迁移到 SQLite。

---

**PM 总结：**
"记一记"功能将 BoJi 从一个"聊天工具"变成了用户的"外挂大脑"。通过**右键截屏**满足了全场景的信息捕获，通过**拖拽喂食**赋予了交互以极强的情感和趣味性。功能的闭环在于**对话调取**，它解决了"记了找不到"的行业通病。
