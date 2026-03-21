# hiClaw 移植计划：ZeroClaw (Rust) → C++ / HarmonyOS

本文档根据 `README.md` 中的目标，制定将 **zeroclaw** 从 Rust 移植到 C++、并面向 **HarmonyOS 移动设备** 运行的详细计划。移植后的项目命名为 **hiClaw**。参考代码位于 `reference/` 目录，移植过程中**不得修改** reference 下任何代码。

---

## 一、项目概述与目标

| 项目 | 说明 |
|------|------|
| **源项目** | zeroclaw（Rust，位于 `reference/zeroclaw`） |
| **目标项目** | hiClaw（C++） |
| **运行平台** | HarmonyOS 移动设备 |
| **编译工具** | `D:\tools\commandline-tools-windows`（HarmonyOS 命令行工具 / NDK） |
| **验证方式** | 使用 `hdc file send` 将 hiClaw 推送到设备 `/data/local/bin`，通过 `hdc shell` 验证编译与运行 |

---

## 二、参考项目 (zeroclaw) 架构摘要

### 2.1 顶层模块（main.rs / lib.rs）

- **agent** — Agent 核心（Agent/AgentBuilder、对话循环）
- **approval** — 审批流程
- **auth** — 认证
- **channels** — 多通道（Telegram、Discord、Slack、Matrix、Lark、Email 等）
- **config** — 配置（schema、traits）
- **coordination** — 协调
- **cost** — 成本统计
- **cron** — 定时任务调度
- **daemon** — 守护进程
- **doctor** — 健康检查
- **gateway** — HTTP 网关
- **goals** — 目标管理
- **hardware** — 硬件相关
- **health** — 健康状态
- **heartbeat** — 心跳
- **hooks** — 钩子
- **identity** — 身份
- **integrations** — 集成
- **memory** — 记忆（SQLite/向量/Postgres 等）
- **migration** — 迁移
- **multimodal** — 多模态
- **observability** — 可观测性（日志、Prometheus、OTEL）
- **onboard** — 引导/向导
- **peripherals** — 外设（串口、Arduino、RPi 等）
- **plugins** — 插件（发现、加载、WASM 运行时等）
- **providers** — LLM 提供商（OpenAI、Anthropic、Ollama、Gemini、OpenRouter 等）
- **rag** — RAG
- **runtime** — 运行时（Docker、Native、WASM）
- **security** — 安全（沙箱、Landlock、密钥、策略等）
- **service** — 服务管理
- **skillforge** — Skill 发现与集成
- **skills** — Skill 与 Tool 处理（templates、tool_handler、audit）
- **tools** — 大量内置工具（shell、file_read/write、http_request、cron_*、memory_*、mcp_*、sop_* 等）
- **tunnel** — 隧道（ngrok、Cloudflare、Tailscale 等）
- **update** — 更新
- **util** — 工具函数

### 2.2 Workspace 子 Crate

- **zeroclaw** — 主二进制与库
- **zeroclaw-types** — 共享类型
- **zeroclaw-core** — 核心契约与边界
- **crates/robot-kit** — 机器人相关

### 2.3 依赖概览（需在 C++ 侧找替代）

- **CLI**：clap → 自实现或轻量 CLI 库
- **异步**：tokio → 需选用 C++ 异步方案（如 libuv、Boost.Asio、或 HarmonyOS 推荐 API）
- **HTTP**：reqwest → libcurl / HarmonyOS 网络 API
- **序列化**：serde/serde_json → nlohmann/json 或 RapidJSON
- **配置**：toml + directories → 自解析 TOML/JSON + 平台路径
- **日志**：tracing → 自实现或 HiLog/标准日志
- **数据库**：rusqlite → SQLite C API 或 HarmonyOS 数据管理
- **加密**：chacha20poly1305、hmac、ring 等 → OpenSSL / mbedTLS / 系统 API
- **WebSocket**：tokio-tungstenite → 选型（如 libwebsockets）
- **Cron**：cron → 自实现 cron 解析与调度

---

## 三、移植范围与阶段划分

建议采用**分阶段、可验证**的移植策略，先打通最小可运行闭环，再逐步扩展功能。

