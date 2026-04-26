# 计划：为 hiclaw 添加微信对接功能

## 背景

参考 `reference/cc-connect`（Go 项目）的实现，为 hiclaw C++ server 添加微信通道支持。cc-connect 支持两种微信模式：

1. **企业微信（WeCom）WebSocket 模式**（推荐）：连接 `wss://openws.work.weixin.qq.com`，无需公网 IP，无需消息加解密，配置最简单
2. **个人微信（WeiXin）ilink 模式**：使用 ilink HTTP 网关长轮询，无需公网 IP

**本计划优先实现 WeCom WebSocket 模式**，ilink 模式作为后续可选扩展。

## 架构设计

### 消息流

```
微信用户发送消息
  → 企业微信服务器
  → hiclaw WeComWsClient 收到 aibot_msg_callback
  → WeChatAdapter 鉴权 + 去重
  → 保存用户消息到 SessionStore (session_key = "wechat:wecom:{chatID}:{userID}")
  → AsyncAgentManager 启动 agent task（无 ToolRouter，仅本地工具）
  → Agent 循环：LLM 调用 + 本地工具
  → 累积完整响应（微信不支持流式）
  → 通过 WeComWsClient 发送 aibot_respond_msg 回复用户
```

### WeCom WebSocket 帧协议

**帧格式**：
```json
{"cmd":"...","headers":{"req_id":"..."},"body":{...},"errcode":0,"errmsg":"ok"}
```

**订阅帧**：
```json
{"cmd":"aibot_subscribe","headers":{"req_id":"aibot_subscribe_1"},"body":{"bot_id":"...","secret":"..."}}
```

**心跳帧**：每 30s 发送 `{"cmd":"ping","headers":{"req_id":"ping_N"}}`，连续 2 次未收到 pong 则重连

**入站消息**（`cmd: "aibot_msg_callback"`）：
```json
{
  "body": {
    "msgid": "...", "chatid": "...", "chattype": "single|group",
    "from": {"userid": "..."},
    "msgtype": "text|voice|image|file|mixed",
    "text": {"content": "..."}
  }
}
```

**回复帧**（`aibot_respond_msg`）：
```json
{"cmd":"aibot_respond_msg","headers":{"req_id":"callback原始req_id"},"body":{"msgtype":"stream","stream":{"id":"stream_1","finish":true,"content":"回复内容"}}}
```

**主动发送帧**（`aibot_send_msg`）：
```json
{"cmd":"aibot_send_msg","headers":{"req_id":"aibot_send_msg_N"},"body":{"chatid":"...","msgtype":"markdown","markdown":{"content":"..."}}}
```

### 技术选型

- **WebSocket 客户端**：使用 libhv 的 `WebSocketClient`（已 vendored，已有 TLS/mbedtls 集成，内置重连支持）
- **HTTP 客户端**：复用现有 `http_client.cpp` 的 libhv HTTP 功能（ilink 模式用）
- **线程模型**：WeChatAdapter 在独立线程运行 libhv EventLoop，agent task 复用 AsyncAgentManager 的线程池模式

## 实现步骤

### 步骤 1：配置结构

**修改** `server/include/hiclaw/config/config.hpp`

在 `Config` 结构体中添加：

```cpp
struct WeChatConfig {
  bool enabled = false;
  std::string mode;  // "wecom" 或 "weixin"

  struct WeComConfig {
    std::string bot_id;
    std::string bot_secret;
  } wecom;

  struct WeiXinConfig {
    std::string token;
    std::string base_url = "https://ilinkai.weixin.qq.com";
    std::string cdn_base_url = "https://novac2c.cdn.weixin.qq.com/c2c";
  } weixin;

  std::vector<std::string> allow_from;
} wechat;
```

**修改** `server/src/config/config.cpp`

在 `loadFromJson` 中解析 `wechat` 节点，在序列化中写出。示例配置：

```json
{
  "wechat": {
    "enabled": true,
    "mode": "wecom",
    "wecom": { "bot_id": "xxx", "bot_secret": "xxx" },
    "allow_from": ["zhangsan"]
  }
}
```

### 步骤 2：WeCom WebSocket 客户端

**新建** `server/include/hiclaw/net/wecom_ws_client.hpp`
**新建** `server/src/net/wecom_ws_client.cpp`

`WecomWsClient` 类：

```
WecomWsClient(bot_id, bot_secret)
  ├─ run(on_message_callback) → 阻塞运行，返回错误信息
  │   ├─ 连接 wss://openws.work.weixin.qq.com
  │   ├─ 发送 aibot_subscribe 帧
  │   ├─ 启动 30s 心跳定时器
  │   ├─ 读取循环：解析帧，分发消息
  │   └─ 断线后指数退避重连 (1s→2s→4s→...→30s max)
  ├─ stop() → 停止运行
  ├─ reply(req_id, content) → 发送 aibot_respond_msg
  └─ send(chat_id, content) → 发送 aibot_send_msg
```

