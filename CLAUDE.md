# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Related instruction files: `AGENTS.md` (condensed agent guidance — keep consistent with this file).

## Mandatory Rules

1. **Always compile after every code change** — run the appropriate build command to verify the code compiles successfully before proceeding.
2. **Always git commit after completing a feature** — commit with a descriptive message to avoid losing work.

## Design Document Workflow

Feature development follows a three-stage document pipeline under `docs/design/`:

| Stage | Input | Output | Naming |
|-------|-------|--------|--------|
| Raw PRD | User provides original design intent | `docs/design/rr/{feature}-{date}.md` | e.g. `note-export-20260517.md` |
| Refined PRD | PM reviews raw PRD, clarifies requirements with user | `docs/design/prd/{feature}-prd-{date}.md` | e.g. `note-export-prd-20260517.md` |
| Architecture | Architect designs implementation based on refined PRD | `docs/design/arch/{feature}-arch-{date}.md` | e.g. `note-export-arch-20260517.md` |

- Raw PRDs in `rr/` are user-authored; do not modify without user confirmation.
- Refined PRDs and architecture docs are produced by the team and must reference the source raw PRD.
- Key architecture docs: `arch/20260826-dsh-refactor-arch.md` (DSH backend), `arch/android-port-arch-20260911.md` (Android embedded engine).

## Project Overview

Bonio (HiClaw) is an AI agent companion system: one backend, four clients, one protocol.