### 阶段 0：环境与工程骨架（优先）

- 在项目根目录建立 hiClaw 的 C++ 工程（与 `reference/` 平级）。
- 配置 HarmonyOS 编译工具链（使用 `D:\tools\commandline-tools-windows`）。
- 使用 CMake 或 DevEco Studio 的 Native 工程模板，目标架构：**aarch64-linux-ohos**（与 reference 中 `build-ohos.sh` 一致）。
- 产出：可编译、可推送到设备并打印版本信息的 **hiClaw** 可执行文件（无业务逻辑）。

### 阶段 1：最小 CLI + 配置

- 实现最小 CLI（解析 `--version`、`--config-dir` 等，与 zeroclaw 主命令对齐）。
- 实现配置加载：从 JSON/TOML 读取核心配置项（如 default_model、models、config 目录），对应 zeroclaw 的 `config::Config` 子集。
- 不实现 agent 逻辑，仅验证：读取配置并打印关键字段。

### 阶段 2：核心 Agent 单轮对话

- 移植 **agent** 核心数据结构与单轮对话流程（对应 `agent::Agent`、`agent::loop_` 的简化版）。
- 实现 **providers** 中 1～2 个提供商（如 OpenAI 兼容接口或 Ollama）的 HTTP 调用。
- 实现 **tools** 的最小子集：如 `shell`、`file_read`、`file_write`（仅核心路径）。
- 实现 **skills/tool_handler** 的简化版：根据模型返回的 tool_calls 派发到上述工具并返回结果。
- 目标：在 HarmonyOS 设备上能完成「用户输入 → 模型 → 可选 tool 调用 → 回复」的单轮闭环。

### 阶段 3：记忆与持久化

- 移植 **memory** 的 SQLite 后端（对应 `memory::sqlite`），或使用 HarmonyOS 推荐存储方式。
- 实现 **memory_store**、**memory_recall**、**memory_forget** 等工具的最小实现。
- 使 agent 在多轮对话中能读写记忆。

### 阶段 4：定时任务与通道（按需裁剪）

- 移植 **cron** 调度逻辑（解析 cron 表达式、触发任务）。
- 实现 1 个通道（如 **Telegram** 或 **HTTP 回调**）用于接收用户消息并驱动 agent。
- 若移动端优先，可仅做 HTTP/Webhook 通道，其余通道列为后续迭代。

### 阶段 5：安全、可观测与生产化

- 移植 **security** 中与移动端相关的策略（如密钥存储、敏感路径保护），适配 HarmonyOS 沙箱。
- 实现 **observability** 的简化版（日志级别、可选指标导出）。
- 完善错误处理、资源释放与稳定性，便于真机长期运行。

### 阶段 6+：扩展功能（可选）

- 更多 **providers**、**tools**、**channels**。
- **plugins**、**WASM** 运行时等按需移植。

---

## 四、技术选型与依赖映射

### 4.1 工具链与构建

| 用途 | 说明 |
|------|------|
| **NDK 路径** | `D:\tools\commandline-tools-windows`（README 指定） |
| **NDK native** | 通常为 `{上述路径}/sdk/default/openharmony/native`，与 reference 中 `build-ohos.sh` 的 `OHOS_NDK_HOME` 对应 |
| **编译器** | 使用 NDK 内 `llvm/bin/clang`、`clang++` |
| **目标三元组** | `aarch64-linux-ohos`（首选） |
| **构建系统** | CMake + NDK 提供的 `ohos.toolchain.cmake`，或 DevEco Studio Native 工程 |

### 4.2 Rust → C++ 依赖映射（建议）

| Rust 依赖 | C++ / HarmonyOS 替代 |
|-----------|----------------------|
| serde_json / toml | nlohmann/json 或 RapidJSON；TOML 可自解析或使用 tomlcpp 等 |
| reqwest | libcurl 或 HarmonyOS 网络 API（如 `@ohos.net.http` 的 Native 封装） |
| tokio | 线程 + 同步/异步 HTTP；或 libuv、Boost.Asio（需评估 OHOS 兼容性） |
| rusqlite | SQLite3 C API 或 OHOS 关系型数据库 |
| tracing / tracing-subscriber | 自实现或 HiLog |
| clap | 手写 main 参数解析或轻量库 |
| chrono | C++11 `<chrono>` + 简单日期解析 |
| base64 | 小库或自实现 |
| uuid | 随机数 + 格式化或轻量库 |

