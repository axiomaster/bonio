# HiClaw Agent 能力增强 — 架构设计

**版本**: 1.0
**日期**: 2025-05-20
**作者**: Architect (hiclaw-capability team)
**来源**: 基于 `docs/design/prd/20260520-hiclaw-agent-capability-prd.md`

---

## 1. 设计目标与约束

### 1.1 目标

为 HiClaw Agent 补齐 P0 核心能力，使其能够：
1. 完成截屏分析任务（`screen.capture` + `image` 工具）
2. 获取实时信息（`web_search` 工具）
3. 可靠执行长时间命令（`shell` 增强和 `process` 工具）

### 1.2 约束条件

- **兼容现有架构**: 必须符合当前的工具注册、路由和执行框架
- **最小改动原则**: 复用现有代码（Desktop 端截屏、cron 系统等）
- **跨平台支持**: Server 端代码需在 Windows/Linux/macOS 上编译
- **协议兼容**: 遵循现有 WebSocket 协议（v3）和工具定义格式

---

## 2. 整体架构

### 2.1 组件图

```
┌──────────────────────────────────────────────────────────────────────┐
│                         HiClaw Server (C++)                          │
│                                                                      │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐       │
│  │   Agent      │─────▶│  ToolRouter  │─────▶│  LocalTools  │       │
│  │   (agent.cpp)│      │              │      │  - shell     │       │
│  │              │      │              │      │  - web_search│       │
│  │  - Tool Loop │      │ - Future/P   │      │  - file_*    │       │
│  │  - Tool Defs │      │ - Register   │      │  - image     │       │
│  └──────────────┘      └──────────────┘      └──────────────┘       │
│         │                                             │              │
│         │                             Remote Tools   │              │
│         ▼                             (screen.*)     │              │
│  ┌──────────────┐                             ┌──────────────┐     │
│  │ ToolRegistry │────────────────────────────▶│ RemoteExec   │     │
│  │ - Register   │     node.invoke.request      │              │     │
│  │ - is_remote  │─────────────────────────────▶│ (async_agent)│     │
│  └──────────────┘                             └──────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
                           │
                           │ WebSocket (v3)
                           │ node.invoke.request / node.invoke.result
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Desktop Client (Flutter/Dart)                      │
│                                                                      │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐       │
│  │ NodeRuntime  │─────▶│InvokeDisp.   │─────▶│ Handlers     │       │
│  │              │      │              │      │ - ScreenCap. │       │
│  │ - onInvoke   │      │ - Route      │      │ - Camera     │       │
│  └──────────────┘      └──────────────┘      └──────────────┘       │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.2 工具调用数据流

**本地工具（如 `web_search`, `image`, `shell`）**:
1. Agent 收到 LLM 返回的 `tool_call`
2. 检查 `tools::is_remote_tool(tool_name)` → false
3. 直接调用 `tools::run_tool(name, args)` 执行
4. 结果通过 `tool` 消息返回给 LLM

**远程工具（如 `screen.capture`）**:
1. Agent 收到 LLM 返回的 `tool_call`
2. 检查 `tools::is_remote_tool(tool_name)` → true
3. 调用 `remote_executor(tool_call_id, name, args)`
4. 通过 Gateway 发送 `node.invoke.request` 到客户端
5. 客户端 `_onNodeInvoke()` 路由到对应 Handler
6. Handler 执行并返回 `InvokeResult`
7. 客户端发送 `node.invoke.result` 回服务器
8. `ToolRouter::complete_tool_call()` 设置 Future 结果
9. 结果通过 `tool` 消息返回给 LLM

---

## 3. 工具调用框架

### 3.1 工具定义格式（JSON Schema for LLM）

当前实现在 `agent.cpp` 中硬编码工具定义：

```cpp
// 示例：shell 工具定义
tools.push_back(json::parse(R"({
  "type":"function",
  "function":{
    "name":"shell",
    "description":"Run a shell command",
    "parameters":{
      "type":"object",
      "properties":{
        "command":{"type":"string"}
      },
      "required":["command"]
    }
  }
})"));
```

**扩展建议**：
- 工具定义结构体化（`struct ToolDefinition`）
- 工具参数 schema 支持更丰富类型（integer, boolean, array）
- 工具元数据（category, version, deprecated）

### 3.2 工具注册机制

当前实现 (`tool.cpp`):

```cpp
void register_tool(const std::string& name, ToolExecutor exec);
ToolResult run_tool(const std::string& name, const std::string& args_json);
bool is_remote_tool(const std::string& name);
```

**远程工具判断逻辑** (`tool.cpp:192-205`):
```cpp
bool is_remote_tool(const std::string& name) {
  static const char* remote_prefixes[] = {
    "screen.", "camera.", "location.", "device.", "notifications.",
    "system.", "sms.", "photos.", "contacts.", "calendar.", "motion.",
    "canvas.", "telephony.", "input.",
    nullptr
  };
  // 检查前缀匹配
}
```

### 3.3 工具路由逻辑

在 `async_agent.cpp:811-830` 中：

```cpp
for (const auto& tc : tool_calls) {
  if (aborted && aborted->load()) break;
  types::ToolResult tr;
  if (tools::is_remote_tool(tc.name) && remote_executor) {
    // 发送 node.invoke.request 到客户端
    tr = remote_executor(tc.id, tc.name, tc.arguments);
  } else {
    // 本地执行
    tr = tools::run_tool(tc.name, tc.arguments);
  }
  // 结果加入 messages_json
}
```

---

## 4. 各工具详细设计

### 4.1 screen.capture

#### 4.1.1 当前状态

- **Server 端**: 已在 `agent.cpp:108` 定义远程工具
- **Desktop 端**: 已有 `Win32ScreenCapture.captureScreen()` 实现
- **Gap**: Desktop 的 `_onNodeInvoke()` 未处理 `screen.capture` 命令

#### 4.1.2 设计方案

**Server 端**: 无需改动，工具定义已存在

**Desktop 端修改** (`desktop/lib/services/node_runtime.dart`):

在 `_onNodeInvoke()` 的 switch 语句中添加 case:

```dart
case 'screen.capture':
  return await _handleScreenCapture();
