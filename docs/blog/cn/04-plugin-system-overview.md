# 插件系统：Bonio 的无限扩展能力

> 右键菜单是 Bonio 的智能工具箱入口。而驱动这个工具箱的，是一套支持任意语言、独立编译、独立分发的插件系统。

---

## 从硬编码到动态插件

Bonio 的第一版右键菜单只有三个写死的功能。每加一个新功能就要改 Avatar 窗口的代码，改完 Dart 还要重新编译 Flutter。随着能力增多，这显然不可持续。

于是有了**插件系统**。现在，右键菜单的所有项目都由插件动态生成。插件可以被安装、启用、禁用、卸载，而**不需要重启 Bonio**。

```
右键菜单结构：
┌─────────────────────┐
│ 记一记              │ ← boji.note-capture (built-in 插件)
│ 圈一圈 (AI Lens)    │ ← boji.ai-lens (built-in 插件)
│ 搜同款              │ ← boji.search-similar (built-in 插件)
│ 伴读                │ ← boji.reading-companion (built-in 插件)
│─────────────────────│
│ 第三方插件A          │ ← third-party.xxx (sidecar 插件)
│ 第三方插件B          │ ← third-party.yyy (sidecar 插件)
│─────────────────────│
│ Bonio 桌面          │ → 打开主窗口
│ 更换伴随窗口         │ → 切换锚定窗口
│ 休息一下             │ → 隐藏 Avatar
└─────────────────────┘
```

---

## 两种插件类型

| | **Built-in（内置）** | **Sidecar（独立进程）** |
|---|---|---|
| **运行方式** | Dart 代码在主进程内，实现 `BojiPlugin` 抽象类 | 独立可执行文件，通过 stdin/stdout JSON-RPC 通信 |
| **开发语言** | Dart（必须） | **任意语言**（Dart、Python、Go、Node.js、Rust……） |
| **能力访问** | 直接调用宿主 API | 通过 JSON-RPC 调用宿主能力 |
| **可卸载** | 否（可禁用） | 是 |
| **适用场景** | 核心功能（记一记、圈一圈等） | 第三方插件、实验性功能 |
| **进程隔离** | 无（共享主进程） | 完全隔离，崩溃不影响宿主 |

### 为什么需要 Sidecar？

Sidecar 模式的核心价值是**语言自由和崩溃隔离**。一个用 Python 写的插件如果因为依赖问题挂了，Bonio 主进程**完全不受影响**。`PluginHost` 会检测进程退出，自动清理，下次触发时重新启动。

这种设计借鉴了 LSP（Language Server Protocol）的思路——宿主和插件通过标准的 JSON-RPC 2.0 协议通信，每行一个 JSON 对象，通过 stdin/stdout 传输。任何能读写标准输入输出的程序都可以成为 Bonio 插件。

---

## 插件清单：plugin.json

每个插件目录下必须包含一个 `plugin.json`：

```json
{
  "id": "boji.reading-companion",
  "name": { "zh": "伴读", "en": "Reading Companion" },
  "version": "1.0.0",
  "description": { "zh": "浏览器网页内容提取与阅读笔记", "en": "..." },
  "author": "Bonio Team",
  "type": "sidecar",
  "entry": { "windows": "reading.exe", "macos": "reading" },
  "menu": {
    "label": { "zh": "伴读", "en": "Reading" },
    "icon": "auto_stories",
    "order": 40,
    "requires_context": ["browser_window"]
  },
  "capabilities_required": ["browser", "window_info", "chat"],
  "min_bonio_version": "1.2.0",
  "platforms": ["windows", "macos"]
}
```

关键字段解读：

- **`type`**：`builtin` 或 `sidecar`
- **`entry`**：sidecar 的可执行文件路径，按平台区分
- **`menu.requires_context`**：菜单显示条件。`browser_window` 表示仅当锚定窗口是浏览器时才显示此菜单项。`anyWindow` 表示只要有锚定窗口就显示。这是关键的用户体验设计——你不会在文件管理器上看到"伴读"选项
- **`capabilities_required`**：声明需要哪些宿主能力，宿主据此决定是否授权
- **`min_bonio_version`**：防止旧版 Bonio 加载不兼容的插件

---

## JSON-RPC 通信协议

Sidecar 插件启动后，宿主通过 stdin 发送初始化握手：

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "hostVersion": "1.2.0",
    "capabilities": ["screen", "window", "browser", "chat", "avatar", "tts", "notes"],
    "pluginDataDir": "/path/to/plugin/data",
    "locale": "zh"
  }
}
```

用户在右键菜单点击插件后，宿主发送 `menuAction` 请求，附带完整的桌面上下文：

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "menuAction",
  "params": {
    "hwnd": 123456,
    "windowTitle": "GitHub - axiomaster/bonio",
    "windowClass": "Chrome_WidgetWin_1",
    "isBrowser": true,
    "screenDpi": 1.5
  }
}
```

插件在处理过程中可以**反过来调用宿主的能力**：

```json
// 插件 → 宿主：截图当前窗口
{"jsonrpc": "2.0", "id": 10, "method": "screen.captureWindow", "params": {"hwnd": 123456}}

// 宿主 → 插件：返回 PNG base64
{"jsonrpc": "2.0", "id": 10, "result": {"pngBase64": "iVBOR...", "width": 1920, "height": 1080}}

// 插件 → 宿主：发送聊天消息给 AI
{"jsonrpc": "2.0", "id": 11, "method": "chat.send", "params": {"text": "分析这张图", "attachments": [...]}}
```

宿主提供的能力清单（18 个 API）：

