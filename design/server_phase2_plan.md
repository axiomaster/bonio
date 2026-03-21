# HiClaw Server Phase 2 - 功能增强计划

## 当前状态总结

Phase 1 (核心功能) 已完成:
- 多轮对话 (run_streaming_with_history + SessionStore)
- 流式事件推送 (chat delta/final + agent assistant/tool)
- 本地工具执行循环 (shell, file_read, file_write, web_fetch, memory_*)
- 会话管理 (chat.history, sessions.list)
- 配置管理 (config.get, config.set)
- 异步任务管理 (chat.send async, chat.abort)

## Phase 2 功能规划

### 功能 1: 远程工具执行 - Agent 等待客户端工具结果

**问题**: 当前 agent 仅执行本地工具 (shell, file_read 等)。`ToolRouter` 已实现 (promise/future 模式)，gateway 已能接收 `node.invoke.result` 并路由到 `ToolRouter`。但 agent 从不调用 `register_tool_call()`，也不等待远程结果。

**目标**: 让 agent 能在工具目录中注册设备端工具 (如 `camera.snap`, `screen.capture`, `sms.read` 等)。当 LLM 请求调用这些工具时，agent 通过 gateway 发送 `node.invoke.request` 到客户端，等待 `node.invoke.result` 返回，将结果注入对话历史继续推理。

**实现要点**:

1. **工具分类**: 在 `tools::run_tool()` 中区分本地工具 vs 远程工具
   - 本地工具: `shell`, `file_read`, `file_write`, `web_fetch`, `memory_*`
   - 远程工具: `camera.snap`, `screen.capture`, `notification.list`, `sms.read`, `location.get` 等
   - 远程工具名前缀匹配 (如 `camera.*`, `screen.*`, `sms.*`, `location.*`)

2. **AsyncAgentManager 注入 ToolRouter**:
   - `AsyncAgentManager` 构造函数接收 `std::shared_ptr<ToolRouter>`
   - 工具回调中，对远程工具调用 `tool_router->register_tool_call(id)` 获取 future
   - 发送 `node.invoke.request` 事件给客户端
   - 使用 `future.wait_for(timeout)` 等待结果 (带30秒超时)
   - 将结果注入 messages_json 继续对话

3. **Agent 工具目录扩展**:
   - `tools_array()` 中添加设备端工具定义
   - 工具描述要清晰，让 LLM 知道何时使用

**文件变更**:
- `server/include/hiclaw/net/async_agent.hpp` - 添加 ToolRouter 引用
- `server/src/net/async_agent.cpp` - 工具执行时判断远程/本地，远程走 ToolRouter
- `server/src/net/gateway.cpp` - 传递 ToolRouter 给 AsyncAgentManager
- `server/src/agent/agent.cpp` - tools_array() 添加设备端工具定义
- `server/src/tools/tool.cpp` - 添加 `is_remote_tool()` 判断函数

---

### 功能 2: Session 管理增强

**问题**: `sessions.delete` 和 `sessions.reset` 未实现，客户端无法删除或清空会话历史。

**实现**:

1. **sessions.delete** - 删除指定 session
   - 参数: `{ sessionKey: string }`
   - 调用 `session_store->delete_session(key)`
   - 返回: `{ ok: true }`

2. **sessions.reset** - 清空 session 消息但保留 session
   - 参数: `{ sessionKey: string }`
   - 新增 `SessionStore::reset_session(key)` 方法
   - 返回: `{ ok: true }`

3. **sessions.patch** - 修改 session 元数据 (displayName)
   - 参数: `{ sessionKey: string, displayName?: string }`
   - 新增 `SessionStore::patch_session(key, display_name)` 方法

**文件变更**:
- `server/include/hiclaw/session/store.hpp` - 添加 reset_session, patch_session
- `server/src/session/store.cpp` - 实现
- `server/src/net/gateway.cpp` - 添加 RPC 处理

---

### 功能 3: System Prompt 支持

**问题**: 当前 agent 没有 system prompt，LLM 不知道自己是 "BoJi" 助手，也不了解自己的能力和可用工具。

**实现**:

1. 在 `config.json` 中支持 `system_prompt` 字段
2. `run_streaming_with_history()` 在 messages 数组最前面注入 system message
3. 默认 system prompt 描述 BoJi 的角色、能力、可用工具

**文件变更**:
- `server/include/hiclaw/config/config.hpp` - Config 添加 system_prompt 字段
- `server/src/config/config.cpp` - 加载/保存 system_prompt
- `server/src/agent/agent.cpp` - messages 头部注入 system message
- `server/conf/config.json.example` - 示例配置

---

### 功能 4: 并发安全与 SessionStore 线程安全

**问题**: `SessionStore` 内部使用 `std::vector<Session>` 无锁保护。多个 WebSocket 连接共享同一个 `SessionStore` 实例时，并发读写会导致数据竞争。

**实现**:

1. `SessionStore` 添加 `std::mutex` 保护所有读写操作
2. `save()` 操作异步化，避免阻塞工具线程

**文件变更**:
- `server/include/hiclaw/session/store.hpp` - 添加 mutex
- `server/src/session/store.cpp` - 所有方法加锁

---

### 功能 5: libwebsockets 后端功能对齐

**问题**: libwebsockets 后端仅支持同步 `gateway_handle_frame`，不支持 async agent、session store、config.set 等 websocketpp 独有功能。Android NDK 构建使用 websocketpp，所以暂不紧急。

**优先级**: 低 (仅当需要 libwebsockets 平台支持时)

---

## 优先级排序

| 功能 | 优先级 | 理由 |
|------|--------|------|
| 功能 3: System Prompt | **P0** | 影响 LLM 输出质量，无此功能 agent 没有人设 |
| 功能 4: SessionStore 线程安全 | **P0** | 并发 bug 会导致崩溃/数据损坏 |
| 功能 2: Session 管理增强 | **P1** | 客户端需要删除/重置会话 |
| 功能 1: 远程工具执行 | **P2** | 需要客户端配合，可分阶段推进 |
| 功能 5: LWS 对齐 | **P3** | 当前不紧急 |

## 建议执行顺序

1. 功能 3 (System Prompt) + 功能 4 (线程安全) — 同时进行，互不依赖
2. 功能 2 (Session 管理) — 简单增量
3. 功能 1 (远程工具) — 最复杂，需客户端配合测试
