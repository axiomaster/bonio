# Ollama gemma4:e4b Default Model + Embedded Server Auto-Start

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Configure HiClaw to default to Ollama `gemma4:e4b` model, and embed the hiclaw binary inside the desktop Flutter app so it auto-starts on launch.

**Architecture:** The server already has full Ollama support. For task 1 we change the default model string from `llama3.2` to `gemma4:e4b` and update the provider heuristic. For task 2 we add a `HiclawProcess` service in the desktop app that discovers/extracts the hiclaw binary from the app bundle and launches it as a child process before connecting.

**Tech Stack:** C++ (server config), Dart/Flutter (desktop process management), Platform-specific app bundling (macOS `.app` / Windows build).

---

### Task 1: Change default model to gemma4:e4b

**Files:**
- Modify: `server/src/config/config.cpp:263`
- Modify: `server/src/config/config.cpp:273-285` (`ensure_default_in_models`)

**Step 1: Update default model string**

In `server/src/config/config.cpp`, line 263, change:
```cpp
out.default_model = "llama3.2";
```
to:
```cpp
out.default_model = "gemma4:e4b";
```

**Step 2: Fix provider heuristic for colon-separated model IDs**

The `ensure_default_in_models` function (line 279) uses `find('-')` to split model ID into provider prefix. But `gemma4:e4b` uses `:` as separator. The heuristic extracts provider by splitting on `-`, which would give `gemma4:e4b` as provider — wrong. Since the model ID doesn't contain a known provider prefix, we should default to `"ollama"` for models without a recognized provider.

Replace the provider extraction logic in `ensure_default_in_models`:

```cpp
void ensure_default_in_models(Config& cfg) {
  if (cfg.default_model.empty()) return;
  for (const auto& e : cfg.models)
    if (e.id == cfg.default_model) return;
  ModelEntry e;
  e.id = cfg.default_model;
  e.model_id = cfg.default_model;
  // If the model ID starts with a known provider prefix followed by '-',
  // extract it; otherwise default to "ollama" (local models).
  size_t hyphen = cfg.default_model.find('-');
  if (hyphen != std::string::npos && hyphen > 0) {
    std::string candidate = cfg.default_model.substr(0, hyphen);
    // Check if candidate matches a known provider
    bool known = false;
    for (std::size_t i = 0; i < kDefaultProvidersCount; ++i) {
      if (candidate == kDefaultProviders[i].id) { known = true; break; }
    }
    e.provider = known ? candidate : "ollama";
  } else {
    e.provider = "ollama";
  }
  cfg.models.push_back(e);
}
```

**Step 3: Build and verify**

```bash
cd server && scripts/build-linux-amd64.sh --clean
# or on macOS/Linux:
cd server && mkdir -p build/debug && cd build/debug && cmake -DCMAKE_BUILD_TYPE=Debug ../.. && make -j$(nproc)
```

Verify the binary starts and shows the correct default:
```bash
./build/debug/hiclaw model list
# Should show gemma4:e4b with ollama provider
```

**Step 4: Commit**

```bash
git add server/src/config/config.cpp
git commit -m "feat(server): change default model to gemma4:e4b with ollama provider"
```

---

### Task 2: Create HiclawProcess service

**Files:**
- Create: `desktop/lib/services/hiclaw_process.dart`

**Step 1: Create the HiclawProcess service**

This service manages the hiclaw server as a child process. It:
1. Locates the hiclaw binary inside the app bundle (macOS) or next to the executable (Windows)
2. Extracts it from assets on first run if not already present
3. Starts `hiclaw gateway` with the configured port
4. Monitors the process and provides status
5. Stops the process on app exit

