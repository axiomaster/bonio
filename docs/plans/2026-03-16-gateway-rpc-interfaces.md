# Gateway RPC 接口补齐实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 完善 HiClaw 服务端的 RPC 接口，使其能够与 Android/HarmonyOS 客户端正确对接。

**Architecture:** 采用异步事件驱动架构，将阻塞式的 `agent.run` 改造为非阻塞的 `chat.send`，通过后台线程处理 LLM 请求，并通过 WebSocket 推送流式事件。

**Tech Stack:** C++17, websocketpp, nlohmann/json, std::thread

---

## 阶段一：短期修复 (Stub 接口)

### Task 1: 实现 health 接口

**Files:**
- Modify: `server/src/net/gateway.cpp:59-137` (gateway_handle_frame 函数)

**Step 1: 添加 health 方法处理**

在 `gateway_handle_frame` 函数的 `sessions.list` 处理之后、`UNKNOWN_METHOD` 之前添加：

```cpp
  if (method == "health") {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"status", "ok"}};
    return res.dump();
  }
```

**Step 2: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 3: 提交**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat(gateway): add health RPC endpoint"
```

---

### Task 2: 实现 config.get 接口

**Files:**
- Modify: `server/src/net/gateway.cpp`

**Step 1: 添加 config.get 方法处理**

在 health 接口之后添加：

```cpp
  if (method == "config.get") {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {
      {"node", {
        {"version", "0.1.0"},
        {"platform", "server"}
      }},
      {"connection", {
        {"status", connected ? "connected" : "disconnected"}
      }},
      {"model", {
        {"default", config.default_model}
      }}
    };
    return res.dump();
  }
```

**Step 2: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 3: 提交**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat(gateway): add config.get RPC endpoint"
```

---

### Task 3: 实现 voicewake.get/set 接口

**Files:**
- Modify: `server/src/net/gateway.cpp`

**Step 1: 添加 voicewake 接口**

在 config.get 之后添加：

```cpp
  // 静态变量存储语音唤醒状态（简化实现）
  static bool voicewake_enabled = false;

  if (method == "voicewake.get") {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"enabled", voicewake_enabled}};
    return res.dump();
  }

  if (method == "voicewake.set") {
    // 从 params 中获取 enabled 参数
    bool new_enabled = false;
    try {
      json j = json::parse(frame);
      if (j.contains("params") && j["params"].is_object()) {
        if (j["params"].contains("enabled")) {
          new_enabled = j["params"]["enabled"].get<bool>();
        }
      }
    } catch (...) {}
    voicewake_enabled = new_enabled;

    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"enabled", voicewake_enabled}};
    return res.dump();
  }
```

**Step 2: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 3: 提交**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat(gateway): add voicewake.get/set RPC endpoints"
```

---

## 阶段二：异步聊天架构

### Task 4: 定义异步任务管理器

**Files:**
- Create: `server/include/hiclaw/net/async_agent.hpp`
- Create: `server/src/net/async_agent.cpp`

**Step 1: 创建头文件**

```cpp
#ifndef HICLAW_NET_ASYNC_AGENT_HPP
#define HICLAW_NET_ASYNC_AGENT_HPP

#include "hiclaw/config/config.hpp"
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <atomic>
#include <mutex>
#include <thread>
#include <condition_variable>

namespace hiclaw {
namespace net {

// 事件回调类型: event_name, payload_json
using EventCallback = std::function<void(const std::string&, const std::string&)>;

// 异步运行任务状态
struct AsyncTask {
  std::string run_id;
  std::string session_key;
  std::string message;
  std::atomic<bool> aborted{false};
  std::thread worker;
};

// 异步 Agent 管理器
class AsyncAgentManager {
public:
  AsyncAgentManager(const config::Config& config, EventCallback callback);
  ~AsyncAgentManager();

  // 启动新的异步任务，返回 run_id
  std::string start_task(const std::string& session_key, const std::string& message);

  // 中止任务
  bool abort_task(const std::string& run_id);

