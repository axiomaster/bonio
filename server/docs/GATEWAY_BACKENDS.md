# Gateway 双后端说明（HarmonyOS 优先）

## 策略

- **HarmonyOS（OHOS）**：默认且优先使用 **websocketpp**，与鸿蒙生态一致，无需系统预装 LWS。
- **主机（Windows/Linux）**：`HICLAW_GATEWAY_BACKEND=auto` 时，若已安装 libwebsockets 则用 LWS，否则用 websocketpp（FetchContent 拉取）。

## 构建选项

```bash
# 默认（OHOS 用 websocketpp，主机自动选）
cmake -B build -DHICLAW_GATEWAY_BACKEND=auto

# 强制 websocketpp（推荐在 OHOS 上验证）
cmake -B build -DHICLAW_GATEWAY_BACKEND=websocketpp

# 强制 libwebsockets（需已安装 LWS）
cmake -B build -DHICLAW_GATEWAY_BACKEND=libwebsockets
```

## 依赖

- **websocketpp**：FetchContent 拉取 [zaphoyd/websocketpp](https://github.com/zaphoyd/websocketpp) 0.8.2 与 [chriskohlhoff/asio](https://github.com/chriskohlhoff/asio)（standalone，无 Boost）。首次配置需网络。
- **libwebsockets**：需系统或工具链中已安装，见 `cmake/FindLibWebSockets.cmake`。历史记录见 [deps-libwebsockets.md](deps-libwebsockets.md)。

## 优先在 HarmonyOS 上测试

1. 使用 OHOS 工具链配置时，未显式指定 backend 即使用 websocketpp。
2. 编译：`ninja -C build-ohos`。
3. 推送设备后运行：`hiclaw gateway --new-pairing` 或 `hiclaw gateway --port 18789`，客户端用配对码或 token 连接即可。
