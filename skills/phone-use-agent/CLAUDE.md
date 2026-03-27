# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) working with code in this repository.

## Project Overview

Phone Use Agent - A native CLI binary that runs directly on mobile devices to execute natural language commands through automated UI interactions.

**Supported Platforms:**
- **HarmonyOS** - Runs on-device using `uitest` commands
- **Android** - Runs on-device using `input` commands

**Key difference from PC-based solutions:** This runs entirely on-device, not through adb/hdc commands from a PC. This means lower latency and no PC dependency.

## Project Structure

```
phone-use/
├── cmake/                    # Platform-specific CMake configurations
│   ├── HarmonyOS.cmake       # HarmonyOS build settings
│   ├── Android.cmake         # Android build settings
│   └── Host.cmake            # Host development build
├── include/                  # Header files
│   ├── core/                 # Core abstractions
│   │   └── TaskExecutor.h
│   ├── platform/             # Platform interface
│   │   └── Platform.h
│   ├── Config.h
│   ├── AutoGLMClient.h
│   ├── CliArgs.h
│   └── ...
├── src/
│   ├── core/                 # Core implementations
│   │   └── TaskExecutor.cpp
│   ├── platform/             # Platform-specific implementations
│   │   ├── Platform.h        # Interface definition
│   │   ├── PlatformFactory.cpp
│   │   ├── harmonyos/
│   │   │   ├── HarmonyOSPlatform.h
│   │   │   └── HarmonyOSPlatform.cpp
│   │   └── android/
│   │       ├── AndroidPlatform.h
│   │       └── AndroidPlatform.cpp
│   ├── main.cpp
│   ├── AutoGLMClient.cpp
│   ├── ConfigManager.cpp
│   └── CliArgs.cpp
├── test/                     # Test files
├── build_harmonyos.ps1       # Windows build script for HarmonyOS
├── build_harmonyos.sh        # Linux build script for HarmonyOS
├── build_android.ps1         # Windows build script for Android
└── build_android.sh          # Linux build script for Android
```

## Build Commands

### HarmonyOS Build

**Windows PowerShell:**
```powershell
./build_harmonyos.ps1 Release
```

**Linux/Bash:**
```bash
chmod +x build_harmonyos.sh
./build_harmonyos.sh Release
```

**Manual:**
```bash
cmake -B build-harmonyos -G Ninja \
    -DBUILD_HARMONYOS=ON \
    -DCMAKE_MAKE_PROGRAM="D:/tools/commandline-tools-windows/sdk/default/openharmony/native/build-tools/cmake/bin/ninja.exe"

D:/tools/commandline-tools-windows/sdk/default/openharmony/native/build-tools/cmake/bin/ninja.exe -C build-harmonyos
```

### Android Build

**Windows PowerShell:**
```powershell
./build_android.ps1 Release
```

**Linux/Bash:**
```bash
chmod +x build_android.sh
./build_android.sh Release
```

**Manual:**
```bash
cmake -B build-android \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-24 \
    -DBUILD_ANDROID=ON

cmake --build build-android
```

## Deployment

### HarmonyOS
```powershell
# From PowerShell
hdc file send 'build-harmonyos/bin/phone-use-agent' '/data/local/bin/phone-use-agent'
hdc shell 'chmod +x /data/local/bin/phone-use-agent'
```

### Android
```powershell
# From PowerShell
adb push build-android/bin/phone-use-agent /data/local/tmp/
adb shell 'chmod +x /data/local/tmp/phone-use-agent'
```

## Usage

### HarmonyOS
```bash
/data/local/bin/phone-use-agent --apikey "your-bigmodel-api-key" --task "打开美团搜索附近的火锅店"
```

### Android
```bash
/data/local/tmp/phone-use-agent --apikey "your-bigmodel-api-key" --task "打开微信发送消息给小明"
```

### Common Options
```bash
--help              Show help message
--version           Show version
--apikey KEY        BigModel API key (required)
--task "COMMAND"    Natural language task to execute
--verbose           Enable verbose output
--max-step N        Maximum steps (default: 20)
```

## Exit Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | SUCCESS | Task completed |
| 1 | GENERAL_FAILURE | Unspecified error |
| 2 | INVALID_ARGS | Missing/invalid arguments |
| 4 | TASK_FAILED | Task execution failed |
| 5 | TIMEOUT | Exceeded max steps |
| 10 | NETWORK_ERROR | HTTP/network error |
| 11 | INITIALIZATION_FAILED | Module init failed |