  // 检查任务是否存在
  bool has_task(const std::string& run_id) const;

private:
  void run_task(std::shared_ptr<AsyncTask> task);
  void send_event(const std::string& event_name, const std::string& payload_json);

  const config::Config& config_;
  EventCallback event_callback_;

  mutable std::mutex tasks_mutex_;
  std::unordered_map<std::string, std::shared_ptr<AsyncTask>> tasks_;
};

}  // namespace net
}  // namespace hiclaw

#endif
```

**Step 2: 创建实现文件**

```cpp
#include "hiclaw/net/async_agent.hpp"
#include "hiclaw/agent/agent.hpp"
#include "hiclaw/observability/log.hpp"
#include <sstream>
#include <random>
#include <chrono>

namespace hiclaw {
namespace net {

namespace {

std::string generate_run_id() {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<uint64_t> dist(0, UINT64_MAX);
  std::ostringstream oss;
  oss << "run_" << std::hex << dist(gen) << "_" << std::chrono::steady_clock::now().time_since_epoch().count();
  return oss.str();
}

}  // namespace

AsyncAgentManager::AsyncAgentManager(const config::Config& config, EventCallback callback)
    : config_(config), event_callback_(std::move(callback)) {}

AsyncAgentManager::~AsyncAgentManager() {
  std::lock_guard<std::mutex> lock(tasks_mutex_);
  for (auto& kv : tasks_) {
    kv.second->aborted = true;
    if (kv.second->worker.joinable()) {
      kv.second->worker.detach();
    }
  }
}

std::string AsyncAgentManager::start_task(const std::string& session_key, const std::string& message) {
  auto task = std::make_shared<AsyncTask>();
  task->run_id = generate_run_id();
  task->session_key = session_key;
  task->message = message;

  std::string run_id = task->run_id;

  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    tasks_[run_id] = task;
  }

  task->worker = std::thread(&AsyncAgentManager::run_task, this, task);

  return run_id;
}

bool AsyncAgentManager::abort_task(const std::string& run_id) {
  std::lock_guard<std::mutex> lock(tasks_mutex_);
  auto it = tasks_.find(run_id);
  if (it != tasks_.end()) {
    it->second->aborted = true;
    return true;
  }
  return false;
}

bool AsyncAgentManager::has_task(const std::string& run_id) const {
  std::lock_guard<std::mutex> lock(tasks_mutex_);
  return tasks_.find(run_id) != tasks_.end();
}

void AsyncAgentManager::run_task(std::shared_ptr<AsyncTask> task) {
  log::info("async_agent: starting task " + task->run_id);

  // 发送开始事件
  nlohmann::json start_payload;
  start_payload["sessionKey"] = task->session_key;
  start_payload["runId"] = task->run_id;
  start_payload["state"] = "started";
  send_event("chat", start_payload.dump());

  // 执行 agent
  agent::RunResult result;
  if (!task->aborted) {
    result = agent::run(config_, task->message, 0.7);
  }

  // 发送 agent 事件（简化：一次性发送完整内容）
  if (!task->aborted && result.ok) {
    nlohmann::json agent_payload;
    agent_payload["sessionKey"] = task->session_key;
    agent_payload["stream"] = "assistant";
    agent_payload["data"] = {{"text", result.content}};
    send_event("agent", agent_payload.dump());
  }

  // 发送完成事件
  nlohmann::json final_payload;
  final_payload["sessionKey"] = task->session_key;
  final_payload["runId"] = task->run_id;
  final_payload["state"] = task->aborted ? "aborted" : (result.ok ? "final" : "error");
  if (!result.ok && !task->aborted) {
    final_payload["error"] = result.error;
  }
  send_event("chat", final_payload.dump());

  // 清理任务
  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    tasks_.erase(task->run_id);
  }

  log::info("async_agent: completed task " + task->run_id);
}

