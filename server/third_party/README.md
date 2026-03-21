# third_party 三方库

本目录下的依赖均需**将对应仓库 clone 到指定子目录**后再构建，不再使用 CMake FetchContent 自动下载。

在 **server 目录**下执行以下命令，一次性拉取所有依赖：

```bash
# CLI11（命令行解析）
git clone --depth 1 --branch v2.3.2 https://github.com/CLIUtils/CLI11.git third_party/CLI11

# spdlog（日志）
git clone --depth 1 --branch v1.14.0 https://github.com/gabime/spdlog.git third_party/spdlog

# nlohmann/json（JSON 解析与序列化）
git clone --depth 1 --branch v3.11.3 https://github.com/nlohmann/json.git third_party/nlohmann_json

# libhv（HTTP/HTTPS 客户端与服务端）
git clone --depth 1 --branch v1.3.3 https://github.com/ithewei/libhv.git third_party/libhv

# mbedTLS（HTTPS 支持，可选但推荐）
git clone --depth 1 --branch v3.6.2 https://github.com/Mbed-TLS/mbedtls.git third_party/mbedtls

# Asio + websocketpp（Gateway WebSocket 后端）
git clone --depth 1 --branch asio-1-28-0 https://github.com/chriskohlhoff/asio.git third_party/asio
git clone --depth 1 --branch 0.8.2 https://github.com/zaphoyd/websocketpp.git third_party/websocketpp

# linenoise-ng（交互式行编辑，已内置）
# 无需 clone，已包含在 third_party/linenoise-ng 中
```

## 依赖说明

| 目录 | 用途 | 必须 |
|------|------|------|
| CLI11 | 命令行参数解析 | 是 |
| spdlog | 日志 | 是 |
| nlohmann_json | JSON | 是 |
| libhv | HTTP 客户端/服务端 | 是 |
| mbedTLS | HTTPS 支持 | 推荐（不安装则仅支持 HTTP） |
| asio / websocketpp | Gateway WebSocket | 是 |
| linenoise-ng | 交互式行编辑 | 是（已内置） |

## HTTPS 支持

如果不克隆 mbedTLS，hiclaw 将只能访问 HTTP API，无法访问 HTTPS API（如 OpenAI、GLM 等）。

克隆 mbedTLS 后重新构建即可启用 HTTPS：
```bash
cd server
rm -rf build/linux-amd64  # 清理旧构建
./scripts/build-linux-amd64.sh
```

未 clone 的库在 CMake 配置时会报错并提示对应 clone 命令。
