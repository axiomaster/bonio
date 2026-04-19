# BoJi Desktop 插件系统设计

> 本文档描述 BoJi Desktop 插件架构的设计与实现。代码位于 `desktop/lib/plugins/`。

---

## 1. 设计目标

将当前硬编码在右键菜单中的功能（记一记、圈一圈、搜同款、伴读）重构为插件架构，实现：

1. **独立编译**：每个插件是独立的可执行文件或包，有自己的代码仓库和构建流程
2. **独立发布**：插件可通过 Market 发布，独立于 BoJi 主应用版本
3. **独立加载**：运行时从 `~/.boji/plugins/` 动态发现和加载插件
4. **灵活扩展**：第三方开发者可以用任意语言（Dart、Python、Go、Node.js 等）开发插件

---

## 2. 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                       BoJi Desktop (Host)                       │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │ PluginManager│──▶│PluginRegistry│──▶│  PluginHost   │        │
│  │   (facade)   │   │ (state/disk) │   │ (per-process) │        │
│  └──────┬───────┘   └──────────────┘   └──────┬───────┘        │
│         │                                      │                │
│  ┌──────┴──────────────────────────────────────┤                │
│  │            Host Capability API              │ PluginBridge   │
│  │  (screen, window, browser, chat, avatar,    │ (JSON-RPC)     │
│  │   tts, notes, storage, ui)                  │                │
│  └─────────────────────────────────────────────┘                │
│                                                                 │
│  ┌────────────────────────────────────────────┐                 │
│  │        Built-in Plugins (BojiPlugin)        │                │
│  │  (in-process, direct Dart API access)       │                │
│  └────────────────────────────────────────────┘                 │
└────────────────────────────┬────────────────────────────────────┘
                             │ stdin/stdout JSON-RPC 2.0
                 ┌───────────┼───────────┐
                 │           │           │
            ┌────┴────┐ ┌────┴────┐ ┌────┴────┐
            │ Plugin  │ │ Plugin  │ │ Plugin  │
            │ Process │ │ Process │ │ Process │
            │ (Dart)  │ │(Python) │ │  (Go)   │
            └─────────┘ └─────────┘ └─────────┘
