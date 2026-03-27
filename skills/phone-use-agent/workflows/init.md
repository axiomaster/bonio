---
description: Initialize the project and get started
---

# Project Initialization Workflow

This workflow sets up the development environment and provides a project overview.

## Steps

// turbo
1. Verify the OHOS NDK path exists at `D:/tools/commandline-tools-windows/sdk/default/openharmony/native`. If not, ask the user to update the path in `CMakeLists.txt`.

// turbo
2. Create the build directory if it doesn't exist:
   ```bash
   mkdir -p build
   ```

// turbo
3. Configure the CMake project:
   ```bash
   cd build && cmake ..
   ```

// turbo
4. Build the project:
   ```bash
   cd build && cmake --build .
   ```

## Project Overview

**OpenClawService** is a HarmonyOS accessibility/automation service written in C++17, cross-compiled for aarch64-linux-ohos.

### Key Components

| File | Purpose |
|------|---------|
| `src/main.cpp` | Application entry point |
| `src/AutoGLMClient.cpp` | Client for AutoGLM AI integration |
| `src/AppManager.cpp` | Application lifecycle management |
| `src/AccessibilityHelper.cpp` | Accessibility service integration |
| `src/UIInspector.cpp` | UI tree inspection utilities |
| `src/HttpClient.cpp` | HTTP networking client |
| `src/MessageMonitor.cpp` | Monitor for incoming messages |
| `src/TaskExecutor.cpp` | Execute automation tasks |
| `src/ConfigManager.cpp` | Configuration management |
| `src/CangLianHelper.cpp` | CangLian (苍链) integration |

### Build Requirements

- CMake 3.16+
- HarmonyOS NDK (configured in `CMakeLists.txt`)
- C++17 compatible toolchain (LLVM/Clang from OHOS NDK)

### Build Artifacts

- `build/bin/openclaw_service` - Main service executable
- `build/bin/test_canglian` - CangLian functionality test
- `build/bin/test_send_message` - Message sending test