| 类别 | 方法 | 说明 |
|------|------|------|
| **屏幕** | `screen.captureWindow` | 截取指定窗口，返回 PNG base64 |
| **窗口** | `window.getInfo` | 获取窗口标题、类名、矩形区域 |
| **窗口** | `window.getForeground` | 获取当前前台窗口句柄 |
| **窗口** | `window.resize` | 调整窗口位置和大小 |
| **浏览器** | `browser.ensureConnected` | 自动发现并连接 Chrome/Edge CDP |
| **浏览器** | `browser.getCurrentUrl` | 获取当前页面 URL |
| **浏览器** | `browser.extractContent` | 提取页面正文、标题、目录结构 |
| **浏览器** | `browser.executeScript` | 在页面中执行任意 JavaScript |
| **聊天** | `chat.send` | 发送消息给 AI（支持附件） |
| **Avatar** | `avatar.setBubble` | 显示气泡文字 |
| **Avatar** | `avatar.showState` | 切换动画状态 |
| **TTS** | `tts.speak` / `tts.stop` | 语音合成 |
| **存储** | `storage.get` / `storage.set` | 插件私有键值存储 |
| **笔记** | `note.save` | 存入记忆系统 |
| **UI** | `ui.createWindow` | 创建新的宿主窗口 |

---

## Sidecar 进程生命周期

```
          首次 menuAction 触发
  Idle ──────────────────────▶ Starting
                                 │
                           Process.start(exe)
                                 │
                          ┌──────▼──────┐
                          │ 发送         │
                          │ initialize   │
                          │ + activate   │
                          └──────┬──────┘
                                 │
                          ┌──────▼──────┐
                 ┌───────▶│   Running   │◀─── menuAction（重置空闲计时器）
                 │        └──────┬──────┘
                 │               │ 5 分钟无交互
                 │        ┌──────▼──────┐
                 │        │ deactivate   │
                 │        │ + shutdown   │
                 │        └──────┬──────┘
                 │               │
                 │        ┌──────▼──────┐
                 │        │   Stopped   │
                 │        └─────────────┘
                 │
                 └─── 进程异常退出 → 清理状态，下次触发自动重启
```

关键设计：
- **空闲回收**：5 分钟无交互后自动关闭 sidecar 进程，释放内存
- **崩溃恢复**：进程异常退出被 `PluginHost` 捕获，下次触发时自动重启，对用户透明
- **请求超时**：每个 JSON-RPC 请求 30 秒超时，防止插件卡死阻塞宿主

---

## 如何开发一个 Sidecar 插件

以 Python 为例，开发一个"文本翻译"右键插件只需几十行代码：

```python
import sys
import json

def rpc_request(method, params):
    """发送 JSON-RPC 请求到宿主，等待响应"""
    msg = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()
    return json.loads(sys.stdin.readline())

# 1. 等待宿主发送 initialize
init = json.loads(sys.stdin.readline())
print(f"Plugin initialized, host version: {init['params']['hostVersion']}", file=sys.stderr)

# 2. 循环等待 menuAction
while True:
    req = json.loads(sys.stdin.readline())
    if req.get("method") == "menuAction":
        hwnd = req["params"]["hwnd"]

        # 3. 调用宿主能力：截图窗口
        cap = rpc_request("screen.captureWindow", {"hwnd": hwnd})
        image_b64 = cap["result"]["pngBase64"]

        # 4. 调用宿主能力：发给 AI 翻译
        rpc_request("chat.send", {
            "text": "请将图片中的文字翻译成中文",
            "attachments": [{"type": "image", "data": image_b64}]
        })

        # 5. 更新 Avatar 气泡
        rpc_request("avatar.setBubble", {"text": "翻译中..."})
```

打包这个脚本为 `translator.exe`（用 PyInstaller），配上 `plugin.json`，放入 `~/.bonio/plugins/translator/`，右键菜单就会出现"翻译"。

同样的模式可以用 Go、Node.js、Rust 实现——只要它能读写 stdin/stdout。

---

## 插件注册与市场

插件注册表存储在 `~/.bonio/plugins/registry.json`：

```json
{
  "version": 1,
  "plugins": [
    {"id": "boji.note-capture", "enabled": true, "menuOrder": 10},
    {"id": "boji.ai-lens", "enabled": true, "menuOrder": 20},
    {"id": "third-party.translator", "enabled": true, "menuOrder": 50}
  ]
}
```

`PluginRegistry` 负责：
- 从 `registry.json` 加载已安装插件
- 扫描 `~/.bonio/plugins/*/plugin.json` 发现新插件
- 管理启用/禁用状态
- 管理菜单排序权重

Bonio 的 Market 页面可以浏览和安装社区插件。`plugins.json` 索引文件托管在 GitHub Pages，列出所有可用插件。用户点击"安装"，Bonio 自动下载 zip、解压、验证、注册。

---

## 设计哲学

Bonio 的插件系统有几个刻意的设计选择：

1. **不做沙箱。** Sidecar 插件运行在用户权限下，可以访问用户能访问的任何东西。这不是懒——而是因为一个截图插件如果需要沙箱，它就无法截屏。安全的责任在于用户选择可信的插件，Market 审核辅助把关。

2. **不依赖 IPC 框架。** stdin/stdout JSON-RPC 是最古老的 IPC 协议。它没有任何库依赖，不需要 protobuf 编译，不需要 gRPC 运行时。Python 的 `print()` 和 `input()` 就能写插件。

3. **菜单上下文过滤。** `requires_context: ["browser_window"]` 这种声明式的菜单过滤，让用户不会在错误的场景下看到无意义的菜单项。插件开发者声明前置条件，宿主负责判断。

---

*下一篇：[记一记：碎片化信息的一键收集](05-note-capture.md)*