void AsyncAgentManager::send_event(const std::string& event_name, const std::string& payload_json) {
  if (event_callback_) {
    event_callback_(event_name, payload_json);
  }
}

}  // namespace net
}  // namespace hiclaw
```

**Step 3: 修改 CMakeLists.txt 添加新源文件**

在 `CMakeLists.txt` 中找到 `src/net/gateway.cpp` 附近，添加：
```cmake
src/net/async_agent.cpp
```

**Step 4: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 5: 提交**

```bash
git add server/include/hiclaw/net/async_agent.hpp server/src/net/async_agent.cpp server/CMakeLists.txt
git commit -m "feat(gateway): add async agent manager for non-blocking chat"
```

---

### Task 5: 改造 gateway 支持异步事件推送

**Files:**
- Modify: `server/src/net/gateway.cpp`

**Step 1: 添加头文件和全局管理器**

在 gateway.cpp 顶部添加：
```cpp
#include "hiclaw/net/async_agent.hpp"
```

**Step 2: 修改 websocketpp 后端支持事件推送**

在 `run_wspp_server` 函数中：

1. 添加 AsyncAgentManager 实例
2. 创建事件推送回调函数
3. 实现 chat.send 和 chat.abort 方法

详细代码修改见 Task 5 的完整实现。

**Step 3: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 4: 提交**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat(gateway): integrate async agent manager with websocketpp"
```

---

### Task 6: 实现 chat.send 接口

**Files:**
- Modify: `server/src/net/gateway.cpp`

**Step 1: 在 gateway_handle_frame 中添加 chat.send 处理**

需要改造 gateway_handle_frame 函数签名，添加事件推送回调。

或者采用更简单的方式：在 websocketpp 的 message_handler 中直接处理 chat.send。

**Step 2: 实现 chat.send**

```cpp
  if (method == "chat.send") {
    std::string session_key = "main";
    std::string content = message;

    // 从 params 获取 sessionKey
    try {
      json j = json::parse(frame);
      if (j.contains("params") && j["params"].is_object()) {
        if (j["params"].contains("sessionKey")) {
          session_key = j["params"]["sessionKey"].get<std::string>();
        }
      }
    } catch (...) {}

    if (content.empty()) {
      json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = false;
      res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing content"}};
      return res.dump();
    }

    // 这里需要调用 AsyncAgentManager::start_task
    // 由于当前架构限制，需要重构 gateway_handle_frame
    // 暂时返回 stub 响应
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"runId", "stub_run_id"}, {"status", "queued"}};
    return res.dump();
  }
```

**Step 3: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 4: 提交**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat(gateway): add chat.send RPC endpoint (stub)"
```

---

### Task 7: 实现 chat.abort 接口

**Files:**
- Modify: `server/src/net/gateway.cpp`

**Step 1: 添加 chat.abort 方法处理**

```cpp
  if (method == "chat.abort") {
    std::string run_id;

    try {
      json j = json::parse(frame);
      if (j.contains("params") && j["params"].is_object()) {
        if (j["params"].contains("runId")) {
          run_id = j["params"]["runId"].get<std::string>();
        }
      }
    } catch (...) {}

    // 这里需要调用 AsyncAgentManager::abort_task
    // 暂时返回 stub 响应
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"aborted", !run_id.empty()}};
    return res.dump();
  }
```

**Step 2: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 3: 提交**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat(gateway): add chat.abort RPC endpoint"
```

---

### Task 8: 实现 node.event 和 node.invoke.result 接口

**Files:**
- Modify: `server/src/net/gateway.cpp`

**Step 1: 添加 node.event 方法处理**

```cpp
  if (method == "node.event") {
    // 客户端主动发送事件，暂时只记录日志
    log::info("gateway: received node.event: " + frame.substr(0, 200));

    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"received", true}};
    return res.dump();
  }
```

**Step 2: 添加 node.invoke.result 方法处理**

```cpp
  if (method == "node.invoke.result") {
    // 客户端返回 Tool Call 执行结果
    log::info("gateway: received node.invoke.result: " + frame.substr(0, 200));

    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"received", true}};
    return res.dump();
  }
```

