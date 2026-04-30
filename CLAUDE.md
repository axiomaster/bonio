# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

请你永远永远记住，
1. 每次修改完成代码后都编译一下，确保代码可以正常编译通过；
2. 每次开发完一个功能，都git提交一下，确保不会丢失；

## Project Overview

BoJi (HiClaw) is an AI agent gateway system with four components:
- **server/** — C++ WebSocket gateway server (HiClaw) that connects to LLM providers and routes tool calls
- **android/** — Kotlin/Jetpack Compose companion app for device control (camera, location, SMS)
- **harmonyos/** — ArkTS/HarmonyOS port of the Android app
- **desktop/** — Flutter desktop client for Windows/macOS (chat, config, session management)

Clients maintain **dual WebSocket sessions**: `operatorSession` (user commands: chat, config) and `nodeSession` (server-initiated tool calls: camera, location, etc.).

## Build Commands

### Server (C++17, CMake)

```bash
# Windows x64
cd server && scripts\build-win-amd64.bat
# Output: server/build/win-amd64/hiclaw.exe

# Linux amd64 (deps: apt install cmake ninja-build libssl-dev)
cd server && scripts/build-linux-amd64.sh [--clean]
# Output: server/build/linux-amd64/hiclaw

# Android (requires ANDROID_NDK_HOME)
cd server && scripts/build-android-arm64-v8a.sh
# Output: server/build/android-arm64-v8a/hiclaw

# HarmonyOS (requires OHOS_NDK_HOME)
cd server && scripts/build-ohos-arm64.sh
# Output: server/build/ohos-arm64/hiclaw
```

Third-party deps are vendored in `server/third_party/` (CLI11, spdlog, nlohmann_json, libhv, mbedtls, websocketpp, asio, linenoise-ng). Must be cloned before building — see CMakeLists.txt error messages for clone URLs.

### Unified Build Scripts (root `scripts/`)

One-click build, bundle, and launch scripts at the project root:

```bash
# Windows — build server + desktop, bundle hiclaw, and launch
scripts\build-and-run.bat

# macOS / Linux
scripts/build-and-run.sh

# Options (all scripts):
#   --skip-server   Skip hiclaw compilation
#   --skip-desktop  Skip Flutter compilation
#   --clean         Clean build directories first
```

Individual steps:

```bash
# Build hiclaw only → server/bin/hiclaw(.exe)
scripts\build-server.bat          # Windows
scripts/build-server.sh           # macOS / Linux

# Build Flutter desktop + bundle hiclaw (requires server built first)
scripts\build-desktop.bat --run   # Windows, --run to launch after build
scripts/build-desktop.sh --run    # macOS / Linux

# Platform-specific server builds (called by build-server scripts):
cd server && scripts\build-win-amd64.bat       # → build/win-amd64/ + bin/
cd server && scripts/build-linux-amd64.sh       # → build/linux-amd64/ + bin/
cd server && scripts/build-macos-arm64.sh       # → build/macos-arm64/ + bin/
cd server && scripts/build-android-arm64-v8a.sh  # → build/android-arm64-v8a/ + bin/
cd server && scripts/build-ohos-arm64.sh        # → build/ohos-arm64/ + bin/
```

### Running Tests

```bash
# Android
cd android && ./gradlew test

# Desktop (Flutter)
cd desktop && flutter test

# HarmonyOS
cd harmonyos && hvigorw test
```

Server has no test suite.

### Android App

```bash
cd android && ./gradlew assembleDebug
```

Package: `ai.axiomaster.boji`, compileSdk 36, minSdk 31, Java 17, Jetpack Compose.

### HarmonyOS App

```bash
# Requires DevEco Studio SDK
$env:DEVECO_SDK_HOME="D:\Program Files\Huawei\DevEco Studio\sdk"
cd harmonyos && hvigorw --mode module -p product=default assembleHap
```

See `harmonyos/CLAUDE.md` for full HarmonyOS development details.

### Desktop App (Flutter)

```bash
cd desktop && flutter pub get && flutter run -d windows
# or for macOS:
cd desktop && flutter pub get && flutter run -d macos
# Build release:
cd desktop && flutter build windows
cd desktop && flutter build macos
# Bundle hiclaw into build output (after server build):
cd desktop && powershell -File scripts\bundle-hiclaw.ps1     # Windows
cd desktop && ./scripts/bundle-hiclaw.sh <app_bundle_path>   # macOS
```

Requires Flutter SDK >=3.2.0. Cross-platform (Windows + macOS) via single Flutter codebase.

**Desktop TTS (avatar commands)**

- Avatar `tts` / `stopTts` use [`desktop/lib/services/desktop_tts.dart`](desktop/lib/services/desktop_tts.dart): **no** `flutter_tts` native plugin (avoids Windows CMake/NuGet). Speech is implemented with **PowerShell + System.Speech** on Windows, **`say`** on macOS, and **`spd-say` / `espeak-ng` / `espeak`** on Linux when available in `PATH`.
- Assistant reply **speech** (when enabled in Settings) uses the same `DesktopTts` after each completed chat turn (`ChatController` → `onAssistantReplyForTts`), so OpenClaw does not need to emit `avatar.command` for basic read-aloud.
- The pet is shown in a **second OS window** via [`desktop_multi_window`](desktop/pubspec.yaml) + [`window_manager`](desktop/pubspec.yaml) (see [`desktop/lib/main.dart`](desktop/lib/main.dart), [`desktop/lib/avatar_window_app.dart`](desktop/lib/avatar_window_app.dart)), so it stays visible when the main BoJi window is minimized. State is pushed from [`AvatarController`](desktop/lib/services/avatar_controller.dart) with `invokeMethod('sync', …)`; drag deltas go back through `avatarPan` on the main window controller.

**Desktop STT (voice input)**

- Uses **Sherpa-ONNX streaming paraformer** (bilingual zh-en), same engine as Android's `SherpaOnnxSpeechManager`. Architecture mirrors Android's `SpeechToTextManager` → `SherpaOnnxSpeechManager` with unified `SpeechToTextListener` callback interface (partial, final, error, ready, end).
- Audio capture via [`record`](desktop/pubspec.yaml) package (PCM16, 16 kHz, mono) → `sherpa_onnx` FFI `OnlineRecognizer` with endpoint detection.
- Model files (`encoder.int8.onnx`, `decoder.int8.onnx`, `tokens.txt`) must be placed next to the executable. Download with `powershell -ExecutionPolicy Bypass -File tool/download_model.ps1`.

## Server CLI Reference

| Command | Description |
|---------|-------------|
| `hiclaw run "prompt"` | Single-turn chat |
| `hiclaw gateway [--port 18789]` | Start WebSocket gateway |
| `hiclaw serve [port]` | HTTP service (POST `{"prompt":"..."}`) |
| `hiclaw agent` | Interactive REPL mode |
| `hiclaw config` | Interactive configuration |
| `hiclaw model list` | List configured models |
| `hiclaw --version` | Print version |

Global options: `--config-dir <path>` (default `~/.bonio`), `--log-level`.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `HICLAW_WORKSPACE` | If set, read config from `$HICLAW_WORKSPACE/hiclaw.json` |
| `hiclaw_log` | Log level: off/error/warn/info/debug |
| `hiclaw_default_model` | Override config's `default_model` |
| API keys | Set per model via `api_key_env` field (e.g., `GLM_API_KEY`) |

## Architecture

### Server (HiClaw)

```
server/
├── src/main.cpp                   # CLI entry point (subcommands: run, config, serve, etc.)
├── src/agent/agent.cpp            # Agent loop (LLM call → tool call → result → repeat)
├── src/config/config.cpp          # Config loading/saving (hiclaw.json)
├── src/cron/                      # Cron scheduler (5-field expr parser + persistent store)
├── src/memory/file_memory.cpp     # Agent memory: store, recall, forget (file-based)
├── src/net/
│   ├── gateway.cpp                # WebSocket gateway - all RPC methods + event broadcast
│   ├── async_agent.cpp            # Per-session agent manager (LLM streaming)
│   ├── http_client.cpp            # HTTP client for LLM provider APIs
│   ├── tool_router.cpp            # Routes tool calls to node sessions
│   ├── intent_router.cpp          # Classifies voice STT results (chat/screenshot/summarize/call)
│   ├── call_handler.cpp           # Incoming call flow: TTS, countdown, answer/reject, spam detect
│   ├── idle_manager.cpp           # Pet avatar random wandering when device is idle
│   ├── health_monitor.cpp         # Screen-time awareness: late-night usage nags
│   ├── notification_handler.cpp   # Filters important notifications for avatar reactions
│   ├── wechat_adapter.cpp         # WeChat channel bridge (WeCom + ilink → agent pipeline)
│   ├── wecom_ws_client.cpp        # WeCom intelligent-bot WebSocket long-connection client
│   └── ilink_http_client.cpp      # HTTP client for WeChat ilink bot API (personal WeChat)
├── src/observability/log.cpp      # Structured logging (spdlog wrapper)
├── src/providers/                 # LLM provider adapters (ollama, openai_compatible)
├── src/security/path_guard.cpp    # Path traversal protection for file operations
├── src/session/store.cpp          # Chat session persistence (file-based)
├── src/skills/skill_manager.cpp   # Skill loading/management
├── src/tools/
│   ├── tool.cpp                   # Tool definitions and execution
│   └── memo_tool.cpp              # memo_save / memo_list tools
└── include/hiclaw/                # Headers mirror src/ structure
```

Key design: `gateway.cpp` uses websocketpp. The gateway manages connected client sessions and broadcasts events (agent deltas, chat updates, avatar commands) to relevant clients. `WeChatAdapter` feeds external WeChat messages into the same agent pipeline as gateway chat messages.

### Android App

```
android/app/src/main/java/ai/axiomaster/boji/
├── MainViewModel.kt          # MVVM ViewModel, holds serverConfig StateFlow
├── NodeRuntime.kt            # Core runtime: manages operatorSession + nodeSession
├── remote/gateway/           # GatewaySession (WebSocket RPC), DeviceIdentityStore (Ed25519)
├── remote/node/              # InvokeDispatcher routes server commands to handlers
├── remote/chat/              # ChatController, VoskSpeechManager, SystemTtsManager
├── remote/config/            # ConfigRepository, ServerConfig data classes
├── ui/screens/               # Compose UI: ServerTab, ChatTab, ModelConfigScreen
```

### Desktop App (Flutter)

```
desktop/lib/
├── main.dart                     # App entry point, theme config
├── models/
│   ├── gateway_models.dart       # GatewayEndpoint, GatewayConnectOptions, GatewayClientInfo
│   ├── server_config.dart        # ServerConfig, ModelConfig, ProviderInfo, GatewayConfig
│   ├── chat_models.dart          # ChatMessage, ChatMessageContent, ChatPendingToolCall, etc.
│   └── device_identity.dart      # DeviceIdentity data model
├── services/
│   ├── gateway_session.dart      # WebSocket session (protocol v3, reconnection, RPC)
│   ├── device_identity_store.dart # Ed25519 key generation, signing, persistence
│   ├── device_auth_store.dart    # Device token persistence (SharedPreferences)
│   ├── config_repository.dart    # config.get / config.set via gateway
│   ├── chat_controller.dart      # Chat state, streaming, history, sessions
│   └── node_runtime.dart         # Dual session orchestration (operator + node)
├── providers/
│   └── app_state.dart            # App-level state (Provider pattern)
└── ui/
    ├── screens/
    │   ├── main_screen.dart      # NavigationRail layout (Chat, Server, Settings)
    │   ├── chat_tab.dart         # Chat messages with markdown rendering
    │   ├── server_tab.dart       # Gateway connection + model config cards
    │   ├── model_config_screen.dart # Add/edit/remove model configurations
    │   └── settings_tab.dart     # About, keyboard shortcuts, capabilities
    └── widgets/
        └── chat_composer.dart    # Message input with thinking level selector
```

Desktop shares the same gateway protocol and dual-session architecture as Android/HarmonyOS. Mobile-only capabilities (camera, location, SMS, etc.) respond with `UNSUPPORTED_COMMAND` on the node session.

### WeChat Integration

Server bridges WeChat into the agent pipeline via `WeChatAdapter`, which orchestrates two channel clients:

- **WeCom** (`WecomWsClient`) — Enterprise WeChat intelligent-bot protocol over `wss://openws.work.weixin.qq.com`. Receives messages via WebSocket long-connection, replies via `aibot_respond_msg` (stream format). Requires `bot_id` + `bot_secret` in config.
- **ilink** (`IlinkHttpClient`) — Personal WeChat bot API via HTTP long-polling. Receives messages with `get_updates()`, sends replies chunked to 3800 chars with retry on `ret=-2`. Requires `token` + `base_url` in config.

Messages from either channel flow through the same `AsyncAgentManager` → `Agent` loop → tool calls → response pipeline as gateway chat messages. Reply context (callback_req_id for WeCom, user_id for ilink) is tracked per session. Message deduplication by msg_id prevents double-processing.

### Avatar Command System

Server sends `avatar.command` events to control the pet avatar on clients. Commands are built via `avatar_cmd` helpers in [`server/include/hiclaw/net/avatar_command.hpp`](server/include/hiclaw/net/avatar_command.hpp):

| Command | Purpose |
|---------|---------|
| `setState(state, temporary?)` | Switch avatar animation state (idle, happy, confused, etc.) |
| `moveTo(x, y, mode)` | Move avatar to position (mode: "walk", "jump", etc.) |
| `setBubble(text, bgColor?, textColor?)` | Show speech/thought bubble |
| `setBubbleCountdown(text, countdown)` | Show bubble with countdown timer |
| `clearBubble()` | Hide bubble |
| `tts(text)` / `stopTts()` | Text-to-speech |
| `playSound(type)` | Play sound effect ("notification", etc.) |
| `setColorFilter(color)` / `clearColorFilter()` | Tint the avatar |
| `setPosition(x, y)` / `cancelMovement()` | Teleport or cancel movement |
| `performAction(type)` | Trigger one-shot animation |
| `sequence(steps[])` | Chain multiple commands with optional delays |

### Server Subsystems

All subsystems receive an `EventCallback` to push events to connected clients:

- **IntentRouter** — Classifies voice STT final results server-side. Intents: `Chat` (send as chat message), `ScreenCapture`, `Summarize`, `CallAnswer`, `CallReject`. Uses keyword matching. Also provides `classify_call_command()` for during-call voice classification.
- **CallHandler** — Manages incoming phone call flow: sends TTS announcement with caller info, runs countdown timer, performs spam detection (number lookup + contact name heuristics), and sends `call.action` events (answer/reject). Coordinates TTS/STT start/stop with the client.
- **IdleManager** — Random pet avatar wandering when device is idle. Triggers `moveTo` commands at random intervals (8-20s) within a radius when the device screen is on and the avatar is in idle state.
- **HealthMonitor** — Screen-time wellness. Accumulates screen-on time and during late-night hours (23:00-6:00), sends gentle then escalating nags via avatar TTS after 2 hours of continuous use, with 15-minute cooldown between nags.
- **NotificationHandler** — Evaluates `notifications.changed` events. Filters important notifications (from messaging apps, calls, etc.) and triggers avatar reactions via `avatar.command`.

### Cron System

5-field cron expression parser (`minute hour day-of-month month day-of-week`) in [`cron/schedule.hpp`](server/include/hiclaw/cron/schedule.hpp). Supports `*`, `N`, `N-M`, and `*/M` (step) syntax. `cron::store` persists scheduled tasks in a JSON file under the config directory. Used for periodic tasks configured in `hiclaw.json`.

### Memory System

File-based agent memory in [`memory/memory.hpp`](server/include/hiclaw/memory/memory.hpp). Supports `store(key, content, category)`, `recall(query, limit)`, and `forget(key)`. Categories: `core` (always loaded), `daily`, `conversation`, or custom. Stores JSON files under `<config_dir>/memory/`. The agent uses memory to persist user preferences and facts across sessions.

## Gateway Protocol

WebSocket protocol version 3. Frame types: `req` (request), `res` (response), `event`.

### Key RPC Methods

| Method | Direction | Description |
|--------|-----------|-------------|
| `connect` | client→server | Auth handshake (Ed25519 signature) |
| `config.get` | client→server | Returns `{default_model, models[], gateway{}, providers[]}` |
| `config.set` | client→server | Updates config, saves to hiclaw.json |
| `chat.send` | client→server | Send message, returns runId (async streaming) |
| `chat.abort` | client→server | Cancel running request |
| `sessions.list/delete/reset/patch` | client→server | Session management |
| `node.invoke.result` | client→server | Return tool call result |

### Key Events (server→client)

| Event | Description |
|-------|-------------|
| `connect.challenge` | Auth nonce (sent on connect) |
| `node.invoke.request` | Server asks client to execute a tool |
| `agent` | LLM streaming delta (assistant text / tool calls) |
| `chat` | Chat state updates (final, etc.) |
| `tick` | Heartbeat every 30s |

### Tool Call Flow

1. LLM response includes tool_call → server sends `node.invoke.request` to client's `nodeSession`
2. Client's `InvokeDispatcher` routes to handler (camera, location, SMS, screen, etc.)
3. Client sends `node.invoke.result` back to server
4. Server feeds result back to LLM, continues agent loop

## Configuration

Server config lives in `hiclaw.json` (workspace root, default: `~/.bonio/hiclaw.json`). Uses **snake_case** field names throughout:

```json
{
  "default_model": "glm-4.7",
  "gateway": {"enabled": true, "host": "0.0.0.0", "port": 10724},
  "models": [{"id": "glm-4.7", "provider": "glm", "api_key": "..."}]
}
```

`providers` are built-in constants (defined in `server/include/hiclaw/config/default_providers.hpp`), returned read-only via `config.get`. `models` are user-configurable and persisted to `hiclaw.json`.

## Key Patterns

- **snake_case in protocol/API**: All gateway methods and hiclaw.json fields use snake_case (e.g., `default_model`, `api_key_env`, `base_url`)
- **Dual session architecture**: Android, HarmonyOS, and Desktop all maintain separate operator and node WebSocket connections
- **Handler interface pattern**: Feature handlers implement interfaces from `InvokeDispatcher` for testability
- **Provider adapters**: New LLM providers implement the provider interface in `server/src/providers/`
- **Reference implementations**: `reference/` contains original code used during porting — do not modify
- **Desktop platform abstraction**: Platform-specific code lives in `desktop/lib/platform/` with `win32_*.dart` / `macos_*.dart` implementations behind shared interfaces (e.g., `screen_capture.dart`, `microphone.dart`, `gui_agent.dart`). CDP (Chrome DevTools Protocol) agent is in `desktop/lib/platform/cdp/`.
- **Plugin system**: Desktop supports dynamic plugins via `desktop/lib/plugins/` (`PluginManager`, `PluginHost`, `PluginBridge`). Built-in plugins defined in `builtin_plugins.dart`.

## Additional Directories

- **`design/`** — PRD documents and implementation plans for features (记一记, 阅读搭子, plugin system, avatar, voice input, etc.)
- **`skills/phone-use-agent/`** — C++ native CLI for mobile screen automation (references Open-AutoGLM)
- **`reference/`** — OpenClaw (Node.js) and ZeroClaw (Rust) reference implementations, used during porting — read-only
- **`assets/`** — Shared Lottie animations for the avatar cat (various states: idle, happy, confused, etc.)

## Linting & Formatting

- **Desktop**: `desktop/analysis_options.yaml` — Flutter analyzer with relaxed rules (e.g., `prefer_const_constructors: false`)
- **HarmonyOS**: `harmonyos/code-linter.json5` — security-focused rules (`@security/no-unsafe-*`), TypeScript/Performance recommended
- **Android**: standard Kotlin conventions (no explicit ktlint/detekt config)
- **Server**: no enforced style; follows C++17 conventions with snake_case

## Git Notes

- **Git LFS** is used for `.so` and `.onnx` binary files (see `.gitattributes`)
- Sherpa-ONNX model files must be downloaded separately: `powershell -ExecutionPolicy Bypass -File desktop/tool/download_model.ps1`