```

新增 Handler 方法:

```dart
Future<InvokeResult> _handleScreenCapture() async {
  if (!Platform.isWindows) {
    return InvokeResult.fail('UNSUPPORTED_PLATFORM',
        'Screen capture is only supported on Windows');
  }
  try {
    final result = await Win32ScreenCapture.captureScreen();
    if (result == null) {
      return InvokeResult.fail('CAPTURE_FAILED', 'Failed to capture screen');
    }
    // 转换为 base64 PNG
    final pngBytes = encodePng(result); // 需要实现 PNG 编码
    final base64 = base64Encode(pngBytes);
    return InvokeResult.success(jsonEncode({
      'success': true,
      'image': 'data:image/png;base64,$base64',
      'width': result.width,
      'height': result.height,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }));
  } catch (e) {
    return InvokeResult.fail('CAPTURE_FAILED', 'Error: $e');
  }
}
```

**PNG 编码实现**:
- 使用 `dart:ui` 的 `Image.toByteData()` 或第三方库 `image` 包
- 建议使用 `image` 包: `final png = encodePng(img);`

#### 4.1.3 返回值格式

```json
{
  "success": true,
  "image": "data:image/png;base64,iVBORw0KGgo...",
  "width": 1920,
  "height": 1080,
  "timestamp": 1716192000000
}
```

#### 4.1.4 与 `image` 工具配合

典型工作流：
1. Agent 调用 `screen.capture` → 返回 `data:image/png;base64,...`
2. Agent 调用 `image(prompt="...", image="data:image/png;base64,...")` → 分析结果

---

### 4.2 web_search

#### 4.2.1 工具定义

**位置**: `server/src/tools/tool.cpp`

**参数 Schema**:
```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "搜索查询"
    },
    "count": {
      "type": "integer",
      "description": "返回结果数量，默认 10，最大 50",
      "minimum": 1,
      "maximum": 50
    },
    "language": {
      "type": "string",
      "description": "语言代码，如 zh-CN, en-US"
    }
  },
  "required": ["query"]
}
```

#### 4.2.2 搜索提供商选择

**Phase 1 (P0)**: **Brave Search API**
- 免费额度: 2000 次/月
- API 文档: `https://api.search.brave.com/app/keys`
- Endpoint: `https://api.search.brave.com/res/v1/web/search`
- 优点: 无需广告联盟，隐私友好，响应快

**备选**: DuckDuckGo (无 API key，但质量不稳定)

#### 4.2.3 实现方案