### 4.3 目录结构建议（hiClaw 根目录）

```
harmonyos_claw/
├── README.md
├── reference/                 # 只读参考，不修改
│   └── zeroclaw/
├── docs/
│   └── PORTING_PLAN.md        # 本文档
├── hiClaw/                    # 移植后的 C++ 工程
│   ├── CMakeLists.txt
│   ├── src/
│   │   ├── main.cpp
│   │   ├── cli/
│   │   ├── config/
│   │   ├── agent/
│   │   ├── providers/
│   │   ├── tools/
│   │   ├── skills/
│   │   ├── memory/
│   │   ├── cron/
│   │   └── ...
│   ├── include/
│   └── third_party/           # json、curl、sqlite 等
└── scripts/
    ├── build-ohos.bat         # Windows 下使用 NDK 构建
    └── deploy-and-verify.bat # hdc file send + shell 验证
```

---

## 五、各阶段任务清单（可勾选执行）

### 阶段 0：环境与工程骨架

- [x] 创建 `hiClaw/` 目录及 `CMakeLists.txt`。
- [x] 配置交叉编译：`OHOS_NDK_HOME` 指向 `D:\tools\commandline-tools-windows\sdk\default\openharmony\native`（或实际安装路径）；脚本 `scripts/build-ohos.bat`。
- [x] 在 CMake 中指定 `ohos.toolchain.cmake` 与目标为 `aarch64-linux-ohos`。
- [x] 编写 `main.cpp`：打印 `hiClaw` 与版本号后退出。
- [x] 编写脚本：使用 NDK 的 CMake 生成并编译，产出 `hiClaw` 可执行文件；`scripts/build-win-x64.bat` 用于本机验证。
- [x] 使用 `hdc file send hiClaw /data/local/bin` 推送（见 `scripts/deploy-and-verify.bat`）。
- [ ] 使用 `hdc shell` 执行 `/data/local/bin/hiClaw --version`，确认无报错（需连接设备后执行 deploy-and-verify.bat）。

### 阶段 1：最小 CLI + 配置

- [x] 实现命令行解析：`--version`、`--config-dir`、子命令占位（如 `run`）。
- [x] 实现配置文件查找与读取（默认目录 `.hiclaw`，与 zeroclaw 类似）。
- [x] 解析 JSON 中的 `default_model`、`models`、`config_dir` 等。
- [x] 在 `hiClaw run` 时加载配置并打印关键项，验证无误。

### 阶段 2：核心 Agent 单轮对话

- [x] 定义与 zeroclaw 兼容的消息/角色结构（user/assistant/system/tool）。
- [x] 实现 1 个 provider 的 HTTP 调用（Ollama，HTTP only）。
- [x] 实现 agent 单轮：构建 messages → 调用 provider → 解析 tool_calls（若有）→ 派发到工具。
- [x] 实现 `shell`、`file_read`、`file_write` 三个工具的最小实现。
- [x] 实现 tool 结果回填与再次请求模型，得到最终回复。
- [ ] 在设备上运行 `hiClaw run "你好"` 并验证回复与工具调用（需设备 + Ollama 或兼容服务）。

### 阶段 3：记忆与持久化

- [x] 实现 memory 存储与召回接口（当前为基于文件的 backend：`config_dir/memory/*.json`，零依赖，适配 OHOS）。
- [x] 实现 memory_store / memory_recall / memory_forget 工具并注册到 agent。
- [x] Agent 启动时设置 memory 根路径（config_dir）；模型可通过工具在对话中读写记忆。

### 阶段 4：Cron + 单通道

