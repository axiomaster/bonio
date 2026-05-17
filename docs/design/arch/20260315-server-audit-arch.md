# HiClaw Server 端完善设计文档

## 1. 项目概述

### 1.1 背景
HiClaw (server/) 是 BoJi 项目的 C++ 后端服务，目标是兼容 OpenClaw/ZeroClaw 协议，为 Android 和 HarmonyOS 客户端提供 AI Agent 能力。

### 1.2 当前状态
- ✅ 基础 CLI 框架
- ✅ Agent 单轮对话 (支持 Ollama/OpenAI 兼容接口)
- ✅ 基础工具 (shell, file_read, file_write, web_fetch, memory_*)
- ✅ WebSocket Gateway (websocketpp / libwebsockets 双后端)
- ✅ 基础协议 (connect, agent.run, chat.run, chat.history, sessions.list)
- ✅ 文件记忆系统
- ✅ 定时任务调度

### 1.3 目标
完善 Gateway 协议支持，实现与 OpenClaw/ZeroClaw 完全兼容的 WebSocket 通信，支持流式响应、多模态、设备能力调用等高级功能。

---

## 2. 现有架构分析

### 2.1 目录结构
```
server/
├── include/hiclaw/
│   ├── agent/          # Agent 核心
│   ├── config/         # 配置管理
│   ├── cron/           # 定时任务
│   ├── memory/         # 记忆系统
│   ├── net/            # 网络 (gateway, http_client, serve)
│   ├── observability/  # 日志
│   ├── providers/      # LLM 提供商
│   ├── security/       # 安全路径保护
│   ├── tools/          # 工具注册
│   └── types/          # 类型定义
├── src/                # 实现文件
└── third_party/        # 第三方库
```

### 2.2 当前协议实现 (gateway.cpp)
| 方法 | 状态 | 说明 |
|------|------|------|
| `connect` | ✅ | 支持 password/token 认证 |
| `agent.run` | ✅ | 单轮对话，返回完整响应 |
| `chat.run` | ✅ | 同 agent.run |
| `chat.history` | ✅ | 返回空历史 (Stub) |
| `sessions.list` | ✅ | 返回固定 "main" 会话 |

### 2.3 客户端期望协议 (基于 Android ChatController.kt)
| 方法 | 状态 | 说明 |
|------|------|------|
| `connect` | ✅ | 已实现 |
| `chat.send` | ❌ | 需实现：发送消息，支持流式响应 |
| `chat.subscribe` | ❌ | 需实现：订阅会话事件 |
| `chat.abort` | ❌ | 需实现：中止正在进行的请求 |
| `chat.history` | ⚠️ | 需完善：持久化历史记录 |
| `sessions.list` | ⚠️ | 需完善：真实的会话列表 |
| `health` | ❌ | 需实现：健康检查 |
| 设备能力 RPC | ❌ | 需实现：camera.*, screen.*, device.* 等 |

---

## 3. 核心设计

### 3.1 协议层架构

```
┌─────────────────────────────────────────────────────────────┐
│                      WebSocket Server                        │
│                   (websocketpp / libwebsockets)              │
├─────────────────────────────────────────────────────────────┤
│                     Protocol Handler                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  认证层     │  │  RPC 路由   │  │  事件推送 (Events)  │  │
│  │  connect    │  │  dispatch   │  │  chat/agent/tick    │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                      业务层 (Handlers)                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ ChatHandler  │  │ AgentHandler │  │ DeviceHandler    │   │
│  │ send/history │  │ run/stream   │  │ camera/screen... │   │
│  └──────────────┘  └──────────────┘  └──────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                      数据层 (Store)                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ SessionStore │  │ MessageStore │  │ MemoryStore      │   │
│  │ 会话管理     │  │ 消息持久化   │  │ 长期记忆         │   │
│  └──────────────┘  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 消息格式

#### 3.2.1 请求格式 (Client → Server)
```json
{
  "method": "chat.send",
  "id": "req-123",
  "params": {
    "sessionKey": "main",
    "message": "你好",
    "thinking": "off",
    "timeoutMs": 30000,
    "idempotencyKey": "run-uuid",
    "attachments": [
      {
        "type": "image",
        "mimeType": "image/png",
        "fileName": "photo.png",
        "content": "<base64>"
      }
    ]
  }
}
```

#### 3.2.2 响应格式 (Server → Client)
```json
{
  "type": "res",
  "id": "req-123",
  "ok": true,
  "payload": {
    "runId": "run-uuid"
  }
}
```

#### 3.2.3 事件格式 (Server → Client, 推送)
```json
{
  "type": "event",
  "event": "chat",
  "payload": {
    "sessionKey": "main",
    "runId": "run-uuid",
    "state": "delta",
    "message": {
      "role": "assistant",
      "content": [{"type": "text", "text": "..."}]
    }
  }
}
```

### 3.3 状态机

```
┌─────────┐   connect    ┌────────────┐
│  初始   │ ───────────> │  已认证    │
└─────────┘              └────────────┘
                               │
                     chat.send │
                               ▼
                         ┌────────────┐
                         │  处理中    │
                         └────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
    ┌──────────┐        ┌──────────┐        ┌──────────┐
    │  delta   │        │  final   │        │  error   │
    │ (流式)   │        │ (完成)   │        │ (错误)   │
    └──────────┘        └──────────┘        └──────────┘
