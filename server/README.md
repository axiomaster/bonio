# HiClaw

将 zeroclaw（Rust）移植到 C++，面向 **HarmonyOS** 运行。参考实现位于 `reference/`，移植时不得修改 reference 下代码。项目名 **HiClaw**（程序/路径为小写 `hiclaw`）。

---

## 构建

所有构建产物统一输出到 `build/` 目录：

```
build/
├── android/           # Android 构建产物
│   ├── arm64-v8a/     # 64位 ARM
│   ├── armeabi-v7a/   # 32位 ARM
│   └── x86_64/        # x86 模拟器
├── ohos/              # HarmonyOS 构建产物
├── linux-amd64/       # Linux x86_64 构建产物
└── win-x64/           # Windows x64 构建产物
```

### Windows x64

```powershell
scripts\build-win-x64.bat
# 产出: build\win-x64\hiclaw.exe
```

### Linux x86_64

```bash
scripts/build-linux-amd64.sh
# 产出: build/linux-amd64/hiclaw

# 依赖: apt install cmake ninja-build libssl-dev
```

### Android

- **Windows 脚本**：`scripts\build-android.bat`（需设置 `ANDROID_NDK_HOME`）。
- **WSL/Linux/macOS**：`scripts/build-android.sh`。
- 环境变量：
  ```powershell
  # Windows 示例
  set ANDROID_NDK_HOME=D:\Android\sdk\ndk\26.1.10909125

  # Linux/macOS 示例
  export ANDROID_NDK_HOME=~/Android/Sdk/ndk/26.1.10909125
  ```
- 可选配置：
  - `ANDROID_ABI`：目标 ABI（默认 `arm64-v8a`，可选 `armeabi-v7a`、`x86_64`）
  - `ANDROID_API_LEVEL`：最低 SDK 版本（默认 `24`）
  - `HICLAW_BUILD_TYPE`：构建类型（默认 `Release`）
- 部署到设备：
  ```bash
  # 使用部署脚本
  scripts\deploy-android.sh arm64-v8a

  # 或手动部署
  adb push build/android/arm64-v8a/hiclaw /data/local/tmp/
  adb shell chmod +x /data/local/tmp/hiclaw
  adb shell /data/local/tmp/hiclaw --version
  ```
- 多架构构建：`scripts\build-android-all.bat`（同时构建 arm64-v8a、armeabi-v7a、x86_64）。

### HarmonyOS（OHOS）

- **Windows 脚本**：`scripts\build-ohos.bat`（需已配置 `OHOS_NDK_HOME`）。
- **WSL/Linux**：`scripts/build-ohos.sh`。
- 手动示例（bash）：
  ```bash
  export OHOS_NDK_HOME=/path/to/openharmony/native
  scripts/build-ohos.sh
  # 产出: build/ohos/hiclaw
  ```
- 推送设备：`hdc file send build/ohos/hiclaw /data/local/bin`；用 `hdc shell` 验证。

---

## 命令概览

| 命令 | 说明 |
|------|------|
| `hiclaw --version` | 打印版本 |
| `hiclaw run "prompt"` | 单轮对话 |
| `hiclaw cron list \| add "expr" "prompt" \| run` | 定时任务 |
| `hiclaw serve [port]` | HTTP 服务（POST `{"prompt":"..."}`） |
| `hiclaw gateway [--port 18789] [--new-pairing]` | WebSocket 网关 |
| `hiclaw agent` | 交互模式：输入问题并查看模型回复与请求过程 |
| `hiclaw agent run "prompt"` | Agent 单次问答 |
| `hiclaw agent serve [port]` | Agent HTTP 服务 |
| `hiclaw config` | 交互配置（如选择 model 进行模型配置） |
| `hiclaw model list \| status` | 列出模型或查看当前模型状态 |

**全局选项**：`--config-dir <path>`（默认 `.hiclaw`）、`--log-level`、`-h` / `-V`。

---

## 配置

### 配置文件位置

- **未设置 HICLAW_WORKSPACE**：从 `--config-dir`（默认 `.hiclaw`）下的 **config.json** 读写。
- **设置 HICLAW_WORKSPACE**：从 **workspace/hiclaw.json** 读写；支持 `~`（如 `export HICLAW_WORKSPACE=~`）。`hiclaw model config` 等修改会写回该文件。

### Model 与 Provider

- 配置为 **models** 列表；每项为一条 model（如 glm-4、minimax-2.5），其 **provider** 字段指向厂商（如 glm、minimax）。多个 model 可共用同一 provider。
- 配置文件（config.json 或 hiclaw.json）中：
  - **default_model**：当前使用的 model id（需在 models 列表中）。
  - **models**：数组，每项含 `id`、`provider`，可选 `base_url`、`model_id`、`api_key_env`。
- **Provider 元数据**（展示名、默认 base_url、默认 api_key_env）在 C++ 中定义为常量，见 **hiclaw/include/hiclaw/config/default_providers.hpp**；增删厂商需改该头文件后重新编译。
- 示例：`hiclaw/.hiclaw/config.json.example`。查看：`hiclaw model list`、`hiclaw model status`；配置：`hiclaw config` 进入交互后选 `model`。

### 其他路径

- 记忆：`config_dir/memory/`（或 workspace 下的 config_dir）。
- Cron 任务：`config_dir/cron/jobs.json`。

---

## 环境变量

| 变量 | 说明 |
|------|------|
| **HICLAW_WORKSPACE** | 若设置，从 workspace/hiclaw.json 读写配置；支持 `~`。 |
| **hiclaw_log** | 日志级别：off / error / warn / info / debug。 |
| **hiclaw_default_model** | 覆盖配置中的 default_model。 |
| **hiclaw_ollama_base_url** | 覆盖 ollama_base_url。 |
| **hiclaw_openai_base_url** | 覆盖 openai_base_url。 |
| API Key | 由各 model 的 `api_key_env` 指定（如 GLM_API_KEY、MINIMAX_API_KEY），见 `hiclaw/.hiclaw/config.env.example`。 |

---

## 功能摘要

- **run / agent run**：单轮对话；支持工具 shell、file_read、file_write、web_fetch、memory_store / memory_recall / memory_forget。
- **HTTP 客户端**：当前仅支持 **HTTP**（无 TLS）。直接调用云厂商 https 接口需本机 HTTP 代理或后续增加 TLS 支持。
- **Gateway**：双后端 **websocketpp**（HarmonyOS 默认，FetchContent）与 **libwebsockets**（主机可选）；CMake `-DHICLAW_GATEWAY_BACKEND=websocketpp|libwebsockets|auto`。
- **安全**：file_read / file_write 限制访问系统敏感目录。

---

## 依赖（Gateway）

- **websocketpp + Asio**：默认后端，HarmonyOS 构建自动选用；FetchContent 拉取，无需预装。
- **libwebsockets**：可选；主机上可 `-DHICLAW_GATEWAY_BACKEND=libwebsockets`，需已安装 LWS。

`auto` 时：OHOS 用 websocketpp；非 OHOS 且已装 LWS 则用 LWS，否则回退 websocketpp。