## Architecture

### Platform Abstraction Layer

The codebase uses a platform abstraction layer to support multiple platforms:

```
IPlatform (interface)
    ├── HarmonyOSPlatform
    │   ├── takeScreenshot() -> snapshot_display
    │   ├── tap() -> /bin/uitest uiInput click
    │   ├── swipe() -> /bin/uitest uiInput swipe
    │   └── launchApp() -> aa start
    │
    └── AndroidPlatform
        ├── takeScreenshot() -> screencap
        ├── tap() -> input tap
        ├── swipe() -> input swipe
        └── launchApp() -> am start
```

### Agent Loop

```
TaskExecutor::executeTask()
    ↓
while (step_count < max_steps && !completed):
    1. platform_->takeScreenshot() → screenshot.jpeg
    2. base64_encode(screenshot)
    3. glm_client_->processCommand() → GLM API
    4. parseActionString(response.action)
       - do(action="tap", element="[500,300]")
       - finish(message="Task done")
    5. platform_->tap/swipe/inputText/etc.
    6. platform_->sleepMs(1000)
    ↓
return Task with status
```

### Supported Actions

| Action | GLM Format | HarmonyOS Command | Android Command |
|--------|------------|-------------------|-----------------|
| Tap | `do(action="tap", element="[x,y]")` | `/bin/uitest uiInput click x y` | `input tap x y` |
| Type | `do(action="type", text="hello")` | `/bin/uitest uiInput text "hello"` | `input text "hello"` |
| Swipe | `do(action="swipe", start="[x,y]", end="[x,y]")` | `/bin/uitest uiInput swipe` | `input swipe` |
| Long Press | `do(action="long press", element="[x,y]")` | `/bin/uitest uiInput longClick` | `input swipe (same point)` |
| Double Tap | `do(action="double tap", element="[x,y]")` | `/bin/uitest uiInput doubleClick` | Two quick taps |
| Launch | `do(action="launch", app="WeChat")` | `aa start -a -b` | `am start -n` |
| Back | `do(action="back")` | `/bin/uitest uiInput keyEvent Back` | `input keyevent KEYCODE_BACK` |
| Home | `do(action="home")` | `/bin/uitest uiInput keyEvent Home` | `input keyevent KEYCODE_HOME` |
| Wait | `do(action="wait", duration="1 seconds")` | `usleep()` | `std::this_thread::sleep_for` |
| Finish | `finish(message="Done")` | Exit loop | Exit loop |

## Configuration

Config file: `/data/local/.phone-use-agent/phone-use-agent.conf`

```json
{
  "glm_api_key": "your-bigmodel-api-key",
  "glm_endpoint": "https://open.bigmodel.cn/api/paas/v4/chat/completions",
  "system_prompt": "You are a phone automation assistant..."
}
```

## Key Implementation Notes

### HarmonyOS-specific
1. **musl libc**: Use `usleep()` instead of `std::this_thread::sleep_for`
2. **Screenshot extension**: Must be `.jpeg` for `snapshot_display`
3. **Deploy via PowerShell**: hdc has path issues in Git Bash

### Android-specific
1. **bionic libc**: `std::this_thread::sleep_for` works fine
2. **Screenshot**: Uses `screencap -p` command
3. **Input**: Uses standard `input` commands

### Common
1. **Coordinate scaling**: GLM uses 0-1000, device uses actual pixels
2. **API Key**: Passed via `--apikey` CLI arg or config file
3. **HTTP Client**: Uses libcurl loaded dynamically

## Tests

```bash
./build/bin/test_cli           # CLI argument parser tests
./build/bin/test_agent_flow    # End-to-end agent flow
./build/bin/test_autoglm_logic # AutoGLM integration
./build/bin/test_glm           # GLM API tests
./build/bin/test_executor_ut   # TaskExecutor unit tests
./build/bin/network_test       # Network functionality
./build/bin/size_check         # Binary size validation
```

## Reference

- `reference/Open-AutoGLM/` - PC-based reference using hdc/adb commands
- BigModel API: https://open.bigmodel.cn/api/paas/v4/chat/completions
