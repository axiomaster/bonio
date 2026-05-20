# HiClaw Agent 能力增强 — 架构评审报告

## 1. 评审概要

**总体评估**: **PASS WITH ISSUES**

PRD 和架构设计总体完整，与现有 HiClaw 代码库架构基本吻合。但存在若干**关键问题**需要修复后才能开始实施：

- **Critical**: Desktop 端 `screen.capture` 实现缺失 PNG 编码功能
- **Major**: `image` 工具的 Vision API 集成缺少 `call_vision_api()` 具体实现
- **Major**: `shell` 工具增强缺少后台进程跟踪机制设计
- **Minor**: 配置文件命名不一致 (`config.json` vs `hiclaw.json`)

---

## 2. PRD 评审

### 2.1 优点

1. **用户场景清晰**: 三个核心场景（截图助手、实时查询、Skill 自进化）具体可测
2. **工具分类合理**: 按类别（Files/Runtime/Web/Memory/Sessions/Media/UI/Automation/Skills）组织工具，便于管理
3. **参数定义精确**: 大部分工具参数都有明确的类型、是否必需、默认值说明
4. **验收标准可测试**: 每个功能都有对应的测试用例和预期结果
5. **分阶段实施**: Phase 1-3 优先级划分合理，P0 能力定义准确

### 2.2 问题

| 严重程度 | 位置 | 问题描述 | 建议修复 |
|----------|------|----------|----------|
| **Critical** | §3.2.2 实现要点 | 声称 Desktop 端已有 `Win32ScreenCapture.capture()` 实现，但**缺少 PNG 编码**。`captureScreen()` 返回的是原始 BGRA 像素数据 (`ScreenCaptureResult`)，不是 base64 PNG。 | 在 Desktop 实现中添加 PNG 编码步骤。建议使用 `dart:ui` 的 `Image.toByteData()` 或第三方 `image` 包的 `encodePng()` 函数。 |
| **Major** | §3.6.1 工具定义 | `image` 工具参数 `maxImages` 未在实现要点中使用，PRD 提到"支持多图分析"但 Phase 1 只实现单图 | 移除 `maxImages` 参数或在实现中说明 Phase 2 才支持 |
| **Major** | §3.4.2 增强方案 | `shell` 后台执行返回 PID，但**未说明如何跟踪这些进程**。`process` 工具是独立的，二者之间的数据共享机制未定义。 | 补充后台进程注册表设计：说明 `shell` 启动的进程如何注册，`process` 如何查询这些进程 |
| **Minor** | §3.3.3 安全考虑 | API 密钥通过 `hiclaw.json` 配置，但代码中默认文件名是 `config.json` | 统一为 `hiclaw.json` 或说明两者兼容 |
| **Minor** | §3.2.3 边界情况 | 多显示器环境只捕获主显示器，但未说明如何确定"主显示器" | 补充说明：在 Windows 上使用 `SM_CXSCREEN/SM_CYSCREEN` 获取主显示器 |

### 2.3 建议

1. **明确 PNG 编码方案**：在 PRD 中明确 Desktop 端使用哪种方式实现 PNG 编码（`dart:ui` 或 `image` 包）
2. **后台进程管理**：在 PRD 中添加一节说明 `shell` 和 `process` 工具如何共享进程列表
3. **配置示例完整化**：提供完整的 `hiclaw.json` 配置示例，包括所有新增字段
4. **错误码标准化**：建议定义统一的错误码枚举，而非字符串

---

## 3. 架构评审

### 3.1 优点

1. **架构验证充分**: 设计文档引用了实际代码位置（`tool.cpp:192-205`, `async_agent.cpp:811-830`），与代码完全吻合
2. **组件图清晰**: Server/Desktop 双 WebSocket 会话架构描述准确
3. **数据流完整**: 截屏分析、Web 搜索、后台 Shell 执行三个工作流描述详尽
4. **复用现有代码**: 正确识别了 Desktop 端 `Win32ScreenCapture.captureScreen()`、`cron` 系统等可复用组件
5. **实施顺序合理**: 从最简单的 `screen.capture` 开始，逐步推进到复杂工具

### 3.2 问题

