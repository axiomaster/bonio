# 微信集成：用手机指挥你的桌面 AI

> 你在地铁上，突然想起让家里的电脑帮你查个东西。掏出手机，打开微信，给 Bonio 发条消息——它就帮你办了。

---

## 场景：为什么需要微信集成？

Bonio 平时在电脑上陪你，但你不是一直坐在电脑前。以下场景每天都在发生：

- 通勤路上，想起来忘记给同事发某个文件
- 开会中，需要让电脑跑一个耗时的数据分析
- 躺床上，突然想搜个东西但懒得爬起来开电脑
- 出差在外，想知道家里的电脑是否正常运行

如果 Bonio 能通过微信接收指令，这些场景就全解决了。**手机微信是你随身携带的远程遥控器。**

Bonio 的微信集成支持两种通道：

| 通道 | 适用账号 | 协议 | 连接方式 |
|------|---------|------|---------|
| **企业微信（WeCom）** | 企业微信智能机器人 | WebSocket 长连接 | `wss://openws.work.weixin.qq.com` |
| **个人微信（ilink）** | 个人微信号 | HTTP 长轮询 | `https://ilinkai.weixin.qq.com` |

---

## 企业微信通道（WeCom）

这是推荐的方式，也是最稳定的通道。你只需要：

1. 在企业微信管理后台创建一个"智能机器人"
2. 获取 `bot_id` 和 `bot_secret`
3. 在 `hiclaw.json` 中配置：

```json
{
  "wechat": {
    "enabled": true,
    "mode": "wecom",
    "wecom": {
      "bot_id": "your_bot_id",
      "bot_secret": "your_bot_secret"
    },
    "allow_from": []
  }
}
```

启动 HiClaw gateway 后，服务器会自动连接企业微信的 WebSocket 网关。整个过程的架构如下：

```
你的手机微信
  │
  ▼
企业微信服务器
  │
  │ wss://openws.work.weixin.qq.com (WebSocket 长连接)
  │
  ▼
HiClaw (你电脑上的 Bonio 后端)
  │
  ├─ WeComWsClient: 接收 aibot_msg_callback
  ├─ WeChatAdapter: 鉴权 + 去重 + 调用 Agent
  └─ Agent: LLM 处理 → 工具调用 → 生成回复
  │
  ▼
WeComWsClient.reply(callback_req_id, content)
  │
  ▼
企业微信服务器 → 你的手机微信
```

### WebSocket 协议细节

WeCom 的协议基于自定义帧格式（非标准 WebSocket 消息）：

```json
// 订阅帧（建立连接后发送）
{"cmd":"aibot_subscribe", "headers":{"req_id":"sub_1"}, "body":{"bot_id":"...","secret":"..."}}

// 入站消息（用户给你发消息）
{"cmd":"aibot_msg_callback", "headers":{"req_id":"cb_xxx"}, "body":{
  "msgid": "msg_001",
  "chatid": "chat_xxx",
  "chattype": "single",
  "from": {"userid": "zhangsan"},
  "msgtype": "text",
  "text": {"content": "帮我把今天的笔记整理一下"}
}}

// 回复帧（Bonio 回复用户）
{"cmd":"aibot_respond_msg", "headers":{"req_id":"cb_xxx"}, "body":{
  "msgtype": "stream",
  "stream": {"id": "stream_1", "finish": true, "content": "好的，今天你记了3条笔记：..."}
}}
```

### 关键实现细节

- **心跳**：每 30s 发送 `{"cmd":"ping"}`，连续 2 次未收到 pong 则重连
- **重连**：指数退避（1s → 2s → 4s → ... → 30s max）
- **写锁**：所有 WebSocket 写操作受 mutex 保护（libhv 的 WebSocket 非线程安全）
- **分块回复**：超过 2000 字节的回复内容自动分块发送，每块等待 ACK（5s 超时）
- **线程模型**：WeCom 客户端在独立线程运行 libhv EventLoop，Agent 任务复用 AsyncAgentManager 的线程池

---

## 个人微信通道（ilink）

如果你没有企业微信，可以使用基于 ilink HTTP API 的个人微信通道：

```json
{
  "wechat": {
    "enabled": true,
    "mode": "weixin",
    "weixin": {
      "token": "your_ilink_token",
      "base_url": "https://ilinkai.weixin.qq.com"
    }
  }
}
```

ilink 使用 **HTTP 长轮询** 而非 WebSocket：

```
IlinkHttpClient
  ├─ get_updates() → 长轮询新消息（阻塞等待有消息或超时）
  ├─ send_message(user_id, content) → 回复用户（自动分块 3800 字符）
  └─ 维护 context_token（每个用户的会话上下文令牌）
```

