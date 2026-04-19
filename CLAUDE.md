# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
cd server && scripts\build-win-x64.bat
# Output: server/build/win-x64/hiclaw.exe

# Linux amd64 (deps: apt install cmake ninja-build libssl-dev)
cd server && scripts/build-linux-amd64.sh [--clean]
# Output: server/build/linux-amd64/hiclaw

# Android (requires ANDROID_NDK_HOME)
cd server && scripts/build-android.sh
# Output: server/build/android/arm64-v8a/hiclaw

# HarmonyOS (requires OHOS_NDK_HOME)
cd server && scripts/build-ohos.sh
# Output: server/build/ohos/hiclaw
```

Third-party deps are vendored in `server/third_party/` (CLI11, spdlog, nlohmann_json, libhv, mbedtls, websocketpp, asio, linenoise-ng). Must be cloned before building — see CMakeLists.txt error messages for clone URLs.

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

Global options: `--config-dir <path>` (default `.hiclaw`), `--log-level`.

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
├── src/main.cpp              # CLI entry point (subcommands: run, config, serve, etc.)
├── src/net/gateway.cpp       # WebSocket gateway - handles all RPC methods
├── src/net/async_agent.cpp   # Per-session agent manager (LLM streaming)
├── src/net/http_client.cpp   # HTTP client for LLM provider APIs
├── src/net/tool_router.cpp   # Routes tool calls to node sessions
├── src/agent/agent.cpp       # Agent loop (LLM call → tool call → result → repeat)
├── src/providers/            # LLM provider adapters (ollama, openai_compatible)
├── src/config/config.cpp     # Config loading/saving (hiclaw.json)
├── src/session/store.cpp     # Chat session persistence (file-based)
├── src/tools/tool.cpp        # Tool definitions and execution
├── src/skills/skill_manager.cpp  # Skill loading/management
└── include/hiclaw/           # Headers mirror src/ structure
```

Key design: `gateway.cpp` has a websocketpp message handler (non-const Config access, for `config.set`) and `gateway_handle_frame` (const Config, read-only methods like `config.get`, `chat.send`).

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

Server config lives in `hiclaw.json` (workspace root). Uses **snake_case** field names throughout:

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
