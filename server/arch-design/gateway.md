关于 OpenClaw Gateway 的网络架构，我已经查阅了源码（包括 src/gateway/server.impl.ts, server-http.ts 和 server-runtime-state.ts）。

实际的情况更接近于你的 第二种猜测（Q2），但也有一点细微的差别。具体来说：

1. 端口与服务器架构
启动 Gateway 之后，它同时启动了 HTTP Server 和 WebSocket Server，并且它们共享同一个 18789 端口。

OpenClaw 在 18789 端口上监听一个标准的 HTTP 服务器。
当客户端发起普通的 HTTP 请求（例如 GET /health 或者获取 UI 静态文件）时，由 HTTP 路由正常处理。
当客户端发起带有 Upgrade: websocket 升级请求头的 HTTP 请求时，网关会拦截这个连接升级事件（相关代码在 attachGatewayUpgradeHandler），并将这个底层 Socket 平滑转交给 WebSocket Server 处理。
2. 客户端的通信方式
浏览器、命令行 (CLI) 工具、Android 或 Mac 客户端并不是单一地全部走 WebSocket 或全部走 HTTP，而是混合使用：

浏览器 (Web UI)： 浏览器首页加载主要是通过 HTTP 访问 18789 端口来获取所有的 HTML、CSS、JS 静态资源、头像图片，也承载着一些像 /v1/chat/completions (OpenAI 兼容接口) 这样的 REST API。但在 Web UI 载入完成后，为了实现聊天流的实时互推与状态同步，前端的 Web 应用也会向这个 18789 端口发起 WebSocket 连接。

Android / Mac / CLI 等系统级客户端： 主要作为集群内部的通信节点（Nodes），心跳维持、RPC 方法调用、系统控制指令以及实时聊天流都是通过持久化的 WebSocket 建立双向通信连接（连接的是同一个 18789 端口）。但在某些需要传输大体积外部资源、文件上传下载、探活，或是第三方 Webhook 回调接入等特殊场景下，也会使用到 18789 端口的 HTTP 接口。

结论总结
你不需要将 18789 单纯理解为 "纯 WebSocket 专属端口" 或是启动了两个监听不同端口的服务。18789 兼顾了 HTTP 协议和 WebSocket 协议服务，底层的分发路由逻辑会根据请求动态派发：

实时、双向通讯的需求（节点间的互通、聊天推送、终端控制）都会升级到 WebSocket 层。
无状态请求、静态资源分发、第三方 API 或者 Webhook 接入则保留在普通的 HTTP 层。