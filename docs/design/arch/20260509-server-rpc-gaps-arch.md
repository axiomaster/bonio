# BoJi 客户端与 HiClaw 服务端功能完成情况审计报告 (更新版)

## 1. 总体进度概览

目前项目已经取得了重大进展。服务端（HiClaw）已经基本完成了从“同步阻塞”向“异步事件驱动”架构的转型，Android 和 HarmonyOS 客户端的核心连通性问题已解决。

### 核心功能状态对照表

| 功能模块 | Android 客户端 | HarmonyOS 客户端 | HiClaw 服务端 | 状态说明 |
| :--- | :---: | :---: | :---: | :--- |
| **基础连接 (WebSocket)** | ✅ 已完成 | ✅ 已完成 | ✅ 已完成 | 支持鉴权与 Challenge 机制。 |
| **状态探活 (health)** | ✅ 已完成 | ✅ 已完成 | ✅ 已完成 | **(新)** 解决了之前 Offline 报错问题。 |
| **异步对话 (chat.send)** | ✅ 已完成 | ✅ 已完成 | ✅ 已完成 | **(新)** 支持异步返回 runId。 |
| **文字流式输出** | ✅ 已完成 | ✅ 已完成 | ✅ 已完成 | **(新)** 支持推送 assistant 事件。 |
| **悬浮窗模式** | ✅ 已验证 | 🟡 开发中 | N/A | HarmonyOS 已建立 FloatWindowManager 框架。 |
| **语音唤醒开关** | N/A | ✅ 已完成 | ✅ 已完成 | **(新)** 已通。 |
| **工具调用 (Streaming)** | ✅ 协议支持 | ✅ 协议支持 | ❌ 未实现 | **(剩余缺口)** SSE 尚未解析 tool_calls。 |
| **会话历史与列表** | ✅ 协议支持 | ✅ 协议支持 | 🟡 仅 Stub | 目前服务端返回硬编码的空列表。 |

---

## 2. 服务端 (HiClaw Server) 详细分析

### 已完成的改进 ✅
*   **RPC 方法扩展**：`health`, `config.get`, `voicewake.get`, `voicewake.set` 已全部实现。
*   **AsyncAgentManager 架构**：成功引入了多线程异步任务管理，支持 `run_id` 追踪。
*   **事件推送机制**：基于 `websocketpp` 和 `io_service.post` 实现了安全的事件下发缓存。

### 剩余待办事项 (TODO) 🛠️
1.  **流式工具调用支持 (Streaming Tool Calls)**:
    *   **现状**: `agent.cpp` 中的 `process_sse_line` 仅提取了 `delta.content`。
    *   **需求**: 需要解析 SSE 流中的 `tool_calls` 数组，并通过 `agent` (stream: "tool") 事件推送给客户端。
2.  **持久化存储**:
    *   **chat.history**: 需要对接数据库或文件系统，返回真实的历史消息。
    *   **sessions.list**: 需要返回真实的会话列表，而非硬编码的 `main`。
3.  **RPC 补齐**:
    *   `node.event` 和 `node.invoke.result` 目前只有日志，需要对接具体的后端逻辑。

---

## 3. 客户端完成情况分析

### Android 客户端
*   **状态**: 生产就绪。已处理了 `health` 方法不支持时的容错，确保了在各种服务端环境下的可用性。
*   **改进空间**: 配合服务端实现真实的会话管理（多轮对话持久化）。

### HarmonyOS 客户端
*   **状态**: 快速追赶中。
*   **新增内容**: 发现了 `FloatWindowManager.ets`。这意味着 HarmonyOS 版的“猫猫悬浮窗”已经完成了底层窗口创建、透明背景设置和页面加载逻辑。
*   **下一步**: 需要在 `EntryAbility` 或主页面触发悬浮窗的开启。

---

## 4. 下一步行动建议

1.  **服务端增强**: 建议优先根据报告中的第 2 点，增强 `agent.cpp` 的 SSE 解析逻辑，以支持工具调用（Tool Calls）的转发。
2.  **数据落盘**: 考虑为服务端引入简单的 SQLite 或 JSON 文件持久化，让 `chat.history` 不再是“每次重启就清空”。
3.  **HarmonyOS 悬浮窗联动**: 测试 `FloatWindowManager` 的实际显示效果，并与应用进入后台的生命周期联动。