**新增文件**: `server/src/tools/web_search_tool.cpp` / `.hpp`

**核心实现**:
```cpp
ToolResult web_search_impl(const std::string& args_json) {
  std::string query = get_arg(args_json, "query");
  int count = get_arg_int(args_json, "count", 10);
  std::string language = get_arg(args_json, "language");

  if (query.empty()) {
    return ToolResult{false, "", "missing 'query' argument"};
  }

  // 从配置读取 API key
  std::string api_key = config::get_web_search_api_key();
  if (api_key.empty()) {
    return ToolResult{false, "", "web_search API key not configured"};
  }

  // 构造 HTTP 请求
  std::string url = "https://api.search.brave.com/res/v1/web/search"
                    "?q=" + url_encode(query) +
                    "&count=" + std::to_string(count);
  if (!language.empty()) {
    url += "&search_lang=" + language;
  }

  net::HttpRequest req;
  req.method = "GET";
  req.url = url;
  req.headers["Accept"] = "application/json";
  req.headers["X-Subscription-Token"] = api_key;

  net::HttpResponse res;
  if (!net::http_request(req, res)) {
    return ToolResult{false, "", res.error};
  }

  // 解析响应
  try {
    nlohmann::json j = nlohmann::json::parse(res.body);

    // 提取搜索结果
    nlohmann::json results = j["web"]["results"];
    std::ostringstream out;
    out << "Found " << results.size() << " results:\n";
    for (const auto& item : results) {
      out << "- " << item["title"].get<std::string>() << "\n";
      out << "  " << item["url"].get<std::string>() << "\n";
      if (item.contains("description")) {
        out << "  " << item["description"].get<std::string>() << "\n";
      }
      out << "\n";
    }
    return ToolResult{true, out.str(), ""};
  } catch (const std::exception& e) {
    return ToolResult{false, "", "failed to parse search results: " + std::string(e.what())};
  }
}
```

**注册工具** (`register_builtin_tools()`):
```cpp
register_tool("web_search", web_search_impl);
```

#### 4.2.4 配置存储

**hiclaw.json 扩展**:
```json
{
  "web_search": {
    "provider": "brave",
    "api_key": "BSX123...",  // Brave Search API key
    "api_key_env": "BRAVE_SEARCH_API_KEY"  // 优先从环境变量读取
  }
}
```

**Config 解析** (`server/src/config/config.cpp`):
```cpp
struct WebSearchConfig {
  std::string provider = "brave";
  std::string api_key;
  std::string api_key_env;
};
```

---

### 4.3 shell 增强

#### 4.3.1 当前实现

**位置**: `server/src/tools/tool.cpp:98-136`

**当前问题**:
- 仅支持同步执行（阻塞）
- 无超时控制（可能永久挂起）
- 无后台执行能力
- 无进程管理

#### 4.3.2 增强方案

**扩展参数** (Phase 1):
```json
{
  "type": "object",
  "properties": {
    "command": {"type": "string"},
    "timeoutMs": {
      "type": "integer",
      "description": "超时时间（毫秒），默认 30000，0 表示无限等待",
      "minimum": 0
    },
    "background": {
      "type": "boolean",
      "description": "是否后台执行，默认 false"
    },
    "workingDir": {
      "type": "string",
      "description": "工作目录"
    }
  },
  "required": ["command"]
}
```

**实现要点**:

1. **超时控制** (`server/src/tools/shell_tool.cpp`):
   - Windows: `WaitForSingleObject(proc_info.hProcess, timeout)`
   - Linux: `waitpid(pid, &status, WNOHANG)` in loop with timeout

2. **后台执行**:
   - 创建进程后立即返回 PID
   - 进程跟踪由 `process` 工具负责
   - 返回格式: `{"success": true, "message": "Started in background", "pid": 12345}`

3. **进程注册表**:
   ```cpp
   namespace {
     std::map<pid_t, BackgroundProcess>& background_processes() {
       static std::map<pid_t, BackgroundProcess> m;
       return m;
     }
   }
   ```

#### 4.3.3 代码结构

**新增文件**: `server/src/tools/shell_tool.cpp` / `.hpp`

**核心函数**:
```cpp
ToolResult shell_impl(const std::string& args_json);
ToolResult shell_execute_sync(const std::string& command, int timeout_ms);
ToolResult shell_execute_background(const std::string& command);
```

---