- [x] 实现 cron 表达式解析与下一次触发时间计算（5 字段，支持 *、N、*/M；UTC）。
- [x] 实现持久化任务队列：`config_dir/cron/jobs.json`；子命令 `cron list`、`cron add "<expr>" "<prompt>"`、`cron run`。
- [x] 实现 HTTP 通道：子命令 `serve [port]`，POST 请求体 `{"prompt":"..."}` 调用 agent 并返回 `{"content":"..."}`，便于 E2E 验证。

### 阶段 5：安全与可观测

- [x] 配置优先从环境变量读取：`HICLAW_OLLAMA_BASE_URL`、`HICLAW_DEFAULT_MODEL` 覆盖 config.json，便于密钥/地址不落盘。
- [x] 敏感路径检查：`security::is_path_allowed` 禁止 file_read/file_write 访问 /etc、/system、/vendor、C:\\Windows\\System 等，适配本地与 OHOS。
- [x] 日志级别：`--log-level` 与 `HICLAW_LOG`（off|error|warn|info|debug），输出 stderr，便于排查问题。

### 阶段 6+：扩展

- [x] 增加 **OpenAI 兼容** provider：`default_provider` 为 `openai` 或 `openai_compatible` 时，请求 `openai_base_url/v1/chat/completions`，支持 `HICLAW_OPENAI_API_KEY`/`OPENAI_API_KEY`（HTTP 仅限；HTTPS 需反向代理）。
- [x] 增加 **web_fetch** 工具：HTTP GET 指定 URL，返回响应 body（仅允许 `http://`）。
- [x] Provider 选择：由 `config.default_provider` 与 `config.openai_base_url`、环境变量驱动。
- [ ] **plugins/WASM**：zeroclaw 的插件与 WASM 运行时未移植，列为后续可选扩展。

---

## 六、构建与验证流程

### 6.1 构建（示例：CMake + NDK）

```powershell
# 设置 NDK（与 README 一致）
$env:OHOS_NDK_HOME = "D:\tools\commandline-tools-windows\sdk\default\openharmony\native"

# 在 hiClaw 目录或项目根目录
cd d:\projects\harmonyos_claw\hiClaw
mkdir build-ohos
cd build-ohos
cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE="$env:OHOS_NDK_HOME/build/cmake/ohos.toolchain.cmake" ..
ninja
```

若 NDK 结构不同，需根据实际路径调整 `OHOS_NDK_HOME` 与 `ohos.toolchain.cmake` 位置。

### 6.2 部署与验证（README 要求）

```powershell
# 推送二进制到设备
hdc file send .\hiClaw /data/local/bin

# 进入设备 shell 验证
hdc shell
# 在设备内：
chmod +x /data/local/bin/hiClaw
/data/local/bin/hiClaw --version
# 若有 run 子命令：
/data/local/bin/hiClaw run "测试"
```

每次阶段结束时都应执行上述流程，确保**编译与运行均无错误**。

---

## 七、风险与注意事项

1. **reference 只读**：所有参考仅阅读 `reference/zeroclaw`，不得修改其中任何文件。
2. **依赖与 ABI**：第三方 C/C++ 库（如 curl、sqlite）需使用 NDK 编译或使用 OHOS 提供的预编译库，注意 ABI 与 sysroot 一致。
3. **异步与线程**：Rust 的 tokio 模型需在 C++ 中用线程/事件循环等价实现，注意线程安全与资源释放。
4. **API 密钥与配置**：不将密钥写死在代码中；使用配置文件或环境变量，并在文档中说明。
5. **HarmonyOS 版本**：参考 `reference/zeroclaw/docs/harmonyos-build.md`，建议目标 API 22+，以便使用稳定系统库。
6. **沙箱与权限**：HarmonyOS 对文件、网络有限制，需在设计与测试时考虑权限与沙箱策略。

---

## 八、文档与迭代

- 在 `docs/` 下可新增 `PORTING_LOG.md` 记录每阶段完成情况与遇到的问题。
- 若 NDK 路径或构建步骤有变，请同步更新本文档与 `README.md`。
- 每完成一个阶段，在「各阶段任务清单」中勾选对应项，并执行一次完整的「构建 → 推送 → hdc shell 验证」流程。

---

*文档版本：1.0 | 基于 README 与 reference/zeroclaw 结构整理*
