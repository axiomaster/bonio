# 波妞伴读 (Bonio Reading Companion) — 技术设计与实现文档

**对应 PRD:** `design/boji-desktop-伴读-2026年4月11日.md` (V6.0 Phase 1)
**实现日期:** 2026-04-11

---

## 1. 整体路线图

PRD V6.0 包含三大功能，按优先级分期交付：

| 阶段 | 功能 | 核心技术 | 状态 |
|------|------|----------|------|
| Phase 1 | 伴读 (Reading) | WebView 内容提取 + Markdown 编辑器 + Memory | 已实现 |
| Phase 2 | 会议转录 (Minutes) | WASAPI Loopback + sherpa_onnx ASR | 待开发 |
| Phase 3 | 双语字幕 (Captions) | 实时翻译 overlay | 待开发 |

---

## 2. 伴读功能架构

### 2.1 数据流

```
用户右键 avatar → "伴读"
    ↓
avatar_window_app.dart: _handleStartReading()
    → 提取浏览器 URL (Win32ScreenCapture.getBrowserUrl)
    → avatarMenuActionWithData('start_reading', {hwnd, url})
    ↓
app_state.dart: _handleStartReading()
    → Win32 SetWindowPos: 浏览器窗口 → 屏幕 70%
    → runtime.createReadingWindow(url, x, y, w, h)
    ↓
main.dart: windowType == 'reading_companion'
    → ReadingCompanionApp(url, mainWindowId)
    ↓
reading_companion_screen.dart:
    1. WebView1 加载 URL → JS 提取标题/正文
    2. 生成结构化 Markdown（目录 + 摘要 + 笔记区）
    3. WebView2 加载 Vditor 编辑器 → 显示 Markdown
    ↓
用户点击"入库"
    → WindowController.invokeMethod('readingSave', {url, markdown})
    ↓
app_state.dart: _handleReadingSave()
    → noteService.saveReadingNote(url, markdown)
    → 存入 Memory，tags: ['伴读']
```

### 2.2 窗口布局

```
┌─── 屏幕 ──────────────────────────────────┐
│                                            │
│  ┌──── 浏览器 (70%) ───┐ ┌─ 伴读 (30%) ─┐ │
│  │                     │ │  [AppBar]     │ │
│  │   原文网页           │ │  [TOC 目录]   │ │
│  │                     │ │  ─────────    │ │
│  │   anchor scroll ←───│─│─ heading tap  │ │
│  │                     │ │              │ │
│  │                     │ │  [Vditor]    │ │
│  │                     │ │  Markdown    │ │
│  │                     │ │  编辑器      │ │
│  │                     │ │              │ │
│  └─────────────────────┘ └──────────────┘ │
└────────────────────────────────────────────┘
```

---

## 3. 关键技术决策

### 3.1 内容提取方式

**选定方案：** WebView 加载 URL + JS 注入提取

在伴读窗口内使用 `webview_windows` (WebView2) 加载目标 URL，页面加载完成后通过 `executeScript` 注入 JS 提取：

```javascript
(() => {
  const headings = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].map(h => ({
    level: parseInt(h.tagName[1]),
    text: h.innerText.trim(),
    id: h.id || (h.closest('[id]') ? h.closest('[id]').id : '')
  })).filter(h => h.text.length > 0);

  const article = document.querySelector('article') ||
                  document.querySelector('[role="main"]') ||
                  document.querySelector('main') ||
                  document.querySelector('.post-content') ||
                  document.body;
  const text = article ? article.innerText.substring(0, 50000) : '';
  const title = document.title || '';
  return JSON.stringify({ headings, text, title });
})()
```

优先从 `<article>` / `<main>` / `[role="main"]` 等语义化标签提取正文，避免提取导航栏、侧边栏等噪音内容。

### 3.2 Markdown 编辑器

**选定方案：** Vditor (CDN) 嵌入 WebView

- **Vditor** (`https://cdn.jsdelivr.net/npm/vditor/dist/`) — 成熟的中文友好 Markdown 编辑器
- 使用 IR (Instant Rendering) 模式，所见即所得
- 本地 HTML 文件 (`assets/reading/editor.html`) 通过 WebView2 加载
- Dart ↔ JS 交互：
  - `setContent(md)` — Dart 向编辑器注入内容
  - `getContent()` — Dart 读取编辑器内容

### 3.3 TOC 导航 → 浏览器滚动

**选定方案：** `url_launcher` + anchor fragment

点击目录标题时，通过 `launchUrl(Uri.parse('$originalUrl#${heading.id}'))` 在系统浏览器中打开带锚点的 URL，浏览器会自动滚动到对应位置。