### 4.4 process — 进程管理工具

#### 4.4.1 工具定义

```json
{
  "type": "function",
  "function": {
    "name": "process",
    "description": "Manage running processes (list, kill, signal)",
    "parameters": {
      "type": "object",
      "properties": {
        "action": {
          "type": "string",
          "enum": ["list", "kill", "signal"],
          "description": "操作类型"
        },
        "pid": {
          "type": "integer",
          "description": "进程 ID（kill/signal 时必需）"
        },
        "filter": {
          "type": "string",
          "description": "进程名过滤（list 时可用）"
        }
      },
      "required": ["action"]
    }
  }
}
```

#### 4.4.2 实现方案

**新增文件**: `server/src/tools/process_tool.cpp` / `.hpp`

**Windows 实现**:
```cpp
std::vector<ProcessInfo> list_processes(const std::string& filter) {
  std::vector<ProcessInfo> result;
  DWORD aProcesses[1024], cbNeeded;

  if (!EnumProcesses(aProcesses, sizeof(aProcesses), &cbNeeded)) {
    return result;
  }

  DWORD cProcesses = cbNeeded / sizeof(DWORD);
  for (DWORD i = 0; i < cProcesses; i++) {
    if (aProcesses[i] == 0) continue;

    HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, aProcesses[i]);
    if (hProcess == NULL) continue;

    char szProcessName[MAX_PATH];
    HMODULE hMod;
    DWORD cbNeeded2;

    if (EnumProcessModules(hProcess, &hMod, sizeof(hMod), &cbNeeded2)) {
      GetModuleBaseName(hProcess, hMod, szProcessName, sizeof(szProcessName));

      if (filter.empty() || std::string(szProcessName).find(filter) != std::string::npos) {
        ProcessInfo info;
        info.pid = aProcesses[i];
        info.name = szProcessName;
        // 获取更多: CPU, 内存等
        result.push_back(info);
      }
    }
    CloseHandle(hProcess);
  }
  return result;
}
```

**Linux 实现**:
```cpp
std::vector<ProcessInfo> list_processes(const std::string& filter) {
  std::vector<ProcessInfo> result;
  for (const auto& entry : fs::directory_iterator("/proc")) {
    if (!entry.is_directory()) continue;

    std::string dirname = entry.path().filename().string();
    if (!std::all_of(dirname.begin(), dirname.end(), ::isdigit)) continue;

    pid_t pid = std::stoi(dirname);
    std::string cmdline_path = entry.path() / "cmdline";
    std::ifstream cmdfile(cmdline_path);
    std::string cmdline;
    std::getline(cmdfile, cmdline);

    if (filter.empty() || cmdline.find(filter) != std::string::npos) {
      ProcessInfo info;
      info.pid = pid;
      info.cmdline = cmdline;
      result.push_back(info);
    }
  }
  return result;
}
```

---

### 4.5 image — 图像理解工具

#### 4.5.1 工具定义

```json
{
  "type": "function",
  "function": {
    "name": "image",
    "description": "Analyze images using vision-capable LLM models. Supports file paths, URLs, and data URLs.",
    "parameters": {
      "type": "object",
      "properties": {
        "prompt": {
          "type": "string",
          "description": "分析提示词"
        },
        "image": {
          "type": "string",
          "description": "单张图片：文件路径、URL 或 data URL (data:image/png;base64,...)"
        },
        "model": {
          "type": "string",
          "description": "指定模型，默认使用配置的视觉模型"
        }
      },
      "required": ["prompt", "image"]
    }
  }
}
```

#### 4.5.2 实现方案

**新增文件**: `server/src/tools/image_tool.cpp` / `.hpp`