消息回调签名：`void(msg_id, user_id, chat_id, chat_type, content, callback_req_id)`

关键实现细节：
- 使用 `hv::WebSocketClient` 连接 wss://
- 写操作用 mutex 保护（WebSocket 不是线程安全的）
- 回复内容按 2000 字节分块，每块等待 ACK（5s 超时）
- req_id 格式：`{prefix}_{递增序号}`

### 步骤 3：WeChat 适配器

**新建** `server/include/hiclaw/net/wechat_adapter.hpp`
**新建** `server/src/net/wechat_adapter.cpp`

`WeChatAdapter` 类：

```
WeChatAdapter(config)
  ├─ start() → 根据 mode 启动 wecom 或 weixin 循环
  ├─ stop()  → 停止
  ├─ 内部组件：
  │   ├─ SessionStore（共享，session key: "wechat:wecom:{chatid}:{userid}"）
  │   ├─ AsyncAgentManager（ToolRouter=nullptr，仅本地工具）
  │   └─ 消息去重缓存（msgid → timestamp，5min TTL）
  └─ 事件回调：
      ├─ 忽略 delta 事件
      ├─ final 事件 → send_wecom_reply()
      └─ error 事件 → 发送 "[Error] ..." 给用户
```

核心流程 `dispatch_to_agent(session_key, user_id, message, reply_ctx)`：
1. 检查 `allow_from`，空则允许所有
2. 去重检查
3. 保存用户消息到 SessionStore
4. 调用 `agent_manager_->start_task(session_key, message)`
5. event_callback 捕获 final 内容，调用 `send_wecom_reply()`

### 步骤 4：网关集成

**修改** `server/src/net/gateway.cpp`

在 `run_wspp_server()` 中（`server.run()` 之前），添加 WeChat 适配器启动：

```cpp
std::unique_ptr<WeChatAdapter> wechat_adapter;
if (config.wechat.enabled) {
  wechat_adapter = std::make_unique<WeChatAdapter>(config);
  std::thread([&]() { wechat_adapter->start(); }).detach();
}
```

在 gateway server 关闭时，调用 `wechat_adapter->stop()`。

### 步骤 5：CLI 命令

**修改** `server/src/cli/cli.cpp` 和 `server/include/hiclaw/cli/cli.hpp`

添加 `wechat` 子命令和 `setup` 子子命令：
- `hiclaw wechat setup` — 打印企业微信智能机器人创建指引和配置示例

### 步骤 6：CMake 构建

**修改** `server/CMakeLists.txt`

在 `HICLAW_SOURCES` 中添加：
```
src/net/wecom_ws_client.cpp
src/net/wechat_adapter.cpp
```

## 修改文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `server/include/hiclaw/config/config.hpp` | 修改 | 添加 WeChatConfig 结构体 |
| `server/src/config/config.cpp` | 修改 | 解析/序列化 wechat 配置 |
| `server/include/hiclaw/net/wecom_ws_client.hpp` | 新建 | WeCom WS 客户端接口 |
| `server/src/net/wecom_ws_client.cpp` | 新建 | WeCom WS 协议实现 |
| `server/include/hiclaw/net/wechat_adapter.hpp` | 新建 | 适配器接口 |
| `server/src/net/wechat_adapter.cpp` | 新建 | 消息编排逻辑 |
| `server/src/net/gateway.cpp` | 修改 | 启动/停止 WeChatAdapter |
| `server/src/cli/cli.cpp` | 修改 | 添加 wechat 子命令 |
| `server/include/hiclaw/cli/cli.hpp` | 修改 | 添加 Options 字段 |
| `server/CMakeLists.txt` | 修改 | 添加新源文件 |

## 验证

1. **编译**：`cd server && scripts\build-win-amd64.bat` 确保编译通过
2. **无配置启动**：`hiclaw gateway` 无 wechat 配置时应正常启动，不加载微信
3. **有配置启动**：配置 wechat 后启动，日志应显示 `WeChatAdapter: connecting to wss://openws.work.weixin.qq.com`
4. **实际测试**：
   - 创建企业微信智能机器人，获取 bot_id 和 bot_secret
   - 配置到 `hiclaw.json`
   - 启动 hiclaw gateway
   - 在企业微信中给机器人发消息
   - 验证机器人回复
   - 验证多轮对话（session 持久化）
   - 验证 allow_from 鉴权
   - 验证断线重连

## 后续扩展（本次不实现）

- 个人微信 ilink 模式（`weixin_http_client.hpp/cpp`）
- 图片/语音/文件消息处理
- 打字指示器（typing indicator）
- 流式回复预览
- `/new`、`/model` 等聊天命令