```

---

## 4. 模块设计

### 4.1 会话管理 (Session Store)

**文件**: `include/hiclaw/store/session_store.hpp`, `src/store/session_store.cpp`

```cpp
namespace hiclaw::store {

struct Session {
  std::string key;           // 会话标识
  std::string display_name;  // 显示名称
  int64_t updated_at;        // 最后更新时间戳 (ms)
  std::string thinking_level;// 思考级别
};

struct Message {
  std::string role;          // user/assistant/system/tool
  std::vector<ContentPart> content;
  int64_t timestamp;
};

struct ContentPart {
  std::string type;          // text/image/audio
  std::string text;          // 文本内容
  std::string mime_type;     // 多媒体类型
  std::string file_name;     // 文件名
  std::string base64;        // Base64 数据
};

class SessionStore {
public:
  void set_base_path(const std::string& path);

  // 会话操作
  std::vector<Session> list_sessions(int limit = 50);
  Session get_or_create(const std::string& key);
  void update_timestamp(const std::string& key);

  // 消息操作
  void append_message(const std::string& session_key, const Message& msg);
  std::vector<Message> get_history(const std::string& session_key, int limit = 100);
  void clear_history(const std::string& session_key);

  // 会话 ID (兼容 OpenClaw)
  std::string get_session_id(const std::string& key);
};

}  // namespace hiclaw::store
```

**存储格式**: `config_dir/sessions/{session_key}.json`
```json
{
  "key": "main",
  "displayName": "Main Chat",
  "updatedAt": 1709123456789,
  "thinkingLevel": "off",
  "sessionId": "sess-uuid",
  "messages": [
    {
      "role": "user",
      "content": [{"type": "text", "text": "你好"}],
      "timestamp": 1709123456789
    }
  ]
}
```

### 4.2 流式响应 (Streaming Agent)

**文件**: `include/hiclaw/agent/streaming_agent.hpp`, `src/agent/streaming_agent.cpp`

```cpp
namespace hiclaw::agent {

// 流式回调
using StreamCallback = std::function<void(const std::string& delta_text, bool done)>;

struct StreamResult {
  bool ok = false;
  std::string error;
};

// 支持流式的 Agent
StreamResult run_streaming(
    const config::Config& config,
    const std::vector<types::Message>& history,
    const std::string& user_message,
    const std::vector<Attachment>& attachments,
    double temperature,
    StreamCallback callback
);

}  // namespace hiclaw::agent
```

**实现策略**:
1. 对于支持流式的 Provider (如 Ollama, OpenAI)，使用 SSE 或 chunked response
2. 每收到一个 token 立即通过回调推送
3. 当前 HTTP 客户端 (`http_client.hpp`) 需扩展支持流式读取

### 4.3 事件推送 (Event Pusher)

**文件**: `include/hiclaw/net/event_pusher.hpp`

```cpp
namespace hiclaw::net {

enum class EventType {
  CHAT,
  AGENT,
  TICK,
  HEALTH,
  SEQ_GAP
};

struct Event {
  EventType type;
  std::string event_name;  // "chat", "agent", "tick" 等
  nlohmann::json payload;
};

class EventPusher {
public:
  virtual ~EventPusher() = default;
  virtual void push(const Event& event) = 0;
  virtual bool is_connected() const = 0;
};

// WebSocket 实现
class WsEventPusher : public EventPusher {
public:
  void push(const Event& event) override;
  bool is_connected() const override;