**核心实现**:
```cpp
ToolResult image_impl(const std::string& args_json) {
  std::string prompt = get_arg(args_json, "prompt");
  std::string image = get_arg(args_json, "image");
  std::string model = get_arg(args_json, "model");

  if (prompt.empty()) {
    return ToolResult{false, "", "missing 'prompt' argument"};
  }
  if (image.empty()) {
    return ToolResult{false, "", "missing 'image' argument"};
  }

  // 处理 image 参数
  std::string image_content;
  if (image.size() >= 5 && image.compare(0, 5, "http:") == 0 ||
      image.size() >= 6 && image.compare(0, 6, "https:") == 0) {
    // URL: 直接传递给 LLM API
    image_content = image;
  } else if (image.size() >= 22 && image.compare(0, 22, "data:image/") == 0) {
    // data URL: 直接使用
    image_content = image;
  } else {
    // 文件路径: 读取并转换为 base64 data URL
    std::ifstream f(image, std::ios::binary);
    if (!f) {
      return ToolResult{false, "", "cannot open image file: " + image};
    }
    std::vector<uint8_t> buffer((std::istreambuf_iterator<char>(f)), {});
    std::string base64 = base64_encode(buffer.data(), buffer.size());
    image_content = "data:image/png;base64," + base64;
  }

  // 调用视觉模型 API
  std::string base_url, model_id, api_key;
  bool use_openai;
  if (!config::resolve_vision_model(config, base_url, model_id, api_key, use_openai)) {
    return ToolResult{false, "", "vision model not configured"};
  }

  // 构造 Vision API 请求
  nlohmann::json messages = nlohmann::json::array();
  messages.push_back({
    {"role", "user"},
    {"content", nlohmann::json::array({
      {{"type", "text"}, {"text", prompt}},
      {{"type", "image_url"}, {"image_url", {{"url", image_content}}}}
    })}
  });

  net::HttpResponse res;
  if (!call_vision_api(base_url, model_id, api_key, messages, res)) {
    return ToolResult{false, "", res.error};
  }

  // 解析响应
  try {
    nlohmann::json j = nlohmann::json::parse(res.body);
    std::string result = j["choices"][0]["message"]["content"];
    return ToolResult{true, result, ""};
  } catch (const std::exception& e) {
    return ToolResult{false, "", "failed to parse vision response: " + std::string(e.what())};
  }
}
```

#### 4.5.3 Vision API 集成

**支持模型**:
- GLM-4V (智谱): `https://open.bigmodel.cn/api/paas/v4/chat/completions`
- GPT-4V (OpenAI): `https://api.openai.com/v1/chat/completions`
- Claude 3.5 Sonnet (Anthropic): `https://api.anthropic.com/v1/messages`

**请求格式** (OpenAI-compatible):
```json
{
  "model": "glm-4v",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "这张图片里有什么？"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}
      ]
    }
  ]
}
```

#### 4.5.4 配置

**hiclaw.json 扩展**:
```json
{
  "models": [
    {
      "id": "glm-4v",
      "provider": "glm",
      "api_key_env": "GLM_API_KEY",
      "capabilities": ["vision"]
    }
  ],
  "vision_model": "glm-4v"  // 默认视觉模型
}
```

**Config 解析** (`server/src/config/config.cpp`):
```cpp
bool resolve_vision_model(const Config& config,
                          std::string& out_base_url,
                          std::string& out_model_id,
                          std::string& out_api_key,
                          bool& out_use_openai);
```

---

### 4.6 Skill 系统增强

#### 4.6.1 当前实现状态

**已有组件**:
- `server/src/skills/skill_manager.cpp` — Skill 管理器
- `server/include/hiclaw/skills/skill_manager.hpp` — 头文件
- `skill.read` 工具 — 加载 skill 指令
- `build_skill_index_prompt()` — 构建系统提示注入

**已有方法但未暴露为工具**:
- `install_from_content()` — 从内容安装 skill
- `enable()` / `disable()` — 启用/禁用 skill
- `remove()` — 删除 skill
- `skills()` — 列出所有 skills

#### 4.6.2 新增工具

**skill.list**:
```json
{
  "type": "function",
  "function": {
    "name": "skill.list",
    "description": "List all available skills with their status",
    "parameters": {
      "type": "object",
      "properties": {}
    }
  }
}
```

**实现** (`tool.cpp`):
```cpp
ToolResult skill_list_impl(const std::string& args_json) {
  auto* mgr = skills::instance();
  if (!mgr) return ToolResult{false, "", "skill system not initialized"};

  nlohmann::json result = nlohmann::json::array();
  for (const auto& skill : mgr->skills()) {
    result.push_back({
      {"id", skill.id},
      {"name", skill.name},
      {"description", skill.description},
      {"builtin", skill.builtin},
      {"enabled", skill.enabled}
    });
  }
  return ToolResult{true, result.dump(), ""};
}
```

