# 后端架构：HiClaw 与 OpenClaw 双引擎

> 一个协议，两种引擎。从零依赖的 C++ 微服务到社区驱动的 Node.js 生态，Bonio 的后端设计兼顾了自托管的极简与大平台的便利。

---

## 为什么需要后端？

有人会问：桌面应用为什么不能直接调 LLM API？答案是：**Agent 循环需要一个持久运行的"大脑"**。

一次典型的 AI Agent 对话不是一问一答，而是一个循环：

```
用户消息 → LLM 分析 → 决定调用工具 → 客户端执行工具 → 结果返回 LLM
→ LLM 再分析 → 再调用工具 → …… → 最终生成回复
```

这个循环可能持续几十轮，涉及多次 LLM 调用和工具执行。如果客户端直接做这件事，切换网络、关闭应用都会打断 Agent 的思考。**后端的存在，让 Agent 循环在服务器上持续运行，客户端只管收发结果。**

---

## 双引擎策略

Bonio 支持连接两种后端：

| | **HiClaw** | **OpenClaw** |
|---|---|---|
| **语言** | C++17 | Node.js / TypeScript |
| **编译产物** | 单个可执行文件 (~15MB) | npm 包 + Node 运行时 |
| **部署复杂度** | 零依赖，拷贝即运行 | 需要 Node.js 环境 |
| **协议** | v3 WebSocket | v3 WebSocket（相同协议） |
| **Skill 系统** | ✅ 支持 | ❌ |
| **Provider 系统** | ✅ 内置 ollama + openai_compatible | ✅ 不同机制 |
| **微信集成** | ✅ WeCom + ilink | ❌ |
| **Cron 定时任务** | ✅ 5 字段 cron | ❌ |
| **Memory 系统** | ✅ 文件记忆 | ❌ |
| **目标用户** | 追求性能与自托管的个人用户 | 连接公共网关的用户 |

**客户端不关心后端是谁。** 两者使用完全相同的 WebSocket 协议——帧格式、RPC 方法名、事件类型全部一致。你可以在 `hiclaw` 和 `openclaw` 之间切换，桌面端零改动。

---

## HiClaw 架构深度解析

HiClaw 是 Bonio 的自研后端，也是整个项目最"硬核"的部分。它用了 **C++17**，这不是为了炫技，而是为了实现"**编译出来就是一个文件，拷贝到任何机器上都直接跑**"的部署体验。

### 整体分层

```
┌─────────────────────────────────────────────────────────┐
│                    WebSocket Server                      │
│                  (libhv / websocketpp)                    │
├─────────────────────────────────────────────────────────┤
│            Gateway —— RPC 路由 + 事件广播                │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐     │
│  │ 认证层    │  │ 方法调度  │  │ 广播 (agent/chat/  │     │
│  │ connect  │  │ dispatch │  │  avatar.command)   │     │
│  └──────────┘  └──────────┘  └────────────────────┘     │
├─────────────────────────────────────────────────────────┤
│                    业务处理层                             │
│  ┌────────────┐  ┌──────────┐  ┌──────────────────┐    │
│  │AsyncAgent  │  │ToolRouter│  │ 子系统们           │    │
│  │Manager     │  │          │  │ IntentRouter     │    │
│  │(Agent循环)  │  │(工具路由) │  │ CallHandler      │    │
│  │            │  │          │  │ IdleManager      │    │
│  │            │  │          │  │ HealthMonitor    │    │
│  └────────────┘  └──────────┘  └──────────────────┘    │
├─────────────────────────────────────────────────────────┤
│                    数据与扩展层                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐  │
│  │ Session  │  │ Memory   │  │ Cron     │  │ Skill  │  │
│  │ Store    │  │ Store    │  │ Scheduler│  │Manager │  │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘  │
├─────────────────────────────────────────────────────────┤
│                    Provider 抽象层                       │
│  ┌──────────┐  ┌──────────────────────┐                 │
│  │  Ollama  │  │  OpenAI Compatible   │  (可扩展...)    │
│  └──────────┘  └──────────────────────┘                 │
└─────────────────────────────────────────────────────────┘
```

### Gateway：双会话模型

Gateway 是 HiClaw 的入口。每个客户端与服务端维持 **两条 WebSocket 连接**：

| 会话 | 方向 | 用途 |
|------|------|------|
| `operatorSession` | 客户端 → 服务端 | 用户主动操作：聊天、配置管理、会话管理 |
| `nodeSession` | 服务端 → 客户端 | 服务端指令：工具调用（截图、相机、定位等） |

这种"双通道"设计解决了 AI Agent 的一个核心矛盾：**用户发起的交互和服务端发起的工具调用需要不同的优先级和生命周期。** 当 AI 决定调用一个工具时，它通过 `nodeSession` 下发指令，客户端执行后通过同一个通道返回结果。而用户的聊天消息始终走 `operatorSession`，两条线互不阻塞。