  // 发送节点事件 (如 chat.subscribe)
  void send_node_event(const std::string& name, const std::string& params_json);
};

}  // namespace hiclaw::net
```

### 4.4 RPC 方法注册表

**文件**: `include/hiclaw/net/rpc_registry.hpp`

```cpp
namespace hiclaw::net {

using RpcHandler = std::function<nlohmann::json(const nlohmann::json& params)>;

class RpcRegistry {
public:
  void register_method(const std::string& name, RpcHandler handler);
  std::optional<nlohmann::json> dispatch(const std::string& method,
                                          const nlohmann::json& params);

private:
  std::unordered_map<std::string, RpcHandler> handlers_;
};

}  // namespace hiclaw::net
```

### 4.5 设备能力框架 (Device Capabilities)

**文件**: `include/hiclaw/device/capability.hpp`

```cpp
namespace hiclaw::device {

struct CapabilityResult {
  bool ok = false;
  nlohmann::json data;
  std::string error;
};

using CapabilityHandler = std::function<CapabilityResult(const nlohmann::json& params)>;

class CapabilityRegistry {
public:
  void register_capability(const std::string& name, CapabilityHandler handler);
  CapabilityResult invoke(const std::string& name, const nlohmann::json& params);
  std::vector<std::string> list_capabilities();

private:
  std::unordered_map<std::string, CapabilityHandler> handlers_;
};

// 内置能力 (服务端逻辑，客户端执行)
// 客户端通过 A2UI (Agent-to-UI) 机制响应

}  // namespace hiclaw::device
```

**能力定义** (对应 Android OpenClawCapability):
| 能力 | 方法 | 说明 |
|------|------|------|
| canvas | canvas.present, canvas.hide, canvas.navigate | 画布控制 |
| camera | camera.list, camera.snap | 相机 |
| screen | screen.record | 屏幕录制 |
| device | device.status, device.info | 设备状态 |
| notifications | notifications.list | 通知 |
| system | system.notify | 系统通知 |

---

## 5. 协议实现计划

### 5.1 Phase 1: 会话持久化 (优先)

**目标**: 让 chat.history 和 sessions.list 返回真实数据

**新增文件**:
- `include/hiclaw/store/session_store.hpp`
- `src/store/session_store.cpp`

**修改文件**:
- `src/net/gateway.cpp`: 使用 SessionStore 处理 chat.history 和 sessions.list

**任务**:
1. 实现 SessionStore 类
2. 修改 chat.history 返回持久化历史
3. 修改 sessions.list 返回真实会话列表
4. chat.run/chat.send 时自动保存消息

### 5.2 Phase 2: 流式响应与事件推送

**目标**: 支持 chat.send 的流式响应

**新增文件**:
- `include/hiclaw/agent/streaming_agent.hpp`
- `src/agent/streaming_agent.cpp`
- `include/hiclaw/net/event_pusher.hpp`

**修改文件**:
- `include/hiclaw/net/http_client.hpp`: 添加流式读取支持
- `src/providers/ollama.cpp`: 支持 stream=true
- `src/providers/openai_compatible.cpp`: 支持 stream=true
- `src/net/gateway.cpp`: 实现事件推送机制

**任务**:
1. 扩展 HTTP 客户端支持 chunked response
2. 实现 Ollama/OpenAI 流式 API 调用
3. 实现事件推送机制
4. 实现 chat.send 方法 (异步，流式)
5. 实现 chat.subscribe 方法

### 5.3 Phase 3: 多模态支持

**目标**: 支持图片、音频等附件

**修改文件**:
- `include/hiclaw/types/message.hpp`: 扩展 ContentPart
- `src/agent/agent.cpp`: 处理多模态内容
- `src/providers/ollama.cpp`: 支持 image_url
- `src/providers/openai_compatible.cpp`: 支持 image_url

**任务**:
1. 扩展消息类型支持多模态
2. 实现 Base64 图片传递给 LLM
3. 在 SessionStore 中持久化多模态消息

### 5.4 Phase 4: 设备能力 RPC

**目标**: 支持服务端发起的设备能力调用

**新增文件**:
- `include/hiclaw/device/capability.hpp`
- `src/device/capability.cpp`

**修改文件**:
- `src/net/gateway.cpp`: 注册设备能力方法

**任务**:
1. 实现 CapabilityRegistry 框架
2. 注册设备能力方法 (Stub，等待客户端响应)
3. 实现 A2UI 请求-响应机制

### 5.5 Phase 5: 完善与优化

**任务**:
1. 实现 health 方法
2. 实现 chat.abort 方法
3. 错误处理完善
4. 性能优化 (消息索引、懒加载)
5. 单元测试

---

## 6. 接口对照表

### 6.1 需实现的 RPC 方法

| 方法 | Phase | 说明 |
|------|-------|------|
| `health` | 1 | 健康检查，返回 `{"ok": true}` |
| `chat.send` | 2 | 发送消息，支持流式响应和附件 |
| `chat.subscribe` | 2 | 订阅会话事件 |
| `chat.abort` | 5 | 中止正在进行的请求 |
| `device.status` | 4 | 设备状态 (Stub) |
| `camera.list` | 4 | 相机列表 (Stub) |
| `camera.snap` | 4 | 拍照 (Stub) |
| `screen.record` | 4 | 屏幕录制 (Stub) |

### 6.2 需推送的事件

| 事件 | Phase | 触发条件 |
|------|-------|----------|
| `connect.challenge` | ✅ | 连接建立时 |
| `chat` (delta) | 2 | 流式响应中每个 token |
| `chat` (final) | 2 | 响应完成 |
| `chat` (error) | 2 | 响应错误 |
| `agent` (tool) | 2 | 工具调用开始/结束 |
| `tick` | 2 | 定时心跳 |
| `health` | 1 | 健康检查响应 |

---

## 7. 技术决策

### 7.1 流式实现方案

**选择**: 在 HTTP 客户端层实现 chunked response 解析

**原因**:
- 不引入额外依赖
- 与现有 httplib 兼容
- Ollama 和 OpenAI 都支持 SSE 格式

**示例**:
```cpp
// 扩展 http_client
void streaming_get(const std::string& url,
                   std::function<bool(const std::string& chunk)> on_chunk);
