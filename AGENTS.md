# AGENTS.md

Guidance for AI coding agents working in this repository. Related instruction file: `CLAUDE.md` (canonical, more detailed build docs and design-doc workflow — keep consistent with it).

请你永远永远记住，
1. 每次修改完成代码后都编译一下，确保代码可以正常编译通过；
2. 每次开发完一个功能，都git提交一下，确保不会丢失；
3. HarmonyOS HAP 任务完成后，必须进行全量编译（`hvigorw clean assembleHap`），使用 hapsigner（`tools/` 下若有二进制则用之，未提交）以 `harmonyos/root_float_signing/` 中的 `system_core` profile（`msdpdemo-system-core-profile.p7b`）签名，并通过 HDC 安装到已连接设备；若设备不可用，明确报告安装阻塞原因。

## Project Overview

Bonio (HiClaw) is an AI companion: one backend, four clients, one protocol. There is **no CI, no root package manifest** — build each module directly.

- **server/** — C++17 WebSocket gateway (HiClaw): LLM provider adapters, tool routing, cron, memory, WeChat bridge
- **desktop/** — Flutter client for Windows/macOS (chat, avatar, plugins, voice, memory)
- **android/** — Kotlin/Jetpack Compose app, package **`ai.axiomaster.bonio`**, compileSdk 36 / minSdk 31 / Java 17
- **harmonyos/** — ArkTS port; its agent backend is the on-device **DSH daemon + `dsh-plugins/bonio-bridge`** (WebSocket at `127.0.0.1:10724`), **not** hiclaw

All clients speak **WebSocket protocol v3** and maintain **dual WebSocket sessions**: `operatorSession` (user commands: chat, config) and `nodeSession` (server-initiated tool calls: camera, location, SMS, screen). Mobile-only capabilities respond `UNSUPPORTED_COMMAND` on the desktop node session. App↔backend coupling is **protocol-only** — clients never link backend code; hiclaw is embedded as `libhiclaw.so` (Android, exec'd from `nativeLibraryDir`) or a spawned binary (desktop), and replaced by DSH on HarmonyOS.

## Build Commands

### Server (C++17, CMake)

```bash
cd server && scripts\build-win-amd64.bat        # Windows x64
cd server && scripts/build-macos-arm64.sh       # macOS arm64
cd server && scripts/build-linux-amd64.sh       # Linux amd64 (apt: cmake ninja-build libssl-dev)
cd server && scripts/build-android-arm64-v8a.sh # requires ANDROID_NDK_HOME
cd server && scripts/build-ohos-arm64.sh        # requires OHOS_NDK_HOME
# Output each: server/build/<platform>/hiclaw + copied to server/bin/hiclaw(.exe)
```

Third-party deps are **vendored** in `server/third_party/` (CLI11, spdlog, nlohmann_json, libhv, mbedtls, websocketpp, asio, linenoise-ng). Must be cloned before building — CMake fails with exact `git clone` URLs.

### Unified scripts (root `scripts/`)

```bash
scripts/build-and-run.sh            # macOS/Linux: build server + desktop, bundle hiclaw, launch
scripts\build-and-run.bat --ninja   # Windows: same; --ninja uses Ninja instead of VS generator
# Options (all scripts): --skip-server  --skip-desktop  --clean

scripts/build-server.sh             # hiclaw only → server/bin/
scripts/build-desktop.sh --run      # Flutter desktop + bundle hiclaw (server must be built first)
```

Windows `.bat` variants accept `--ninja` (recommended — avoids `.vcxproj` generation).

### Tests

```bash
cd android && ./gradlew test
cd android && ./gradlew test --tests "ai.axiomaster.bonio.UserProfileExtractionTest"  # single class
cd desktop && flutter test
cd desktop && flutter test test/services/foo_test.dart          # single file
cd desktop && flutter test --plain-name "some test name"        # single test
cd harmonyos && hvigorw test
```

Server has **no test suite** — verification is compiling and running it.

### Desktop app (Flutter)

```bash
cd desktop && flutter pub get && flutter run -d macos   # or -d windows
cd desktop && flutter build macos                        # release build
./scripts/bundle-hiclaw.sh <app_bundle_path>             # bundle hiclaw (server built first)
# Windows: powershell -File scripts\bundle-hiclaw.ps1
```

Quirks:

- The pet lives in a **second OS window** via `desktop_multi_window` + `window_manager`; state is pushed from `AvatarController` (`invokeMethod('sync', …)`), drag deltas return via `avatarPan`.
- `desktop_multi_window` is a **vendored local package** (`desktop/packages/desktop_multi_window`, referenced by path in pubspec) — not from pub.dev.
- **TTS** (`desktop/lib/services/desktop_tts.dart`): deliberately **no `flutter_tts` plugin** (avoids Windows CMake/NuGet) — uses PowerShell + System.Speech (Windows), `say` (macOS), `spd-say`/`espeak-ng` (Linux). Assistant replies are spoken by `ChatController` → `onAssistantReplyForTts`, not via `avatar.command`.
- **STT** (`sherpa_speech_manager.dart` + `lib/platform/microphone.dart`): Sherpa-ONNX streaming paraformer via FFI. Model files (`encoder.int8.onnx`, `decoder.int8.onnx`, `tokens.txt`) must sit next to the executable — download with `powershell -ExecutionPolicy Bypass -File tool/download_model.ps1` (from `desktop/`). Paddle OCR models: `tool/download_ocr_models.ps1`.

### Android app

```bash
cd android && ./gradlew assembleDebug
```

The hiclaw engine is embedded as `android/app/src/main/jniLibs/arm64-v8a/libhiclaw.so` (arm64 only; the `lib*.so` name is required for APK packaging, and `useLegacyPackaging = true` extracts it so `local/LocalEngineController.kt` can exec it from `nativeLibraryDir`). After a `build-android-arm64-v8a.sh` run:

```bash
cp server/build/android-arm64-v8a/hiclaw android/app/src/main/jniLibs/arm64-v8a/libhiclaw.so
```

Chat STT uses the **platform `SpeechRecognizer`** only (`remote/chat/SpeechToTextManager.kt`) — the offline Sherpa-ONNX engine was cut from the v1 build (APK 345MB → 114MB); the avatar uses sprite sheets, not Lottie (Lottie deps were stripped; desktop still uses `lottie`). Bundled native libs must be **16KB-page-aligned** (Android 15+ installers reject 4KB).

### HarmonyOS app

```bash
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk   # API 26
cd harmonyos && hvigorw --mode module -p product=default assembleHap
```

- No hvigorw wrapper is vendored — use DevEco's bundled hvigor.
- Builds are **unsigned** (no signingConfigs committed). After any HAP task: full `hvigorw clean assembleHap` → sign with hapsigner using the `system_core` profile in `harmonyos/root_float_signing/` → `hdc install -r` onto a connected device (report the blocker if no device).

## Server CLI & Environment

| Command | Description |
|---------|-------------|
| `hiclaw agent run "prompt"` | Single-turn chat |
| `hiclaw agent` | Interactive REPL |
| `hiclaw gateway [--port N] [--new-pairing]` | WebSocket gateway (default port from `hiclaw.json` `gateway.port`) |
| `hiclaw gateway serve [port]` | HTTP service (POST `{"prompt":"..."}`) |
| `hiclaw cron list\|add\|run` | Scheduled jobs (`add "<expr>" "<prompt>"`) |
| `hiclaw config` | Interactive configuration |
| `hiclaw model list\|status` | Model management |
| `hiclaw skill list\|install\|remove\|enable\|disable` | Skill packages |
| `hiclaw wechat setup` | Print WeChat setup instructions |

Global options: `--config-dir <path>` (default `~/.bonio`), `--log-level`.

| Variable | Description |
|----------|-------------|
| `HICLAW_WORKSPACE` | Read config from `$HICLAW_WORKSPACE/hiclaw.json` |
| `hiclaw_log` | Log level: off/error/warn/info/debug |
| `hiclaw_default_model` | Override config's `default_model` |
| API keys | Per model via `api_key_env` field (e.g. `GLM_API_KEY`); falls back to `OPENAI_API_KEY` |

## Configuration

`hiclaw.json` (workspace root copy in this repo; default dir `~/.bonio`). **snake_case everywhere** — this is the protocol/API convention too:

```json
{
  "default_model": "deepseek-chat",
  "gateway": {"enabled": true, "host": "0.0.0.0", "port": 10724, "pairing_code": "..."},
  "models": [{"id": "deepseek-chat", "provider": "openai_compatible", "base_url": "https://api.deepseek.com/v1", "api_key": "..."}]
}
```

The checked-in root `hiclaw.json` currently ships `deepseek-chat` (`openai_compatible`) plus an `ollama` model, with no `pairing_code`. `providers` are built-in constants (`server/include/hiclaw/config/default_providers.hpp`), read-only via `config.get`. `models` are user-configurable and persisted. Gateway auth: `params.auth.token` checked against `gateway.pairing_code`; empty `pairing_code` = open access. Clients also send an Ed25519 device signature, which the server currently does **not** verify.

## Architecture Notes

- **Server entry**: `server/src/main.cpp` (CLI11 subcommands), `src/cli/cli.cpp` for parsing. Agent loop: `agent/agent.cpp` (LLM call → tool call → result → repeat). `net/gateway.cpp` (websocketpp) owns RPC methods and event broadcast; `net/async_agent.cpp` manages per-session streaming agents.
- **Server subsystems** (all take an `EventCallback`): `intent_router` (voice STT → chat/screenshot/summarize/call-answer/reject), `call_handler` (incoming call TTS/countdown/spam detect), `idle_manager` (avatar wandering when idle), `health_monitor` (late-night screen-time nags), `notification_handler`, `wechat_adapter` + `wecom_ws_client` + `ilink_http_client`.
- **WeChat integration**: two channels — WeCom (bot_id + bot_secret, WebSocket) and ilink (token + base_url, HTTP long-polling). Both feed into the same agent pipeline as gateway chat messages; dedup by msg_id.
- **Avatar commands**: server drives pet via `avatar.command` events built in `server/include/hiclaw/net/avatar_command.hpp` — `setState`, `moveTo`, `setBubble`, `setBubbleCountdown`, `clearBubble`, `tts`/`stopTts`, `playSound`, `setColorFilter`, `setPosition`, `performAction`, `sequence`.
- **Gateway protocol v3**: frames `req`/`res`/`event`. Key RPC: `connect` (pairing-code auth + hello), `config.get/set`, `chat.send` (returns runId, async streaming), `chat.abort`, `sessions.list/delete/reset/patch`, `node.invoke.result` (plus `chat.history`, `cron.*`, `memo.*`, `skills.*`, `voicewake.get/set`). Key events: `connect.challenge`, `node.invoke.request`, `agent` (streaming deltas), `chat`, `tick` (30s heartbeat). Tool call flow: LLM tool_call → `node.invoke.request` on nodeSession → client handler → `node.invoke.result` → agent loop continues.
- **Desktop platform abstraction**: platform code behind shared interfaces in `desktop/lib/platform/` (`win32_*`/`macos_*` impls; CDP browser agent in `platform/cdp/`). Plugins: `desktop/lib/plugins/` (`PluginManager`/`PluginHost`/`PluginBridge`, built-ins in `builtin_plugins.dart`).

## Other Top-Level Directories

Beyond the four clients:

- **`dsh-plugins/`** — on-device DSH (DeepSeek Harness, HarmonyOS's replacement for hiclaw) plugins, TypeScript/Node: `bonio-bridge` (exposes the hiclaw-compatible gateway at `127.0.0.1:10724` so the ArkTS app connects unchanged) and `bonio-wechat`. Each has its own `test/` and `build/`.
- **`tools/`** — device deploy scripts: `deploy-bonio-bridge-ohos.sh`, `deploy-bonio-wechat-ohos.sh`, `deploy-dsh-skills-ohos.sh`, `deploy-node-ohos.sh`, and `dsh-daemon.sh` (keeps `dsh --profile bonio --port 13082` alive on-device). Also `make-skin-pack.py` (packages an Android avatar skin into `dist/skins/*.skin.zip`, format v1) and `skills-device/` (SKILL.md copies).
- **`skills/`** — device skills: `phone-use-agent` (a **separate** C++ project with its own `CLAUDE.md` and `test/` CMake suite — on-device UI automation via `uitest`/`input`), `ohos-cli-tool`, `phone-use-harmonyos`.
- **`dsh-kun-like-pet/`** — vendored third-party DSH desktop-pet plugin, **reference only**; do not edit (separate upstream project).
- **`tasks/`** — working PRD notes; **`docs/`** is documentation-heavy, not a build input.

## Generated Artifacts / Ignored Paths

Build outputs are gitignored — never commit them: `server/build/`, `server/bin/`, `dist/` (generated skin packs), `hapsigner`, `harmonyos/.hvigor|oh_modules|build`, Flutter `desktop/build|.dart_tool`, `android/**/build`. `.so`/`.onnx` are tracked via **Git LFS** (uncommitted `hapsigner`/tool binaries are expected).

## Design Document Workflow

Feature docs follow a three-stage pipeline under `docs/design/`:

1. Raw PRD (user-authored): `rr/{feature}-{date}.md` — **do not modify without user confirmation**
2. Refined PRD: `prd/{feature}-prd-{date}.md`
3. Architecture: `arch/{feature}-arch-{date}.md`

## Key Patterns & Gotchas

- **snake_case in all gateway methods and config fields** (e.g. `default_model`, `api_key_env`, `base_url`).
- **Dual session architecture** on every client: separate operator and node WebSocket connections.
- Feature handlers implement interfaces from `InvokeDispatcher` (Android) for testability.
- New LLM providers implement the provider interface in `server/src/providers/`.
- `.bat`/`.cmd`/`.ps1` files must use **CRLF** (enforced via `.gitattributes`).
- Server follows C++17 with snake_case; no enforced formatter. Desktop analyzer rules are relaxed (`desktop/analysis_options.yaml`); HarmonyOS linting is security-focused (`harmonyos/code-linter.json5`).
- Android instrumentation/unit tests live under `android/app/src/test/` and `androidTest/` (package `ai.axiomaster.bonio`).