```dart
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class HiclawProcess with ChangeNotifier {
  Process? _process;
  bool _isRunning = false;
  int _port = 10724;
  String? _error;

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get error => _error;

  /// Resolves the path to the hiclaw binary.
  /// macOS: <app_bundle>/Contents/Resources/hiclaw
  /// Windows: <exe_dir>/hiclaw.exe
  Future<String> _resolveBinaryPath() async {
    if (Platform.isMacOS) {
      final exePath = Platform.resolvedExecutable;
      // exePath = /path/to/BoJi Desktop.app/Contents/MacOS/boji_desktop
      final resourcesDir = exePath
          .substring(0, exePath.lastIndexOf('/'))
          .replaceFirst('/MacOS', '/Resources');
      final bundled = '$resourcesDir/hiclaw';
      if (await File(bundled).exists()) return bundled;

      // Fallback: extract from app support dir
      final supportDir = await getApplicationSupportDirectory();
      final localBin = '${supportDir.path}/boji/hiclaw';
      if (await File(localBin).exists()) return localBin;
      throw FileSystemException('hiclaw binary not found');
    } else if (Platform.isWindows) {
      final exeDir = Platform.resolvedExecutable
          .substring(0, Platform.resolvedExecutable.lastIndexOf('\\'));
      final bundled = '$exeDir\\hiclaw.exe';
      if (await File(bundled).exists()) return bundled;

      final supportDir = await getApplicationSupportDirectory();
      final localBin = '${supportDir.path}\\boji\\hiclaw.exe';
      if (await File(localBin).exists()) return localBin;
      throw FileSystemException('hiclaw binary not found');
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// Start hiclaw gateway on the given port.
  Future<void> start({int port = 10724}) async {
    if (_isRunning) return;
    _port = port;
    _error = null;

    try {
      final binary = await _resolveBinaryPath();
      final result = await Process.start(
        binary,
        ['gateway', '--port', port.toString()],
        workingDirectory: null,
        environment: {'HICLAW_WORKSPACE': await _workspaceDir()},
      );

      _process = result;
      _isRunning = true;
      notifyListeners();

      // Monitor stdout/stderr for debugging
      result.stdout
          .transform(const SystemEncoding().decoder)
          .listen((data) => debugPrint('[hiclaw] $data'));
      result.stderr
          .transform(const SystemEncoding().decoder)
          .listen((data) => debugPrint('[hiclaw:err] $data'));

      // Handle unexpected exit
      result.exitCode.then((code) {
        _isRunning = false;
        _process = null;
        if (code != 0) {
          _error = 'hiclaw exited with code $code';
        }
        notifyListeners();
      });
    } catch (e) {
      _error = e.toString();
      debugPrint('[hiclaw] Failed to start: $e');
    }
  }

  Future<String> _workspaceDir() async {
    final supportDir = await getApplicationSupportDirectory();
    return '${supportDir.path}/boji/hiclaw';
  }

  /// Stop the hiclaw process gracefully.
  Future<void> stop() async {
    if (_process == null) return;
    _process!.kill();
    await _process!.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _process!.kill(ProcessSignal.sigkill);
      return -1;
    });
    _process = null;
    _isRunning = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
```

**Step 2: Commit**

```bash
git add desktop/lib/services/hiclaw_process.dart
git commit -m "feat(desktop): add HiclawProcess service for managing hiclaw server lifecycle"
```

---

### Task 3: Integrate HiclawProcess into AppState

**Files:**
- Modify: `desktop/lib/providers/app_state.dart`

**Step 1: Add HiclawProcess to AppState**

Add the import and field at the top of `app_state.dart`:

```dart
import '../services/hiclaw_process.dart';
```

Add field in the `AppState` class (after `final SpeechToTextManager _sttManager`):

```dart
final HiclawProcess hiclawProcess = HiclawProcess();
```

**Step 2: Auto-start hiclaw on connect and stop on disconnect**

Replace the `connectToGateway()` method to start hiclaw before connecting:

```dart
Future<void> connectToGateway() async {
  if (_host.trim().isEmpty) {
    // Auto-start local hiclaw if no host configured
    if (!hiclawProcess.isRunning) {
      await hiclawProcess.start(port: _port);
    }
    _host = '127.0.0.1';
  }
  runtime.connect(
    profile: _gatewayProfile,
    host: _host.trim(),
    port: _port,
    token: _token.trim().isEmpty ? null : _token.trim(),
    tls: _tls,
  );
}
```

Update `disconnectFromGateway()`:

```dart
Future<void> disconnectFromGateway() async {
  runtime.disconnect();
  await hiclawProcess.stop();
}
```

**Step 3: Stop hiclaw on app dispose**

In the `dispose()` method, add before `super.dispose()`:

```dart
hiclawProcess.dispose();
```

**Step 4: Commit**

```bash
git add desktop/lib/providers/app_state.dart
git commit -m "feat(desktop): auto-start hiclaw server when connecting"
```

---

### Task 4: Add auto-connect on first launch

**Files:**
- Modify: `desktop/lib/providers/app_state.dart` (`_loadPrefs`)

**Step 1: Auto-connect after loading prefs**

When there's no saved host (first launch), automatically start hiclaw and connect. Add at the end of `_loadPrefs()`:

```dart
// Auto-start local hiclaw on first launch (no saved host)
if (_host.trim().isEmpty || _host == '127.0.0.1') {
  unawaited(_autoStartAndConnect());
}
```