**Step 3: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 4: 提交**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat(gateway): add node.event and node.invoke.result RPC endpoints"
```

---

## 阶段三：流式推送实现

### Task 9: 实现流式 Agent 回调

**Files:**
- Modify: `server/include/hiclaw/agent/agent.hpp`
- Modify: `server/src/agent/agent.cpp`

**Step 1: 添加流式回调接口**

在 agent.hpp 中添加：

```cpp
// 流式回调类型
using StreamCallback = std::function<void(const std::string& /*delta_text*/)>;

// 带流式回调的 run 函数
RunResult run_streaming(const config::Config& config,
                        const std::string& message,
                        float temperature,
                        StreamCallback callback);
```

**Step 2: 实现流式 run**

需要改造 HTTP 客户端支持 chunked 响应，这部分取决于 LLM provider 的 SSE 支持。

**Step 3: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 4: 提交**

```bash
git add server/include/hiclaw/agent/agent.hpp server/src/agent/agent.cpp
git commit -m "feat(agent): add streaming run with callback support"
```

---

### Task 10: 集成流式推送到 Gateway

**Files:**
- Modify: `server/src/net/gateway.cpp`
- Modify: `server/src/net/async_agent.cpp`

**Step 1: 修改 AsyncAgentManager 使用流式回调**

在 run_task 中，使用 agent::run_streaming 而非 agent::run，每次收到增量文本时推送 agent 事件。

**Step 2: 编译测试**

Run: `cd /mnt/d/projects/boji/server && ./scripts/build-linux-amd64.sh`
Expected: 编译成功

**Step 3: 提交**

```bash
git add server/src/net/gateway.cpp server/src/net/async_agent.cpp
git commit -m "feat(gateway): integrate streaming agent with event push"
```

---

## 验证测试

### Task 11: 集成测试

**Step 1: 启动 gateway 服务**

```bash
./build/linux-amd64/hiclaw gateway
```

**Step 2: 使用 wscat 测试连接**

```bash
wscat -c ws://localhost:8765
```

**Step 3: 测试各个接口**

```json
// 1. 连接
{"method": "connect", "id": "1", "params": {}}

// 2. health
{"method": "health", "id": "2"}

// 3. config.get
{"method": "config.get", "id": "3"}

// 4. chat.send
{"method": "chat.send", "id": "4", "params": {"sessionKey": "main", "content": "hello"}}

// 5. model status
{"method": "sessions.list", "id": "5"}
```

**Step 4: 确认所有接口返回正确响应**

---

## 依赖关系图

```
Task 1 (health) ─────────────────────────────────────────┐
Task 2 (config.get) ─────────────────────────────────────┤
Task 3 (voicewake) ──────────────────────────────────────┤
                                                         │
Task 4 (AsyncAgentManager) ──────────────────────────────┤
                    │                                    │
                    ▼                                    │
Task 5 (Gateway 集成) ───────────────────────────────────┤
                    │                                    │
                    ▼                                    │
Task 6 (chat.send) ──────────────────────────────────────┤
Task 7 (chat.abort) ─────────────────────────────────────┤
Task 8 (node.event/invoke.result) ───────────────────────┤
                                                         │
Task 9 (流式 Agent) ─────────────────────────────────────┤
                    │                                    │
                    ▼                                    │
Task 10 (流式推送集成) ──────────────────────────────────┤
                                                         │
                    ▼                                    │
Task 11 (集成测试) ◄─────────────────────────────────────┘
```

---

## 风险与注意事项

1. **线程安全**: AsyncAgentManager 需要正确处理多线程访问，使用 mutex 保护共享状态
2. **资源清理**: 确保任务完成后正确清理线程和资源
3. **错误处理**: 所有 RPC 接口都需要返回有意义的错误信息
4. **性能考虑**: 对于大量并发连接，可能需要使用线程池
5. **SSL/TLS 问题**: 当前 HTTP 客户端存在 SSL 握手问题，需要优先修复