这利用了浏览器原生的 anchor 定位能力，无需跨进程窗口控制。

### 3.4 分屏 (70/30)

通过 Win32 FFI 实现：

- `MonitorFromWindow` + `GetMonitorInfoW` — 获取当前显示器工作区域（排除任务栏）
- `SetWindowPos` — 调整浏览器窗口到 70% 宽度
- `WindowController.create` — 在剩余 30% 创建伴读窗口

### 3.5 跨窗口通信 (Save)

伴读窗口是独立的 Flutter 引擎，无法直接访问主引擎的 NoteService。

保存流程通过 `desktop_multi_window` 的 `WindowController.invokeMethod` 实现：

```
伴读窗口 → invokeMethod('readingSave', {url, markdown}) → 主窗口
主窗口 → AppState._handleReadingSave() → NoteService.saveReadingNote()
```

---

## 4. 文件变更清单

### 新增文件

| 文件 | 说明 |
|------|------|
| `lib/ui/screens/reading_companion_screen.dart` | 伴读窗口主界面（内容提取 + TOC + Markdown 编辑器 + 保存） |
| `assets/reading/editor.html` | Vditor Markdown 编辑器 HTML 载体 |

### 修改文件

| 文件 | 变更内容 |
|------|----------|
| `lib/avatar_window_app.dart` | 右键菜单新增 "伴读" (ID=6)；`_handleStartReading()` 提取 URL 并发送到主窗口 |
| `lib/platform/win32_screen_capture.dart` | 新增 `resizeWindow()` (SetWindowPos)、`getMonitorWorkArea()` (MonitorFromWindow + GetMonitorInfoW) |
| `lib/providers/app_state.dart` | 新增 `_handleStartReading()` (分屏 + 创建窗口)、`_handleReadingSave()` (保存笔记)；注册 `readingSave` 方法通道 |
| `lib/services/node_runtime.dart` | 新增 `createReadingWindow()` (WindowController.create) |
| `lib/services/note_service.dart` | 新增 `saveReadingNote()`；`_matchesNoteSession` 扩展匹配 `boji-reading` |
| `lib/main.dart` | 新增 `reading_companion` 窗口类型路由 |
| `lib/l10n/app_strings.dart` | 新增 10 个伴读相关 i18n 字符串（中/英） |
| `pubspec.yaml` | 新增 `assets/reading/` 资源目录 |

---

## 5. 右键菜单 ID 映射（完整）

| ID | Action 字符串 | 功能 |
|----|--------------|------|
| 1 | `note_capture` | 记一记 |
| 2 | `show_main` | 显示主窗口 |
| 3 | `switch_window` | 切换窗口（禁用） |
| 4 | `ai_lens` | 圈一圈 |
| 5 | `search_similar` | 搜同款 |
| 6 | `start_reading` | 伴读 |

---

## 6. i18n 新增字符串

| Key | 中文 | English |
|-----|------|---------|
| `menuStartReading` | 伴读 | Reading |
| `readingTitle` | 伴读 | Reading Companion |
| `readingExtracting` | 正在提取内容... | Extracting content... |
| `readingAnalyzing` | 正在生成摘要... | Generating summary... |
| `readingSave` | 入库 | Save |
| `readingSaveSuccess` | 已存入记忆 | Saved to memory |
| `readingTocTitle` | 目录 | Table of Contents |
| `readingClose` | 关闭伴读 | Close |
| `readingNoBrowserUrl` | 未检测到浏览器URL | No browser URL detected |
| `readingEditorLoading` | 编辑器加载中... | Loading editor... |

---

## 7. Memory 集成

伴读笔记通过 `NoteService.saveReadingNote()` 存入 Memory 系统：

- `type`: `NoteType.text`
- `sourceApp`: `"伴读"`
- `sourceUrl`: 原文 URL
- `rawText`: 完整 Markdown 内容
- `tags`: `['伴读']`
- `analyzed`: `true`（无需二次 AI 分析）

在 Memory 页面中，用户可通过 `伴读` tag 筛选所有伴读笔记。

---

## 8. 后续迭代方向

1. **LLM 智能摘要**：当前版本使用本地文本提取生成模板；后续接入 gateway `chat.send` (sessionKey: `boji-reading`) 实现 AI 深度摘要
2. **智能感知触发**：检测活动窗口文本量，主动气泡提示是否开启伴读
3. **Avatar 状态**：增加 `READING` Lottie 动画（拿笔记录、翻书、戴眼镜）
4. **PDF 支持**：扩展内容提取支持 PDF 文件
5. **跨窗口滚动同步**：使用 Win32 SendMessage 实现更精确的浏览器滚动控制