| 严重程度 | 位置 | 问题描述 | 建议修复 |
|----------|------|----------|----------|
| **Critical** | §4.1.2 设计方案 | Desktop 端 `_handleScreenCapture()` 代码示例中调用 `encodePng(result)`，但 `result` 是 `ScreenCaptureResult` 类型（包含 BGRA 像素），**没有实现 PNG 编码**。代码示例不可运行。 | 修正代码示例，说明需要先将 BGRA 转换为 Image 对象，再调用 PNG 编码。或使用 `image` 包的 `encodePng()` 函数。 |
| **Major** | §4.5.2 实现方案 | `image` 工具实现调用 `call_vision_api()` 函数，但**该函数未定义**。架构中提到要支持 GLM-4V/GPT-4V/Claude，但缺少具体的 HTTP 请求实现。 | 补充 `call_vision_api()` 函数实现，或说明复用现有 `http_client.cpp` 中的 `post()` 方法 |
| **Major** | §4.3.2 增强方案 | 后台进程注册表使用 `std::map<pid_t, BackgroundProcess>`，但**未说明如何防止内存泄漏**（进程结束后何时清理条目）。 | 补充清理机制：`process` 工具的 list 操作应该清理僵尸进程，或添加定期清理线程 |
| **Minor** | §4.2.4 配置存储 | `hiclaw.json` 示例中 `web_search` 配置与现有 `Config` 结构体不匹配（现有代码没有 `WebSearchConfig`） | 说明需要在 `config.hpp` 中添加 `WebSearchConfig` 结构体 |
| **Minor** | §4.5.4 配置 | 模型配置中的 `capabilities` 字段未在现有 `ModelEntry` 结构体中定义 | 说明需要在 `ModelEntry` 中添加 `std::vector<std::string> capabilities` 字段 |

### 3.3 建议

1. **补充 Vision API 客户端设计**: 在 §4.5 节后添加一个子节，详细说明如何构造 OpenAI-compatible Vision API 请求
2. **后台进程生命周期管理**: 添加进程状态跟踪（running/zombie/stopped），防止内存泄漏
3. **工具注册扩展**: 建议实现 `struct ToolDefinition`，避免硬编码 JSON 工具定义
4. **错误处理标准化**: 建议定义 `enum class ToolErrorCode { TIMEOUT, NOT_FOUND, PERMISSION_DENIED, ... }`

---

## 4. 代码验证

### 4.1 工具定义格式

✅ **验证通过** — 架构 §3.1 描述的工具定义格式与 `agent.cpp:72-103` 完全一致：

```cpp
// agent.cpp:76
tools.push_back(json::parse(R"({"type":"function","function":{"name":"shell","description":"Run a shell command","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}})"));
```

### 4.2 远程工具判断

✅ **验证通过** — 架构 §3.2 的 `is_remote_tool()` 实现与 `tool.cpp:192-205` 完全一致：

```cpp
// tool.cpp:192-205
bool is_remote_tool(const std::string& name) {
  static const char* remote_prefixes[] = {
    "screen.", "camera.", "location.", "device.", "notifications.",
    "system.", "sms.", "photos.", "contacts.", "calendar.", "motion.",
    "canvas.", "telephony.", "input.",
    nullptr
  };
  // ...
}
```

### 4.3 工具路由逻辑

✅ **验证通过** — 架构 §3.3 描述的远程工具路由与 `async_agent.cpp:214-261` 完全一致：

```cpp
// async_agent.cpp:214-261
agent::RemoteToolExecutor remote_executor = nullptr;
if (tool_router_) {
  auto tr = tool_router_;
  auto event_cb = [this](const std::string& name, const std::string& payload) {
    send_event(name, payload);
  };
  remote_executor = [tr, event_cb, &task](
      const std::string& tool_call_id,
      const std::string& tool_name,
      const std::string& args_json) -> types::ToolResult {
    // Send node.invoke.request to client
    // ...
  };
}

// agent.cpp:814
if (tools::is_remote_tool(tc.name) && remote_executor) {
  tr = remote_executor(tc.id, tc.name, tc.arguments);
} else {
  tr = tools::run_tool(tc.name, tc.arguments);
}
```

### 4.4 Desktop Handler 实现

✅ **验证通过** — Desktop 端 `_onNodeInvoke()` 路由模式与架构描述一致：

```dart
// node_runtime.dart:808-830
Future<InvokeResult> _onNodeInvoke(InvokeRequest request) async {
  switch (request.command) {
    case 'device.info':
      return InvokeResult.success(jsonEncode({...}));
    case 'camera.snap':
      return _handleCameraSnap(request.paramsJson);
    default:
      return InvokeResult.fail('UNSUPPORTED_COMMAND',
          'Desktop client does not support: ${request.command}');
  }
}
```

❌ **问题确认** — `screen.capture` 确实**未实现**，返回 `UNSUPPORTED_COMMAND`。

### 4.5 Win32ScreenCapture 实现

✅ **验证通过** — `Win32ScreenCapture.captureScreen()` 存在且返回 BGRA 像素：

```dart
// win32_screen_capture.dart:57-137
static ScreenCaptureResult? captureScreen() {
  // ...
  return ScreenCaptureResult(
    originX: screenX,
    originY: screenY,
    width: physW,
    height: physH,
    bgraPixels: pixels,  // 原始 BGRA 数据，非 PNG
    dpiScale: scale,
  );
}
```