消息分块自动处理：
- 回复内容超过 3800 字符自动分割
- 自动处理 `ret=-2`（微信侧 token 过期）并重试
- 每个用户的 `context_token` 持久化在状态目录中

---

## 消息流：从微信到 Agent 再回来

不管用哪个通道，消息进入 HiClaw 后的处理流程是一样的：

```
微信用户发送 "帮我查一下最近的天气"
  │
  ▼
WeChatAdapter.handle_message(msg_id, user_id, chat_id, chat_type, content, callback_req_id)
  │
  ├─ 鉴权：is_user_allowed(user_id)
  │   └─ allow_from 为空 → 允许所有用户
  │   └─ allow_from 非空 → 仅允许列表中用户
  │
  ├─ 去重：is_duplicate(msg_id)
  │   └─ 5 分钟内相同 msg_id → 跳过（微信可能重复推送）
  │
  ├─ 保存用户消息到 SessionStore
  │   └─ session_key = "wechat:wecom:{chat_id}:{user_id}"
  │
  ├─ AsyncAgentManager.start_task(session_key, message)
  │   └─ Agent 循环：LLM 调用 + 工具调用 + 结果处理
  │
  └─ 累积完整响应 → reply(context, full_content)
      └─ WeCom: reply(callback_req_id, content)
      └─ ilink: send_message(user_id, content)
```

### 设计考量

**为什么不流式回复？** 微信消息不支持 SSE 或流式文本。用户发一条消息，收到一条完整回复。所以 HiClaw 的 WeChatAdapter 等待 Agent 循环完全结束，累积完整的 AI 回复，再一次性发送。

**会话持久化。** 每个微信用户的对话历史都保存在 HiClaw 的 SessionStore 中（session key = `wechat:wecom:{chat_id}:{user_id}`）。这意味着多轮对话的上下文是连续的——你跟微信上的 Bonio 聊，跟桌面上的 Bonio 聊，**用的是同一个 AI 大脑**。

**用户鉴权。** 通过 `allow_from` 配置项控制谁能通过微信指挥你的 Bonio。留空表示允许所有人（适合单人使用场景），填写 user_id 列表则仅允许指定用户。

---

## 安全考量

把你的桌面 AI 暴露到微信上需要谨慎：

1. **只读 + 有限写操作。** 微信通道的 Agent 默认不会执行危险的本地工具（如 `shell`）。你可以在 `hiclaw.json` 中限制微信会话可用的工具集。

2. **鉴权白名单。** 不要让 `allow_from` 空着而没有任何防护。至少设置只有你自己能访问。

3. **日志审计。** HiClaw 的日志系统记录所有微信消息的 user_id、时间和内容摘要，你可以随时查看谁通过微信做了什么。

4. **验证码保护。** 未来计划：对敏感操作（如执行 shell 命令）要求微信端输入验证码确认。

---

## 两种通道怎么选？

| | WeCom | ilink |
|---|---|---|
| **需要什么** | 企业微信管理后台 + 智能机器人 | 个人微信号 + ilink API 权限 |
| **连接方式** | WebSocket（实时推送，省资源） | HTTP 长轮询（5-10s 延迟） |
| **稳定性** | 高，生产级 | 中，依赖第三方 API |
| **合规性** | 企业微信官方支持 | 非官方 API |
| **推荐场景** | 日常使用 | 没有企业微信时的备选 |

建议优先用 WeCom 通道。创建一个企业微信账号是免费的，智能机器人功能也不需要企业认证。

---

## 体验：这意味着什么？

Bonio 的微信集成把一个"桌面工具"变成了一个**随时随地的 AI 执行器**。以下是真实的体验场景：

> **场景一：通勤查东西**
> 你在地铁上刷手机，突然想起今天开会需要的那个数据表忘了提前打开。打开微信，给 Bonio 发："帮我把 D 盘 projects 目录下的 Q1 销售报告截个图发给我"。Bonio 在你的电脑上执行截图，通过微信把图片发回来。

> **场景二：远程启动任务**
> 你在咖啡馆用手机写文档，需要跑一个耗时 10 分钟的代码编译。微信告诉 Bonio："在电脑上编译 desktop 项目，完成后告诉我结果"。10 分钟后，微信收到一条消息："编译成功，产物在 build/windows/x64/runner/Release/。"

> **场景三：消息转发**
> 电脑上收到一封重要邮件，但你在外面。Bonio 可以（在获得许可的情况下）将邮件摘要通过微信推送给你，你决定怎么处理。

Bonio + 微信 = **桌面 AI 的远程遥控时代。**

---

*这是 Bonio 技术博客系列的最后一篇。希望这 10 篇文章让你了解了 Bonio 从底层协议到上层交互的完整设计。*