### Provider 系统：一套接口，多个 LLM

HiClaw 通过 Provider 抽象层支持多种 LLM 后端。每个 Provider 实现相同的接口：

```cpp
// Provider 接口（简化）
class Provider {
  virtual std::string chat(const ChatRequest& req) = 0;       // 同步调用
  virtual void chat_stream(const ChatRequest& req, Callback cb) = 0;  // 流式调用
  virtual std::vector<ModelInfo> list_models() = 0;
};
```

当前内置两个 Provider：

- **Ollama**：连接本地 Ollama 实例，支持所有 Ollama 模型（Gemma、Llama、Qwen 等）
- **OpenAI Compatible**：兼容 OpenAI API 格式的任何服务（智谱 GLM、DeepSeek、通义千问、以及各种第三方代理）

添加新 Provider 只需实现接口并在配置中注册，不需要改动 Agent 循环或 Gateway 的任何代码。

### Skill 系统：给 AI 装插件

Skill 是 HiClaw 的一个独特能力。一个 Skill 就是一个 `SKILL.md` 文件，包含：

- **元数据**：名称、描述、版本
- **系统提示词**：注入到 LLM 的 system prompt 中
- **工具定义**：Skill 可以注册自定义工具
- **触发条件**：什么情况下应该激活这个 Skill

Skill 可以动态安装、启用、禁用，无需重启服务。它本质上是一种**运行时 prompt engineering**——通过注入不同的系统提示词和工具，让同一个 LLM 表现出不同的专业能力。

### Cron 定时任务

HiClaw 内置了一个 5 字段 cron 表达式解析器和持久化调度器：

```
分钟 小时 日 月 星期
 *   *   *  *   *
```

支持通配符、枚举、范围和步进（`*/5` 表示每 5 个单位）。定时任务配置在 `hiclaw.json` 中，持久化存储在 config 目录下。这允许 AI 在用户设定的时间主动执行任务——比如每天早上 9 点自动总结昨天的笔记。

### 会话持久化

HiClaw 将所有聊天历史持久化为文件（基于 session key）。重启服务后，对话不会丢失。会话管理支持 `list`、`delete`、`reset`、`patch` 操作，客户端可以完整管理用户的对话历史。

---

## 协议层：客户端看到了什么

无论后端是 HiClaw 还是 OpenClaw，客户端看到的都是同一套 v3 WebSocket 协议。帧格式统一为：

```json
{
  "type": "req",
  "method": "chat.send",
  "id": "req-001",
  "params": { "message": { "role": "user", "content": "..." } }
}
```

三种帧类型：

| type | 方向 | 用途 |
|------|------|------|
| `req` | 客户端→服务端 | RPC 请求（需要响应） |
| `res` | 服务端→客户端 | RPC 响应 |
| `event` | 服务端→客户端 | 服务端推送（不需响应） |

核心 RPC 方法：

| 方法 | 说明 |
|------|------|
| `connect` | 认证（Ed25519 签名 + 可选 token/password） |
| `config.get` / `config.set` | 配置读写 |
| `chat.send` / `chat.abort` | 聊天消息与中断 |
| `skills.list` / `skills.install` / `skills.enable` | Skill 管理 |
| `sessions.list` / `sessions.delete` / `sessions.patch` | 会话管理 |
| `node.invoke.result` | 客户端返回工具执行结果 |

核心事件（服务端主动推送）：

| 事件 | 说明 |
|------|------|
| `agent` | LLM 流式增量（文本或 tool_call） |
| `chat` | 聊天状态更新（开始、完成、错误） |
| `node.invoke.request` | 要求客户端执行工具 |
| `avatar.command` | 控制 Avatar 动画 |
| `tick` | 30s 心跳 |

---

## 为什么自己写后端

这是个合理的问题。市面上有 OpenAI API、有 LangChain、有各种 Agent 框架——为什么还要用 C++ 从头写一个？

1. **零依赖部署。** 我们不想让用户装 Python、装 Node.js、配虚拟环境。一个 exe，双击启动。这对 Windows 用户尤为重要。
2. **完全控制 Agent 循环。** 市面上的 Agent 框架封装了太多"魔法"，出了问题难以调试。HiClaw 的 Agent 循环不到 500 行，逻辑透明。
3. **协议层自主。** 通过设计自己的 WebSocket 协议，我们可以精细控制客户端-服务端的通信模式（双会话、流式事件、Avatar 指令），不必受限于现有框架的设计假设。
4. **学习价值。** HiClaw 本身是一个很好的 C++ 工程实践——CMake 构建、第三方库管理、WebSocket 编程、LLM 集成——这些经验本身就是资产。

---

*下一篇：[插件系统：Bonio 的无限扩展能力](04-plugin-system-overview.md)*