❌ **问题确认** — **缺少 PNG 编码**。返回的是 `Uint8List` BGRA 像素，需要转换为 PNG。

---

## 5. 综合建议

### 5.1 必须修复（阻断实施）

1. **PNG 编码方案**（Critical）
   - 在 Desktop 实现中添加 PNG 编码
   - 推荐方案：使用 `image` 包的 `encodePng()` 函数
   - 需要在 `desktop/pubspec.yaml` 中添加依赖：`image: ^4.0.0`

2. **Vision API 集成**（Major）
   - 补充 `call_vision_api()` 函数实现
   - 可复用 `net::http_client.cpp` 中的 `post()` 方法
   - 构造 OpenAI-compatible 请求格式

3. **后台进程管理**（Major）
   - 补充 `shell` 和 `process` 工具的进程共享机制
   - 添加进程状态跟踪和清理逻辑

### 5.2 建议修复（提升质量）

1. **配置文件命名统一**：使用 `hiclaw.json` 或明确兼容性
2. **工具定义结构化**：实现 `struct ToolDefinition` 避免硬编码 JSON
3. **错误码标准化**：定义统一的错误码枚举

### 5.3 实施前检查清单

- [ ] Desktop 端 PNG 编码方案确定并测试
- [ ] Vision API HTTP 请求实现完成
- [ ] 后台进程注册表设计文档化
- [ ] 配置结构体扩展（`WebSearchConfig`, `ShellConfig`, `ModelEntry::capabilities`）
- [ ] 单元测试框架准备

---

## 6. 修订建议

### 6.1 PRD 修订（§3.2.2）

**原文**：
> Desktop 客户端:
> - 已有 `desktop/lib/platform/win32_screen_capture.dart` 实现
> - 需要在 `NodeRuntime._onNodeInvoke()` 中添加 `screen.capture` 的处理
> - 路由到现有的 `Win32ScreenCapture.capture()` 方法

**修订为**：
> Desktop 客户端:
> - 已有 `desktop/lib/platform/win32_screen_capture.dart` 实现，但返回 BGRA 像素，需 PNG 编码
> - 需要在 `desktop/pubspec.yaml` 添加 `image: ^4.0.0` 依赖
> - 在 `NodeRuntime._onNodeInvoke()` 中添加 `screen.capture` 的处理
> - 路由到 `_handleScreenCapture()` 方法，使用 `encodePng()` 编码

### 6.2 架构修订（§4.1.2）

**原文**：
```dart
// 转换为 base64 PNG
final pngBytes = encodePng(result); // 需要实现 PNG 编码
```

**修订为**：
```dart
// 转换为 base64 PNG
import 'package:image/image.dart';

// 将 BGRA 像素转换为 Image 对象
final img = Image.fromBytes(
  width: result.width,
  height: result.height,
  bytes: result.bgraPixels.buffer,
  format: Format.bgra,
);
final pngBytes = encodePng(img);
final base64 = base64Encode(pngBytes);
```

### 6.3 架构修订（§4.5.2 后添加）

**新增子节**：

#### 4.5.5 Vision API 客户端实现

使用现有的 `net::http_client.cpp` 实现 Vision API 调用：

```cpp
bool call_vision_api(const std::string& base_url,
                     const std::string& model_id,
                     const std::string& api_key,
                     const nlohmann::json& messages,
                     net::HttpResponse& out_response) {
  nlohmann::json req_body;
  req_body["model"] = model_id;
  req_body["messages"] = messages;
  req_body["max_tokens"] = 4096;

  net::HttpRequest req;
  req.method = "POST";
  req.url = base_url + "chat/completions";
  req.headers["Content-Type"] = "application/json";
  req.headers["Authorization"] = "Bearer " + api_key;
  req.body = req_body.dump();

  return net::post(req, out_response);
}
```

### 6.4 架构修订（§4.3.2 后添加）

**新增内容**：

**后台进程清理机制**：
```cpp
namespace {
  struct BackgroundProcess {
    pid_t pid;
    std::string command;
    std::chrono::system_clock::time_point start_time;
    bool is_zombie = false;
  };

  std::map<pid_t, BackgroundProcess>& background_processes() {
    static std::map<pid_t, BackgroundProcess> m;
    return m;
  }

  void cleanup_zombie_processes() {
    for (auto it = background_processes().begin(); it != background_processes().end(); ) {
      pid_t result = waitpid(it->first, nullptr, WNOHANG);
      if (result == it->first || result == -1) {
        // Process has terminated
        it = background_processes().erase(it);
      } else {
        ++it;
      }
    }
  }
}
```

---

**评审完成** — 2025-05-21