**skill.install**:
```json
{
  "type": "function",
  "function": {
    "name": "skill.install",
    "description": "Install a new skill from SKILL.md content",
    "parameters": {
      "type": "object",
      "properties": {
        "id": {"type": "string", "description": "Skill ID (directory name)"},
        "content": {"type": "string", "description": "SKILL.md file content"}
      },
      "required": ["id", "content"]
    }
  }
}
```

**实现**:
```cpp
ToolResult skill_install_impl(const std::string& args_json) {
  std::string skill_id = get_arg(args_json, "id");
  std::string content = get_arg(args_json, "content");

  auto* mgr = skills::instance();
  if (!mgr) return ToolResult{false, "", "skill system not initialized"};

  std::string err = mgr->install_from_content(skill_id, content);
  if (!err.empty()) {
    return ToolResult{false, "", err};
  }
  return ToolResult{true, "Installed skill: " + skill_id, ""};
}
```

**skill.enable / skill.disable**:
```json
{
  "type": "function",
  "function": {
    "name": "skill.enable",
    "description": "Enable a skill by ID",
    "parameters": {
      "type": "object",
      "properties": {
        "id": {"type": "string"}
      },
      "required": ["id"]
    }
  }
}
```

#### 4.6.3 Skill 系统工作流

```
用户请求 "部署 Node.js 应用"
        ↓
Agent 检查 "Available Skills" (系统提示中)
        ↓
匹配到 "Node.js Deployment"
        ↓
Agent 调用 skill.read(name="Node.js Deployment")
        ↓
返回 SKILL.md body（包含完整指令）
        ↓
Agent 按照 skill 中的指令执行 shell 命令
```

---

## 5. 数据流

### 5.1 截屏分析工作流

```
用户: "帮我分析一下当前屏幕"
        ↓
Agent LLM 返回: tool_calls=[{name="screen.capture", id="call_1", arguments={}}]
        ↓
Server: is_remote_tool("screen.capture") = true
        ↓
Server: 发送 node.invoke.request {command="screen.capture", params={}}
        ↓
Desktop: _onNodeInvoke() → _handleScreenCapture()
        ↓
Desktop: Win32ScreenCapture.captureScreen()
        ↓
Desktop: 返回 InvokeResult.success {image="data:image/png;base64,..."}
        ↓
Desktop: 发送 node.invoke.result
        ↓
Server: ToolRouter::complete_tool_call()
        ↓
Server: tool 消息加入 messages_json
        ↓
Agent LLM 收到 screen.capture 结果
        ↓
Agent LLM 返回: tool_calls=[{name="image", id="call_2", arguments={prompt="...", image="data:image/png;base64,..."}}]
        ↓
Server: is_remote_tool("image") = false (本地工具)
        ↓
Server: run_tool("image", args) → image_impl()
        ↓
Server: HTTP POST to Vision API (GLM-4V)
        ↓
Server: 返回分析结果
        ↓
Agent LLM 收到 image 结果
        ↓
Agent: 返回最终回复给用户
```

### 5.2 Web 搜索工作流

```
用户: "今天北京天气怎么样？"
        ↓
Agent LLM 返回: tool_calls=[{name="web_search", id="call_1", arguments={query="北京天气", count=5}}]
        ↓
Server: is_remote_tool("web_search") = false
        ↓
Server: run_tool("web_search", args) → web_search_impl()
        ↓
Server: HTTP GET to Brave Search API
        ↓
Server: 解析 JSON 响应
        ↓
Server: 返回搜索结果摘要
        ↓
Agent LLM 收到 web_search 结果
        ↓
Agent: 总结并返回给用户
```

### 5.3 后台 Shell 执行工作流

```
用户: "后台运行 npm run dev"
        ↓
Agent LLM 返回: tool_calls=[{name="shell", id="call_1", arguments={command="npm run dev", background=true}}]
        ↓
Server: shell_impl() → shell_execute_background()
        ↓
Server: CreateProcess("npm run dev", ...)
        ↓
Server: 返回 {success=true, message="Started in background", pid=12345}
        ↓
Agent: 告知用户 "已在后台启动 (PID: 12345)"
        ↓
[用户可以调用 process 工具查看/管理后台进程]
```

---

## 6. 配置变更

### 6.1 hiclaw.json 扩展

**新增字段**:
```json
{
  "vision_model": "glm-4v",
  "web_search": {
    "provider": "brave",
    "api_key_env": "BRAVE_SEARCH_API_KEY"
  },
  "shell": {
    "default_timeout_ms": 30000,
    "max_background_processes": 10
  }
}
```