- **server/** — C++17 WebSocket gateway (hiclaw): LLM provider adapters, agent loop, tool routing, memory, cron, WeChat bridge
- **android/** — Kotlin/Jetpack Compose app, package **`ai.axiomaster.bonio`** (compileSdk 36, minSdk 31, Java 17)
- **harmonyos/** — ArkTS port; its agent backend is the on-device **DSH daemon + `dsh-plugins/bonio-bridge`** (WebSocket at `127.0.0.1:10724`), not hiclaw
- **desktop/** — Flutter client for Windows/macOS

All clients speak **WebSocket protocol v3** and maintain **dual sessions**: `operatorSession` (user commands: chat, config) and `nodeSession` (server-initiated tool calls: camera, location, SMS, screen). Mobile-only capabilities respond `UNSUPPORTED_COMMAND` on the desktop node session.

The app↔backend coupling is **protocol-only** — apps only do RPC, never link backend code. The same hiclaw gateway binary is embedded per platform:

- **Android**: bundled as `android/app/src/main/jniLibs/arm64-v8a/libhiclaw.so` (arm64 only), exec'd from `nativeLibraryDir` by [`local/LocalEngineController.kt`](android/app/src/main/java/ai/axiomaster/bonio/local/LocalEngineController.kt) — a loopback gateway on `127.0.0.1` supervised as a child process.
- **Desktop**: bundled next to the app and spawned by [`desktop/lib/services/hiclaw_process.dart`](desktop/lib/services/hiclaw_process.dart).
- **HarmonyOS**: hiclaw is replaced entirely by the DSH backend (see **DSH Backend** below).

## Build Commands

### Server (C++17, CMake)

```bash
# Windows x64
cd server && scripts\build-win-amd64.bat
# Output: server/build/win-amd64/hiclaw.exe

# Linux amd64 (deps: apt install cmake ninja-build libssl-dev)
cd server && scripts/build-linux-amd64.sh [--clean]
# Output: server/build/linux-amd64/hiclaw

# macOS arm64 (requires Xcode Command Line Tools)
cd server && scripts/build-macos-arm64.sh
# Output: server/build/macos-arm64/hiclaw

# Android (requires ANDROID_NDK_HOME)
cd server && scripts/build-android-arm64-v8a.sh
# Output: server/build/android-arm64-v8a/hiclaw

# HarmonyOS (requires OHOS_NDK_HOME)
cd server && scripts/build-ohos-arm64.sh
# Output: server/build/ohos-arm64/hiclaw
```

Each build also copies the binary to `server/bin/`. Third-party deps are vendored in `server/third_party/` (CLI11, spdlog, nlohmann_json, libhv, mbedtls, websocketpp, asio, linenoise-ng). Must be cloned before building — see CMakeLists.txt error messages for clone URLs.

**Embedding the engine into the Android APK** (after a successful android-arm64 build):

```bash
cp server/build/android-arm64-v8a/hiclaw android/app/src/main/jniLibs/arm64-v8a/libhiclaw.so
```

The `lib*.so` name is required for APK packaging; `useLegacyPackaging = true` in `app/build.gradle.kts` extracts it to `nativeLibraryDir` (Android 10+ W^X only allows exec from there). Bundled native libs must be **16KB-page-aligned** — Android 15+ installers reject 4KB-aligned ones.

### Unified Build Scripts (root `scripts/`)

One-click build, bundle, and launch scripts at the project root:

```bash
# Windows — build server + desktop, bundle hiclaw, and launch
scripts\build-and-run.bat [--ninja]   # --ninja uses Ninja instead of the VS generator

# macOS / Linux
scripts/build-and-run.sh

# Options (all scripts):
#   --skip-server   Skip hiclaw compilation
#   --skip-desktop  Skip Flutter compilation
#   --clean         Clean build directories first

scripts\build-server.bat / scripts/build-server.sh    # hiclaw only → server/bin/
scripts\build-desktop.bat --run / scripts/build-desktop.sh --run   # Flutter desktop + bundle hiclaw
```

### Running Tests

```bash
# Android (unit tests in android/app/src/test/, e.g. UserProfileExtractionTest, NotificationTodoExtractorTest)
cd android && ./gradlew test
cd android && ./gradlew test --tests "ai.axiomaster.bonio.UserProfileExtractionTest"   # single class

# Desktop (Flutter)
cd desktop && flutter test
cd desktop && flutter test test/services/foo_test.dart              # single file
cd desktop && flutter test --plain-name "some test name"            # single test

# HarmonyOS
cd harmonyos && hvigorw test
```

Server has no test suite — verification is compiling and running it.

### Android App

```bash
cd android && ./gradlew assembleDebug
```

- Chat STT uses the **platform `SpeechRecognizer`** only ([`remote/chat/SpeechToTextManager.kt`](android/app/src/main/java/ai/axiomaster/bonio/remote/chat/SpeechToTextManager.kt)) — the offline Sherpa-ONNX engine was cut from the v1 build (APK 345MB → 114MB).
- The avatar uses **sprite sheets** (`avatar/PixelAvatarView.kt`), not Lottie — Lottie deps/assets were stripped from Android (desktop still uses `lottie`).

### HarmonyOS App

```bash
# Requires DevEco Studio SDK (API 26). No hvigorw wrapper is vendored in
# harmonyos/ — use DevEco's bundled hvigor. On this Mac:
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
cd harmonyos && hvigorw --mode module -p product=default assembleHap
```

Builds are **unsigned** (no `signingConfigs` committed). After any HAP task: full `hvigorw clean assembleHap` → sign with **hapsigner** using the `system_core` profile in `harmonyos/root_float_signing/` → `hdc install -r` onto a connected device (report the blocker if no device).

### Desktop App (Flutter)

```bash
cd desktop && flutter pub get && flutter run -d macos   # or -d windows
cd desktop && flutter build macos                        # release build
./scripts/bundle-hiclaw.sh <app_bundle_path>             # bundle hiclaw (server built first)
# Windows: powershell -File scripts\bundle-hiclaw.ps1
```

Requires Flutter SDK >=3.2.0. Cross-platform (Windows + macOS) via single Flutter codebase.

**Desktop quirks**

- `desktop_multi_window` is a **vendored local package** (`desktop/packages/desktop_multi_window`, path dep in pubspec) — not from pub.dev. Together with `window_manager` it hosts the pet in a **second OS window** ([`avatar_window_app.dart`](desktop/lib/avatar_window_app.dart)) so it stays visible when the main window is minimized. State is pushed from `AvatarController` (`invokeMethod('sync', …)`); drag deltas return via `avatarPan`.
- **TTS** ([`desktop/lib/services/desktop_tts.dart`](desktop/lib/services/desktop_tts.dart)): deliberately **no `flutter_tts` plugin** (avoids Windows CMake/NuGet) — uses PowerShell + System.Speech (Windows), `say` (macOS), `spd-say`/`espeak-ng`/`espeak` (Linux). Assistant replies are spoken by `ChatController` → `onAssistantReplyForTts` after each turn, not via `avatar.command`.
- **STT** (`sherpa_speech_manager.dart` + `platform/microphone.dart`): Sherpa-ONNX streaming paraformer via FFI. Model files (`encoder.int8.onnx`, `decoder.int8.onnx`, `tokens.txt`) must sit next to the executable — download from `desktop/` with `powershell -ExecutionPolicy Bypass -File tool/download_model.ps1`. Paddle OCR models: `tool/download_ocr_models.ps1`.

## Server CLI Reference

| Command | Description |
|---------|-------------|
| `hiclaw agent run "<prompt>"` | Single-turn chat |
| `hiclaw agent` | Interactive REPL mode |
| `hiclaw gateway [--port N] [--new-pairing]` | WebSocket gateway (default port from config `gateway.port`) |
| `hiclaw gateway serve [port]` | HTTP service (POST `{"prompt":"..."}`) |
| `hiclaw cron list\|add\|run` | Scheduled jobs (`add "<expr>" "<prompt>"`) |
| `hiclaw config` | Interactive configuration |
| `hiclaw model list\|status` | Model management |
| `hiclaw skill list\|install\|remove\|enable\|disable` | Skill packages |
| `hiclaw wechat setup` | Print WeChat setup instructions |
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
├── src/main.cpp                   # CLI entry point
├── src/cli/cli.cpp                # Subcommand parsing (CLI11)
├── src/agent/agent.cpp            # Agent loop (LLM call → tool call → result → repeat)
├── src/config/config.cpp          # Config loading/saving (hiclaw.json)
├── src/cron/                      # 5-field cron parser + persistent store + scheduler + cron_tool
├── src/memory/file_memory.cpp     # Agent memory: store, recall, forget (file-based)
├── src/net/
│   ├── gateway.cpp                # WebSocket gateway - all RPC methods + event broadcast
│   ├── async_agent.cpp            # Per-session agent manager (LLM streaming)
│   ├── context_classifier.cpp     # Classifies UI structure into plugin-declared tags (local Ollama)
│   ├── http_client.cpp            # HTTP client for LLM provider APIs
│   ├── tool_router.cpp            # Routes tool calls to node sessions
│   ├── intent_router.cpp          # Classifies voice STT results (chat/screenshot/summarize/call)
│   ├── call_handler.cpp           # Incoming call flow: TTS, countdown, answer/reject, spam detect
│   ├── health_monitor.cpp         # Screen-time awareness: late-night usage nags
│   ├── notification_handler.cpp   # Filters important notifications for avatar reactions
│   ├── serve.cpp                  # HTTP server mode
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

All subsystems receive an `EventCallback` to push events to connected clients:

- **IntentRouter** — Classifies voice STT final results server-side. Intents: `Chat`, `ScreenCapture`, `Summarize`, `CallAnswer`, `CallReject`. Keyword matching; also `classify_call_command()` for during-call voice classification.
- **CallHandler** — Incoming call flow: TTS announcement with caller info, countdown timer, spam detection, `call.action` events (answer/reject). Coordinates TTS/STT start/stop with the client.
- **HealthMonitor** — Screen-time wellness: late-night (23:00-6:00) nags via avatar TTS after 2h continuous use, 15-min cooldown. (Android also implements client-side idle wandering + health nags in `avatar/IdleBehaviorScheduler.kt` / `HealthNagScheduler.kt`.)
- **NotificationHandler** — Evaluates `notifications.changed` events, filters important ones (messaging apps, calls), triggers avatar reactions.
- **ContextClassifier** — Classifies a UI structure into content-type tags using a local Ollama model. Tags are not hardcoded; the caller passes available tags aggregated from installed plugin declarations.

### Android App

```
android/app/src/main/java/ai/axiomaster/bonio/
├── MainViewModel.kt / NodeRuntime.kt   # MVVM + dual-session runtime (operator + node)
├── local/LocalEngineController.kt      # Spawns/supervises the embedded libhiclaw.so gateway
├── avatar/                             # Floating pet: PixelAvatarView (sprite sheets), state machine,
│                                       #   CloneManager, CustomSkinManager, idle/health schedulers
├── input/                              # BonioProxyImeService + ImeProxyManager (proxy IME for magic cue)
├── remote/
│   ├── gateway/                        # GatewaySession (WebSocket RPC), DeviceIdentityStore (Ed25519)
│   ├── node/                           # InvokeDispatcher + handlers (camera, location, SMS, screen,
│   │                                   #   contacts/calendar, telephony, notifications, accessibility)
│   ├── chat/                           # ChatController, SpeechToTextManager (platform), SystemTtsManager
│   ├── cue/                            # MagicCueController — answers on-screen questions (tool-backed;
│   │                                   #   OCR degrade path via ML Kit → remote/ocr/ScreenOcrRecognizer)
│   ├── memory/                         # Hierarchical memory L0–L3, UserProfile extraction, charging sync
│   ├── skills/                         # ClawHubClient (skill marketplace), SkillRepository
│   ├── config/                         # ConfigRepository, ServerConfig data classes
│   └── protocol/ theme/ todo/          # Protocol constants (OpenClaw-compatible), theme, todo extraction
├── ui/screens/                         # MainScreen tabs: Chat / Todo / Memory / Personalization / Settings
│                                       #   (+ ServerTab, ModelConfigScreen, ScreenTab, MarketplaceTab)
└── i18n/ util/
```

Magic-cue references: `docs/design/arch/magic-cue-arch-20260905.md`, `arch/20260913-android-magic-cue-ime-proxy-arch.md`, `arch/20260918-screen-ocr-degrade-arch.md`.

### Desktop App (Flutter)

```
desktop/lib/
├── main.dart / avatar_window_app.dart  # Main window + second OS window hosting the pet
├── models/                             # gateway_models, server_config, chat_models, device_identity
├── services/
│   ├── gateway_session.dart            # WebSocket session (protocol v3, reconnection, RPC)
│   ├── chat_controller.dart / node_runtime.dart   # Chat state/streaming; dual-session orchestration
│   ├── hiclaw_process.dart             # Spawns the bundled hiclaw engine
│   ├── note_service.dart / note_export_service.dart  # Memory notes; Obsidian/ZIP export
│   ├── skill_repository.dart / clawhub_client.dart   # Skills + ClawHub marketplace
│   ├── avatar_controller.dart / avatar_command_executor.dart  # Pet state sync + avatar.command execution
│   ├── desktop_tts.dart / sherpa_speech_manager.dart  # TTS / STT (see Desktop quirks above)
│   └── device_identity_store.dart / device_auth_store.dart / config_repository.dart / tray_service.dart
├── platform/                           # win32_* / macos_* behind shared interfaces
│   ├── cdp/                            # Chrome DevTools Protocol browser agent
│   └── ocr/                            # Paddle OCR bridge (native)
├── plugins/                            # PluginManager / PluginHost / PluginBridge; builtin_plugins.dart
├── providers/app_state.dart            # App-level state (Provider pattern)
├── l10n/                               # app_strings.dart
└── ui/screens/                         # chat_tab, memory_tab, marketplace_tab, plugin_tab, ai_lens_screen,
                                        #   reading_companion_screen, search_similar_screen, server_tab,
                                        #   settings_tab, model_config_screen, ocr_result_window
```

### HarmonyOS App

ArkTS under `harmonyos/entry/src/main/ets/`: `gateway/` (GatewaySession), `node/` (handlers + chat), `voice/`, `intent/`, `pages/` (incl. float window), `system/` (device services), `tools/`, `models/`, `protocol/`, `common/`. Talks to the DSH backend below; float-window avatar mirrors Android's.

### DSH Backend (HarmonyOS)

DSH (DeepSeek Harness) runs **on the phone** and replaces hiclaw as the agent backend:

```
avatar ⇄ bonio-app ⇄ (hiclaw protocol, ws://127.0.0.1:10724) ⇄ dsh process / bonio-bridge ⇄ DeepSeek LLM
```

- **`dsh-plugins/bonio-bridge`** — a cordis (DSH) plugin exposing the hiclaw-compatible gateway protocol at `127.0.0.1:10724` (token auth, dual sessions), so bonio-app connects with zero business-code changes. Implements dsh tools: `bonio_node_invoke` (device capabilities → node session), `memo_save`/`memo_list`, `cron_add`/`cron_list`/`cron_remove`/`cron_runs`, `device_info`.
- **`dsh-plugins/bonio-wechat`** — WeChat bridge plugin for DSH.
- **Daemon**: `tools/dsh-daemon.sh` keeps `dsh --profile bonio --port 13082` alive on-device (`/data/local/bin/`), pushed by the deploy scripts.
- **Deploy**: `tools/deploy-bonio-bridge-ohos.sh`, `tools/deploy-bonio-wechat-ohos.sh`, `tools/deploy-dsh-skills-ohos.sh`, `tools/deploy-node-ohos.sh`. On-device skills: `skills/ohos-cli-tool`, `skills/phone-use-harmonyos` (SKILL.md copies in `tools/skills-device/`).

### WeChat Integration (server)

Server bridges WeChat into the agent pipeline via `WeChatAdapter`, orchestrating two channel clients:

- **WeCom** (`WecomWsClient`) — Enterprise WeChat intelligent-bot protocol over `wss://openws.work.weixin.qq.com`. Receives via WebSocket long-connection, replies via `aibot_respond_msg` (stream format). Requires `bot_id` + `bot_secret`.
- **ilink** (`IlinkHttpClient`) — Personal WeChat bot API via HTTP long-polling (`get_updates()`), replies chunked to 3800 chars with retry on `ret=-2`. Requires `token` + `base_url`.

Messages from either channel flow through the same `AsyncAgentManager` → `Agent` loop → tool calls → response pipeline as gateway chat messages. Reply context (callback_req_id for WeCom, user_id for ilink) is tracked per session; msg_id dedup prevents double-processing.

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

### Memory System

- **Server**: file-based agent memory in [`memory/memory.hpp`](server/include/hiclaw/memory/memory.hpp) — `store(key, content, category)`, `recall(query, limit)`, `forget(key)`; categories `core` (always loaded), `daily`, `conversation`, custom; JSON files under `<config_dir>/memory/`. `memo_tool.cpp` exposes `memo_save`/`memo_list` (stored under `~/.bonio/memos` via bonio-bridge).
- **Android**: hierarchical memory **L0–L3** in `remote/memory/` (`UserProfileExtractor`, `ChargingTriggeredSync` extracts profiles while charging) with chat prompt injection. PRD: `docs/design/prd/20260916-hierarchical-memory-l0-l3-prd.md`.

## Gateway Protocol

WebSocket protocol version 3. Frame types: `req` `{type,id,method,params}`, `res` `{type,id,ok,payload,error}`, `event` `{type,event,payload}`.

**Auth**: server compares `params.auth.token`/`params.auth.password` against `gateway.pairing_code` from config; an empty `pairing_code` means open access. Clients also send an Ed25519 device signature, which the server currently does **not** verify.

### Key RPC Methods

| Method | Direction | Description |
|--------|-----------|-------------|
| `connect` | client→server | Handshake (role=operator/node, pairing-code auth, hello payload) |
| `config.get` / `config.set` | client→server | Read config / update + save hiclaw.json |
| `chat.send` | client→server | Send message (+attachments), returns runId (async streaming) |
| `chat.abort` | client→server | Cancel running request |
| `sessions.list/delete/reset/patch` | client→server | Session management |
| `voicewake.get/set` | client→server | Voice wake toggle |
| `node.invoke.result` | client→server | Return tool call result |

### Key Events (server→client)

| Event | Description |
|-------|-------------|
| `connect.challenge` | Auth nonce (sent on connect) |
| `node.invoke.request` | Server asks client to execute a tool |
| `agent` | LLM streaming delta (assistant text / tool calls) |
| `chat` | Chat state updates (final, etc.) |
| `avatar.command` | Pet avatar control (see table above) |
| `notifications.changed` | Device notification stream |
| `tick` | Heartbeat every 30s |

### Tool Call Flow

1. LLM response includes tool_call → server sends `node.invoke.request` to client's `nodeSession`
2. Client's `InvokeDispatcher` routes to handler (camera, location, SMS, screen, etc.)
3. Client sends `node.invoke.result` back to server
4. Server feeds result back to LLM, continues agent loop

## Configuration

Server config lives in `hiclaw.json` (workspace root copy in this repo; default dir `~/.bonio`). Uses **snake_case** field names throughout:

```json
{
  "default_model": "glm-4.7",
  "gateway": {"enabled": true, "host": "0.0.0.0", "port": 10724, "pairing_code": "..."},
  "models": [{"id": "glm-4.7", "provider": "glm", "api_key": "..."}]
}
```

`providers` are built-in constants (defined in `server/include/hiclaw/config/default_providers.hpp`), returned read-only via `config.get`. `models` are user-configurable and persisted to `hiclaw.json`.

## Key Patterns

- **snake_case in protocol/API**: All gateway methods and hiclaw.json fields use snake_case (e.g., `default_model`, `api_key_env`, `base_url`)
- **Dual session architecture**: Android, HarmonyOS, and Desktop all maintain separate operator and node WebSocket connections
- **Protocol-only coupling**: clients never link backend code; any backend speaking gateway v3 (hiclaw, bonio-bridge/DSH) is a drop-in replacement
- **Handler interface pattern**: Feature handlers implement interfaces from `InvokeDispatcher` (Android) for testability
- **Provider adapters**: New LLM providers implement the provider interface in `server/src/providers/`
- **Desktop platform abstraction**: Platform-specific code lives in `desktop/lib/platform/` with `win32_*.dart` / `macos_*.dart` implementations behind shared interfaces (e.g., `screen_capture.dart`, `microphone.dart`, `gui_agent.dart`)
- **16KB page alignment**: bundled native libs (jniLibs, ML Kit OCR ≥16.0.1) must be 16KB-aligned for Android 15+ installers

## Additional Directories

- **`docs/design/`** — `rr/` raw PRDs, `prd/` refined PRDs, `arch/` architecture docs (DSH refactor, Android port, magic cue, OCR degrade, memory, avatar, …)
- **`docs/blog/`** — bilingual tech blog series; **`docs/superpowers/`** — plans/specs notes
- **`skills/`** — Device skills: `phone-use-agent` (C++ CLI for mobile screen automation), `ohos-cli-tool`, `phone-use-harmonyos` (deployed to the on-device DSH)
- **`dsh-plugins/`** — On-device DSH plugins: `bonio-bridge` (hiclaw-compatible gateway), `bonio-wechat` (WeChat bridge)
- **`tools/`** — Deploy scripts (`deploy-*-ohos.sh`), `dsh-daemon.sh`, `bonio-proxy-ime` (C++ proxy IME), `skills-device/` (SKILL.md copies), `hapsigner` binaries if present
- **`assets/`** — Shared animation/OCR/reading assets (Lottie for desktop avatar)
- **`dsh-kun-like-pet/`** — Vendored third-party DSH desktop-pet plugin (reference only; separate upstream project)
- **`tasks/`** — Working PRD notes

## Linting & Formatting

- **Desktop**: `desktop/analysis_options.yaml` — Flutter analyzer with relaxed rules (e.g., `prefer_const_constructors: false`)
- **HarmonyOS**: `harmonyos/code-linter.json5` — security-focused rules (`@security/no-unsafe-*`), TypeScript/Performance recommended
- **Android**: standard Kotlin conventions (no explicit ktlint/detekt config)
- **Server**: no enforced style; follows C++17 conventions with snake_case

## Git Notes

- **Git LFS** tracks `.so` and `.onnx` files (see `.gitattributes`)
- `.bat` / `.cmd` / `.ps1` files **must use CRLF** (enforced via `.gitattributes`)
- Sherpa-ONNX model files must be downloaded separately (see Desktop quirks above)