```

### 7.2 会话存储方案

**选择**: 基于文件的 JSON 存储

**原因**:
- 零依赖，与现有 memory 系统一致
- 适合 HarmonyOS/Android 沙箱环境
- 易于调试和迁移

**优化** (可选): 后续可添加 LRU 缓存减少 IO

### 7.3 事件推送方案

**选择**: 在 WebSocket 连接上下文中直接发送

**原因**:
- 简单直接，无额外依赖
- websocketpp 和 libwebsockets 都支持异步发送
- 与现有架构一致

---

## 8. 风险与注意事项

1. **流式 HTTP 兼容性**: httplib 默认不支持流式响应，需验证扩展方案
2. **线程安全**: 事件推送需确保 WebSocket 发送在正确线程
3. **会话并发**: 多客户端同时操作同一会话需加锁
4. **内存管理**: 流式响应需注意 buffer 生命周期
5. **协议兼容**: 保持与 OpenClaw 协议的完全兼容，便于客户端无缝切换

---

## 9. 验收标准

### Phase 1:
- [ ] `sessions.list` 返回真实会话列表
- [ ] `chat.history` 返回持久化历史
- [ ] 多轮对话历史被正确保存

### Phase 2:
- [ ] `chat.send` 返回 runId
- [ ] 客户端收到流式 delta 事件
- [ ] 完成后收到 final 事件
- [ ] 工具调用通过 agent 事件推送

### Phase 3:
- [ ] 发送带图片的消息成功
- [ ] 图片被正确传递给 LLM
- [ ] 历史记录包含图片

### Phase 4:
- [ ] `device.status` 返回 (即使是 Stub)
- [ ] 设备能力方法可被调用

### Phase 5:
- [ ] `health` 方法正常工作
- [ ] `chat.abort` 能中止请求
- [ ] 错误处理完善

---

## 10. 时间估算

| Phase | 工作量 | 说明 |
|-------|--------|------|
| Phase 1 | 2-3 天 | 会话存储，基础结构 |
| Phase 2 | 3-5 天 | 流式响应，事件系统 |
| Phase 3 | 1-2 天 | 多模态支持 |
| Phase 4 | 2-3 天 | 设备能力框架 |
| Phase 5 | 2-3 天 | 完善与测试 |
| **总计** | **10-16 天** | |

---

*文档版本: 1.0 | 创建日期: 2026-03-15*