**Config 结构体扩展** (`server/include/hiclaw/config/config.hpp`):
```cpp
struct Config {
  std::string default_model;
  std::string vision_model;
  WebSearchConfig web_search;
  ShellConfig shell;
  // ...
};
```

### 6.2 模型配置扩展

**models 项新增 capabilities 字段**:
```json
{
  "models": [
    {
      "id": "glm-4v",
      "provider": "glm",
      "api_key_env": "GLM_API_KEY",
      "capabilities": ["vision", "chat"],
      "base_url": "https://open.bigmodel.cn/api/paas/v4/"
    }
  ]
}
```

---

## 7. 涉及文件清单

### 7.1 新增文件

| 文件 | 描述 |
|------|------|
| `server/src/tools/web_search_tool.cpp` | Web 搜索工具实现 |
| `server/src/tools/web_search_tool.hpp` | Web 搜索工具头文件 |
| `server/src/tools/shell_tool.cpp` | Shell 增强工具实现 |
| `server/src/tools/shell_tool.hpp` | Shell 工具头文件 |
| `server/src/tools/process_tool.cpp` | 进程管理工具实现 |
| `server/src/tools/process_tool.hpp` | 进程管理工具头文件 |
| `server/src/tools/image_tool.cpp` | 图像分析工具实现 |
| `server/src/tools/image_tool.hpp` | 图像分析工具头文件 |
| `server/include/hiclaw/tools/vision_client.hpp` | Vision API 客户端 |
| `server/src/tools/vision_client.cpp` | Vision API 客户端实现 |

### 7.2 修改文件

| 文件 | 修改内容 |
|------|----------|
| `server/src/tools/tool.cpp` | 注册新工具，添加 skill.list/install/enable/disable |
| `server/src/agent/agent.cpp` | 添加 image 工具定义，更新工具列表 |
| `server/include/hiclaw/config/config.hpp` | 添加 VisionModel, WebSearchConfig 等配置 |
| `server/src/config/config.cpp` | 添加配置解析逻辑 |
| `desktop/lib/services/node_runtime.dart` | 添加 screen.capture handler，_handleScreenCapture() |
| `desktop/pubspec.yaml` | 添加 image 包依赖（PNG 编码） |

---

## 8. 实施顺序

### Phase 1: 核心能力 (P0)

1. **screen.capture (Desktop)** — 最简单，先完成验证流程
   - Desktop: 添加 `case 'screen.capture'` 到 `_onNodeInvoke()`
   - Desktop: 实现 `_handleScreenCapture()` 方法
   - 测试: 手动测试截屏功能

2. **web_search** — 独立工具，无依赖
   - Server: 实现 `web_search_tool.cpp`
   - Server: 添加配置解析
   - 测试: 验证 API 调用

3. **image 分析** — 依赖 screen.capture
   - Server: 实现 `image_tool.cpp`
   - Server: 添加 Vision API 客户端
   - 测试: 端到端截屏分析

4. **shell 增强** — 基础工具增强
   - Server: 重构 `shell_impl()` 为独立文件
   - Server: 添加超时控制
   - 测试: 长时间命令超时

5. **process** — 依赖 shell 增强
   - Server: 实现 `process_tool.cpp`
   - 测试: 后台进程管理

### Phase 2: Skill 增强 (P1)

6. **skill.list/install/enable/disable**
   - Server: 在 `tool.cpp` 中添加新工具实现
   - 测试: 安装、启用、禁用 skill

---

## 9. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **Vision API 成本高** | image 工具使用成本高 | 添加本地缓存，限制使用频率，提示用户成本 |
| **搜索 API 不稳定** | web_search 可能失败 | 实现多个提供商，自动降级到备用 API |
| **跨平台兼容性** | Shell/Process 工具在不同平台行为差异 | 抽象平台接口，分平台实现，充分测试 |
| **PNG 编码依赖** | Desktop 需要第三方库 | 使用 Flutter 内置 `dart:ui` 或轻量级 `image` 包 |
| **配置复杂性** | 新增多个配置项，用户难以配置 | 提供默认值，详细文档，交互式配置命令 |
| **后台进程泄漏** | 后台启动的进程可能未清理 | 实现 `process` 工具管理，添加清理机制 |

---

**文档结束**