```

### 2.1 插件类型

| 类型 | 运行方式 | 适用场景 |
|------|----------|----------|
| **built-in** | Dart 代码在主进程内，实现 `BojiPlugin` 抽象类 | 核心功能（记一记、圈一圈等），不可卸载，可禁用 |
| **sidecar** | 独立进程，通过 stdin/stdout JSON-RPC 通信 | 第三方插件，完全隔离，支持任意语言 |

### 2.2 核心组件职责

| 组件 | 文件 | 职责 |
|------|------|------|
| `PluginManifest` | `plugin_manifest.dart` | 插件清单数据模型，JSON 解析，平台兼容性判断 |
| `BojiPlugin` | `plugin_interface.dart` | 内置插件抽象接口 + `PluginMenuContext` 上下文 |
| `PluginRegistry` | `plugin_registry.dart` | 已安装插件注册表：状态、排序、持久化到 `registry.json` |
| `PluginHost` | `plugin_host.dart` | 单个 sidecar 进程生命周期（启动、心跳、空闲回收、崩溃恢复） |
| `PluginBridge` | `plugin_bridge.dart` | 双向 JSON-RPC 2.0 over stdio 通信层 |
| `PluginManager` | `plugin_manager.dart` | 顶层门面：扫描、加载、激活、菜单生成、动作路由、安装/卸载 |

---

## 3. 数据模型

### 3.1 插件清单 `plugin.json`

每个插件目录下必须包含 `plugin.json`：

```json
{
  "id": "boji.reading-companion",
  "name": { "zh": "伴读", "en": "Reading Companion" },
  "version": "1.0.0",
  "description": { "zh": "浏览器网页内容提取与阅读笔记", "en": "..." },
  "author": "BoJi Team",
  "icon": "icon.png",
  "type": "sidecar",
  "entry": { "windows": "reading.exe", "macos": "reading" },
  "menu": {
    "label": { "zh": "伴读", "en": "Reading" },
    "icon": "auto_stories",
    "order": 40,
    "requires_context": ["browser_window"]
  },
  "capabilities_required": ["browser", "window_info", "chat"],
  "session_config": {
    "independent_session": true,
    "default_model": null,
    "system_prompt": "You are a reading assistant..."
  },
  "min_boji_version": "1.2.0",
  "platforms": ["windows", "macos"]
}
```

### 3.2 Dart 数据类映射

| JSON 字段 | Dart 类 | 说明 |
|-----------|---------|------|
| `id`, `name`, `version`, ... | `PluginManifest` | 主清单类，包含所有字段 |
| `name`, `description`, `menu.label` | `I18nString` | 国际化字符串 `{zh, en}`，`current` 取当前语言 |
| `type` | `PluginType` 枚举 | `builtin` / `sidecar` |
| `menu` | `PluginMenuConfig` | 菜单项配置 |
| `menu.requires_context` | `MenuContextRequirement` 枚举 | `none` / `anyWindow` / `browserWindow` |
| `session_config` | `PluginSessionConfig` | 独立 LLM 会话配置 |

关键方法：
- `PluginManifest.fromJson(json, {directoryPath})` — 解析 JSON
- `PluginManifest.loadFromDirectory(dirPath)` — 从目录读取 `plugin.json`
- `PluginManifest.executablePath` — 根据当前平台解析可执行文件绝对路径
- `PluginManifest.supportsPlatform` — 判断当前平台是否支持

### 3.3 菜单上下文 `PluginMenuContext`

触发插件菜单时传递的桌面环境信息：

```dart
class PluginMenuContext {
  final int hwnd;           // 当前锚定窗口句柄
  final String windowTitle; // 窗口标题
  final String windowClass; // 窗口类名
  final bool isBrowser;     // 是否浏览器窗口
  final double screenDpi;   // 显示器 DPI 缩放比
}
```

---

## 4. 内置插件接口 (`BojiPlugin`)

```dart
abstract class BojiPlugin {
  PluginManifest get manifest;
  Future<void> activate() async {}
  Future<void> onMenuAction(PluginMenuContext context);
  Future<void> deactivate() async {}
}
```

| 生命周期方法 | 调用时机 |
|-------------|---------|
| `activate()` | 插件首次启用或应用启动时（对启用的插件） |
| `onMenuAction(context)` | 用户点击右键菜单触发 |
| `deactivate()` | 插件被禁用或应用关闭时 |

内置插件通过 `PluginManager.registerBuiltin(plugin)` 注册。

---

## 5. 插件注册表 (`PluginRegistry`)

### 5.1 持久化格式 `registry.json`

存储在 `~/.boji/plugins/registry.json`：

```json
{
  "version": 1,
  "plugins": [
    {
      "id": "boji.note-capture",
      "enabled": true,
      "menuOrder": 10,
      "installedAt": "2026-04-01T12:00:00Z",
      "updatedAt": "2026-04-10T15:30:00Z"
    }
  ]
}
```

### 5.2 API

| 方法 | 说明 |
|------|------|
| `load()` | 从磁盘加载 `registry.json` + 扫描 `~/.boji/plugins/*/plugin.json` |
| `registerBuiltin(manifest)` | 注册内置插件（无磁盘目录） |
| `setEnabled(id, enabled)` | 启用/禁用插件，持久化 |
| `setMenuOrder(id, order)` | 更新菜单排序权重 |
| `reorder(orderedIds)` | 按列表顺序重排（每项间隔 10） |
| `install(manifest)` | 注册新安装的 sidecar 插件 |
| `unregister(id)` | 从注册表移除（不删除文件） |
| `enabledMenuPlugins` | 返回已启用 + 当前平台 + 有菜单配置的插件列表（按 menuOrder 排序） |

`PluginRegistry` 继承 `ChangeNotifier`，状态变化时通知监听者（UI 更新）。

---

## 6. Sidecar 进程管理 (`PluginHost`)

### 6.1 生命周期

```
           首次 menuAction
    Idle ──────────────────▶ Starting
                               │
                          Process.start(exe)
                               │
                          ┌────▼─────┐
                          │ 发送       │
                          │initialize │
                          │+ activate │
                          └────┬─────┘
                               │
                          ┌────▼─────┐
                  ┌──────▶│ Running  │◀──── menuAction（重置空闲计时器）
                  │       └────┬─────┘
                  │            │ 5 分钟无交互
                  │       ┌────▼──────┐
                  │       │ deactivate│
                  │       │ + shutdown│
                  │       └────┬──────┘
                  │            │ 等待 3 秒
                  │       ┌────▼──────┐
                  │       │  Stopped  │
                  │       └───────────┘
                  │
                  └── 进程异常退出 → 清理状态，下次触发自动重启
```

### 6.2 策略参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `_idleTimeout` | 5 分钟 | 无交互后自动关闭 |
| `_shutdownGrace` | 3 秒 | 优雅关闭等待时间，超时 `SIGKILL` |
| 请求超时 | 30 秒 | 每个 JSON-RPC 请求的超时 |
| `deactivate` 超时 | 2 秒 | 停止时 `deactivate` 调用的超时 |
| `shutdown` 超时 | 1 秒 | 停止时 `shutdown` 调用的超时 |

### 6.3 初始化参数

`PluginHost` 启动进程后发送 `initialize` 请求：

```json
{
  "hostVersion": "1.0.0",
  "capabilities": ["screen", "window", "browser", "chat", "avatar", "tts", "notes", "storage"],
  "pluginDataDir": "/path/to/plugin/data",
  "locale": "zh"
}
```

---

## 7. JSON-RPC 通信协议 (`PluginBridge`)

### 7.1 传输层

- 基于 **stdin/stdout**，每行一个 JSON 对象（类似 LSP 协议）
- 使用 **JSON-RPC 2.0** 格式（`jsonrpc`, `id`, `method`, `params`, `result`, `error`）
- 双向通信：Host 和 Plugin 都可以发起请求

### 7.2 消息分发逻辑

```dart
// PluginBridge 收到一行 JSON 后：
if (data 包含 id && id 在 _pending 中) {
    // 这是我们发出的请求的响应 → complete Completer
} else if (data 包含 method) {
    // 这是插件发来的能力调用请求 → 调用 onRequest handler → 回写 result
}
```

### 7.3 Host → Plugin 请求

| 方法 | 参数 | 说明 |
|------|------|------|
| `initialize` | `{hostVersion, capabilities, pluginDataDir, locale}` | 初始化握手 |
| `activate` | `{}` | 插件应准备就绪 |
| `menuAction` | `{hwnd, windowTitle, windowClass, isBrowser, screenDpi}` | 用户触发菜单项 |
| `deactivate` | `{}` | 插件应清理资源 |
| `shutdown` | `{}` | 进程应退出 |

### 7.4 Plugin → Host 能力调用

| 方法 | 参数 | 响应 |
|------|------|------|
| `screen.captureWindow` | `{hwnd}` | `{pngBase64, width, height}` |
| `window.getInfo` | `{hwnd}` | `{title, class, rect, isBrowser}` |
| `window.getForeground` | `{}` | `{hwnd}` |
| `window.resize` | `{hwnd, x, y, w, h}` | `{}` |
| `browser.ensureConnected` | `{}` | `{}` |
| `browser.getCurrentUrl` | `{}` | `{url}` |
| `browser.extractContent` | `{maxLength?}` | `{title, url, text, headings}` |
| `browser.executeScript` | `{js}` | `{result}` |
| `chat.send` | `{text, attachments?, sessionKey?}` | `{runId}` |
| `avatar.setBubble` | `{text, bgColor?, textColor?}` | `{}` |
| `avatar.showState` | `{state, temporary?}` | `{}` |
| `tts.speak` | `{text}` | `{}` |
| `tts.stop` | `{}` | `{}` |
| `storage.get` | `{key}` | `{value}` |
| `storage.set` | `{key, value}` | `{}` |
| `note.save` | `{text, tags?, type?}` | `{noteId}` |
| `ui.createWindow` | `{type, url?, title?, width?, height?, x?, y?}` | `{windowId}` |

### 7.5 Host → Plugin 事件通知

```jsonc
// 聊天流式响应（notification，无 id）
{"jsonrpc": "2.0", "method": "chat.streamDelta", "params": {"text": "...", "done": false}}

// 聊天完成
{"jsonrpc": "2.0", "method": "chat.complete", "params": {"text": "...", "sessionKey": "..."}}
```

### 7.6 错误处理

```dart
class PluginRpcError implements Exception {
  final int code;     // JSON-RPC 错误码（-32603 = 内部错误）
  final String message;
}
```

---

## 8. 顶层门面 (`PluginManager`)

### 8.1 初始化流程

```dart
// 在 NodeRuntime 构造函数中：
pluginManager = PluginManager();
pluginManager.addListener(pushPluginMenuToAvatar);
unawaited(pluginManager.initialize());
```

`initialize()` 执行：
1. 获取应用支持目录 → `~/.boji/plugins/`
2. 创建 `PluginRegistry` 并 `load()`（读 `registry.json` + 扫描目录）
3. 注册之前通过 `registerBuiltin()` 添加的内置插件
4. 设置 `_initialized = true` 并通知监听者

### 8.2 菜单系统

```dart
// 获取菜单项列表（带上下文过滤）
List<Map<String, dynamic>> getMenuItems({int hwnd, bool isBrowser});
// 返回: [{id: 1, label: "记一记", enabled: true}, ...]

// 获取菜单 ID → 插件 ID 映射
Map<int, String> getMenuActions({int hwnd, bool isBrowser});
// 返回: {1: "boji.note-capture", 2: "boji.ai-lens", ...}

// 执行菜单动作
Future<void> executeMenuAction(String pluginId, PluginMenuContext context);
// → 内置插件: 调用 builtin.onMenuAction(context)
// → Sidecar: 获取/创建 PluginHost → sendMenuAction(context.toJson())
```

### 8.3 安装/卸载

```dart
// 从 zip 安装 sidecar 插件
Future<void> installFromZip(String zipPath);
// 1. 解压 zip → 读取 plugin.json → 验证 id
// 2. 提取到 ~/.boji/plugins/{id}/
// 3. macOS/Linux: chmod +x 可执行文件
// 4. registry.install(manifest)

// 卸载
Future<void> uninstall(String pluginId);
// 1. 停止运行中的 PluginHost
// 2. 删除插件目录
// 3. registry.unregister(id)
```

---

## 9. 菜单动态化（IPC 流程）

### 9.1 数据流

```
PluginManager (main engine)
       │
       │ pluginManager.addListener(pushPluginMenuToAvatar)
       │
       ▼
NodeRuntime.pushPluginMenuToAvatar()
       │
       │ ctrl.invokeMethod('syncPluginMenu', enrichedItems)
       │
       ▼
Avatar Window (avatar engine)
       │
       │ 存储 _pluginMenuItems
       │
       ▼
_onShowNativeMenu()
       │
       │ 使用 _pluginMenuItems 构建菜单（若非空）
       │ 否则回退到硬编码菜单项
       │
       ▼
用户选择后
       │
       ├─ 内置动作 (ai_lens/note_capture/start_reading): 本地处理
       ├─ show_main: _sendMenuActionToMain
       └─ 插件动作: _sendPluginActionToMain(pluginId)
              │
              │ main.invokeMethod('pluginMenuAction', {pluginId, hwnd, isBrowser})
              │
              ▼
       AppState._handlePluginMenuAction()
              │
              │ 构建 PluginMenuContext (从 GuiAgent 获取 title/class/dpi)
              │
              ▼
       pluginManager.executeMenuAction(pluginId, context)
```

### 9.2 当前菜单状态

当前实现为**渐进式改造**：
- `_pluginMenuItems` 非空时，使用动态插件菜单
- 为空时（插件系统未初始化或无已注册插件），回退到硬编码菜单项
- 这确保了向后兼容性，Phase 2 迁移内置插件后可移除回退逻辑

---

## 10. 存储布局

```
~/.boji/plugins/
├── registry.json                  # 已安装插件列表、启用状态、菜单排序
├── boji.note-capture/
│   ├── plugin.json                # 清单
│   └── data/                      # 插件本地数据 (storage.get/set)
├── boji.ai-lens/
│   ├── plugin.json
│   └── data/
├── boji.search-similar/
│   ├── plugin.json
│   ├── search.exe                 # sidecar 可执行文件
│   └── data/
├── boji.reading-companion/
│   ├── plugin.json
│   ├── reading.exe
│   ├── assets/
│   │   └── editor.html            # 插件自带资源
│   └── data/
└── third-party.my-plugin/
    ├── plugin.json
    ├── my_plugin.exe
    ├── icon.png
    └── data/
```

---

## 11. UI 集成

### 11.1 导航

主导航栏（`main_screen.dart`）新增 **插件** 目的地（位于 Market 和 Settings 之间），对应 `PluginTab`。

### 11.2 插件管理页面 (`PluginTab`)

- **已安装列表**：按 `menuOrder` 排序的卡片列表
- **启用/禁用开关**：`Switch` 控件，变更后同步到 avatar 菜单
- **拖拽排序**：`ReorderableListView`，拖拽后调用 `registry.reorder()` + 同步 avatar
- **卸载**：仅 sidecar 插件显示删除按钮，确认对话框后调用 `pluginManager.uninstall()`
- **内置标签**：built-in 插件显示 "内置" Chip 标记
- **刷新**：工具栏刷新按钮调用 `pluginManager.reload()`

### 11.3 市场插件页签 (`_PluginMarketContent`)

在现有 `MarketplaceTab`（Skills / Models / Themes）的第一个页签位置新增 **Plugins** 页签：

- 数据源：`https://axiomaster.github.io/boji-market/plugins.json`
- 列表展示：名称、版本、描述、作者
- 安装按钮：下载 zip → `pluginManager.installFromZip()`
- 已安装状态标记

### 11.4 国际化

`app_strings.dart` 新增 13 条插件相关字符串（中/英双语）：

| Key | 中文 | English |
|-----|------|---------|
| `pluginManageTitle` | 插件管理 | Plugin Manager |
| `pluginEmptyHint` | 暂无已安装的插件 | No plugins installed |
| `pluginBuiltinLabel` | 内置 | Built-in |
| `pluginInstall` | 安装 | Install |
| `pluginInstalled` | 已安装 | Installed |
| `pluginRemove` | 卸载 | Uninstall |
| `marketPlugins` | 插件 | Plugins |
| ... | ... | ... |

---

## 12. Market 插件目录格式

### plugins.json

```json
{
  "plugins": [
    {
      "id": "third-party.cool-tool",
      "name": { "zh": "酷工具", "en": "Cool Tool" },
      "version": "1.0.0",
      "description": { "zh": "...", "en": "..." },
      "author": "Developer Name",
      "icon_url": "https://.../icon.png",
      "download_url": {
        "windows": "https://.../cool-tool-windows.zip",
        "macos": "https://.../cool-tool-macos.zip"
      },
      "min_boji_version": "1.2.0",
      "platforms": ["windows", "macos"],
      "downloads": 1234,
      "rating": 4.5
    }
  ]
}
```

### zip 包格式

```
cool-tool-windows.zip
├── plugin.json          # 必须
├── cool_tool.exe        # sidecar 可执行文件
├── icon.png             # 可选图标
└── assets/              # 可选资源目录
```

---

## 13. 安全考虑

- 插件进程运行在用户权限下，无额外沙箱
- 宿主能力调用可按 `capabilities_required` 白名单限制
- 插件来源验证：Market 发布需审核；本地安装显示安全提示
- 插件本地存储隔离在各自 `data/` 目录中
- 崩溃的插件不影响宿主进程稳定性（`PluginHost` 监控 `exitCode`，自动清理）

---

## 14. 实现文件清单

### 新增文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `desktop/lib/plugins/plugin_manifest.dart` | 229 | `PluginManifest`, `I18nString`, `PluginMenuConfig`, `PluginSessionConfig` |
| `desktop/lib/plugins/plugin_interface.dart` | 58 | `BojiPlugin` 抽象类, `PluginMenuContext` |
| `desktop/lib/plugins/plugin_registry.dart` | 213 | `PluginRegistry`, `PluginRegistryEntry` |
| `desktop/lib/plugins/plugin_host.dart` | 153 | `PluginHost` sidecar 进程管理 |
| `desktop/lib/plugins/plugin_bridge.dart` | 161 | `PluginBridge` JSON-RPC 通信, `PluginRpcError` |
| `desktop/lib/plugins/plugin_manager.dart` | 281 | `PluginManager` 门面 |
| `desktop/lib/ui/screens/plugin_tab.dart` | 228 | 插件管理 UI |

### 修改文件

| 文件 | 变更 |
|------|------|
| `desktop/lib/services/node_runtime.dart` | 新增 `pluginManager` 字段、初始化/销毁、`pushPluginMenuToAvatar()` |
| `desktop/lib/providers/app_state.dart` | 新增 `pluginMenuAction` IPC 处理、`_handlePluginMenuAction()` |
| `desktop/lib/avatar_window_app.dart` | 新增 `_pluginMenuItems` + `syncPluginMenu` IPC、`_sendPluginActionToMain()`、渐进式动态菜单 |
| `desktop/lib/ui/screens/main_screen.dart` | 新增 "插件" 导航目的地 + `PluginTab` |
| `desktop/lib/ui/screens/marketplace_tab.dart` | 新增 "Plugins" 页签 + `_PluginMarketContent` |
| `desktop/lib/l10n/app_strings.dart` | 新增 13 条插件相关国际化字符串 |

---

## 15. 实施路线

### Phase 1：插件基础设施 ✅ (已完成)
- 设计文档
- `PluginManifest` 数据模型 + JSON 解析
- `PluginRegistry` 本地持久化
- `PluginHost` 进程生命周期
- `PluginBridge` JSON-RPC 通信
- `PluginManager` 门面
- 动态菜单生成 + IPC 同步
- 插件管理 UI + 市场 Plugins 页签

### Phase 2：内置插件迁移
- 将 记一记 重构为 `BuiltinNoteCapturePlugin`
- 将 圈一圈 重构为 `BuiltinAiLensPlugin`
- 将 搜同款 重构为 `BuiltinSearchSimilarPlugin`
- 将 伴读 重构为 `BuiltinReadingPlugin`
- 移除 `avatar_window_app.dart` 中的硬编码菜单回退逻辑

### Phase 3：插件 SDK
- Dart 插件 SDK 包 (`boji_plugin_sdk`)
- Python 插件 SDK
- 脚手架/模板生成 CLI
- 开发者文档
