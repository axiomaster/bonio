# 依赖记录：libwebsockets（Gateway 后端之一）

本文档记录 HiClaw gateway 曾使用 **libwebsockets (LWS)** 作为 WebSocket 服务端实现的配置，便于回溯与对比。

## 使用时段与方式

- **使用方式**：通过 CMake `find_package(LibWebSockets)` 查找系统或工具链中的 libwebsockets，未在仓库内固定版本或 vendored。
- **代码位置**：`hiclaw/src/net/gateway.cpp` 中通过 `HICLAW_USE_LIBWEBSOCKETS` 宏启用 LWS 实现；`hiclaw/cmake/FindLibWebSockets.cmake` 提供查找脚本。
- **能力**：完成 WebSocket 握手、帧收发；协议逻辑（connect.challenge、connect、agent.run、chat.history、sessions.list）在 gateway 内统一实现。

## 版本与平台说明

- **未固定版本**：未在项目中记录具体 LWS 版本号，以各环境 `find_package` 得到的结果为准。
- **HarmonyOS**：LWS 非鸿蒙官方三方库，需自行用 OHOS NDK 交叉编译后提供；官方生态更常用 websocketpp。

## 当前策略（两套保留）

Gateway 现支持双后端，**优先在 HarmonyOS 上使用 websocketpp**，主机/其他平台可选用 LWS 或 websocketpp：

- **websocketpp**：头文件库 + Asio（standalone），与 OpenHarmony 生态一致，优先在 OHOS 构建中启用。
- **libwebsockets**：保留为可选后端，CMake 可选或自动回退；构建/运行时可选择其一。

详见根目录 README 与 `hiclaw/CMakeLists.txt` 中的 `HICLAW_GATEWAY_BACKEND` 及后端选择逻辑。