Add the helper method:

```dart
Future<void> _autoStartAndConnect() async {
  if (!hiclawProcess.isRunning) {
    await hiclawProcess.start(port: _port);
  }
  // Wait briefly for server to bind the port
  await Future.delayed(const Duration(milliseconds: 500));
  _host = '127.0.0.1';
  connectToGateway();
}
```

**Step 2: Commit**

```bash
git add desktop/lib/providers/app_state.dart
git commit -m "feat(desktop): auto-start and connect to local hiclaw on first launch"
```

---

### Task 5: Bundle hiclaw binary in macOS app

**Files:**
- Modify: `desktop/macos/Runner.xcodeproj/project.pbxproj` (or use a post-build script)
- Create: `desktop/scripts/bundle-hiclaw.sh`

**Step 1: Create a build helper script**

Create `desktop/scripts/bundle-hiclaw.sh`:

```bash
#!/usr/bin/env bash
# Bundle hiclaw binary into the macOS app bundle.
# Usage: scripts/bundle-hiclaw.sh <path_to_app_bundle>
#
# Prerequisite: server must be built for the current platform.
set -e

BUNDLE="${1:?Usage: bundle-hiclaw.sh <app_bundle_path>}"
RESOURCES="$BUNDLE/Contents/Resources"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HICLAW_BIN="$PROJECT_ROOT/server/build/mac/hiclaw"

if [[ ! -f "$HICLAW_BIN" ]]; then
  echo "Error: hiclaw binary not found at $HICLAW_BIN"
  echo "Build the server first: cd server && mkdir -p build/mac && cd build/mac && cmake -DCMAKE_BUILD_TYPE=Release ../.. && make"
  exit 1
fi

cp "$HICLAW_BIN" "$RESOURCES/hiclaw"
chmod +x "$RESOURCES/hiclaw"
echo "Bundled hiclaw -> $RESOURCES/hiclaw"
```

**Step 2: Commit**

```bash
git add desktop/scripts/bundle-hiclaw.sh
git commit -m "feat(desktop): add script to bundle hiclaw into macOS app"
```

---

### Task 6: Bundle hiclaw binary in Windows app

**Files:**
- Create: `desktop/scripts/bundle-hiclaw.ps1`
- Modify: `desktop/windows/CMakeLists.txt` (optional, to include binary)

**Step 1: Create a Windows bundling script**

Create `desktop/scripts/bundle-hiclaw.ps1`:

```powershell
# Bundle hiclaw.exe into the Windows build output.
# Usage: scripts/bundle-hiclaw.ps1 [-BuildDir <path>]
param(
  [string]$BuildDir = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\..\.."
$HiclawBin = "$ProjectRoot\server\build\win-x64\hiclaw.exe"

if (-not (Test-Path $HiclawBin)) {
  Write-Error "hiclaw.exe not found at $HiclawBin. Build the server first."
  exit 1
}

if ($BuildDir -eq "") {
  $BuildDir = "$ProjectRoot\desktop\build\windows\x64\runner\Release"
}

if (-not (Test-Path $BuildDir)) {
  Write-Error "Build directory not found: $BuildDir"
  exit 1
}

Copy-Item $HiclawBin "$BuildDir\hiclaw.exe" -Force
Write-Host "Bundled hiclaw.exe -> $BuildDir\hiclaw.exe"
```

**Step 2: Commit**

```bash
git add desktop/scripts/bundle-hiclaw.ps1
git commit -m "feat(desktop): add script to bundle hiclaw into Windows app"
```

---

### Task 7: Create macOS server build script

**Files:**
- Create: `server/scripts/build-macos.sh`

**Step 1: Create macOS build script**

The server doesn't have a macOS-specific build script. Create `server/scripts/build-macos.sh`:

```bash
#!/usr/bin/env bash
# Build hiclaw for macOS (arm64 or x86_64)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/mac"
BUILD_TYPE="${HICLAW_BUILD_TYPE:-Release}"

echo "============================================"
echo "Building HiClaw for macOS"
echo "============================================"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" "$PROJECT_ROOT"
make -j$(sysctl -n hw.ncpu)

echo ""
echo "Build OK! Binary: $BUILD_DIR/hiclaw"
```

**Step 2: Test build**

```bash
cd server && scripts/build-macos.sh
```

**Step 3: Commit**

```bash
git add server/scripts/build-macos.sh
git commit -m "feat(server): add macOS build script"
```
