# BoJi Desktop macOS 补齐 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring the macOS desktop client to feature parity with Windows by fixing the broken screen capture FFI, adding macOS-specific window/browser operations, and enabling platform-conditional features (AI Lens, Avatar anchoring, Reading Companion, Note Capture).

**Architecture:** The existing `macos_screen_capture.dart` has critical FFI bugs — CFDictionary keys must be CFString objects (not raw C strings), and CoreFoundation is re-opened per call. We fix these by properly using `CFStringCreateWithCString` for dictionary keys and caching the CoreFoundation library handle. Higher-level features (AI Lens, Note Capture, etc.) already have Windows implementations that reference `Win32ScreenCapture` — we introduce a platform abstraction so the same call sites work on both platforms. For Reading Companion, since `webview_windows` is Windows-only, we use `Process.run('open', [url])` to open in the default browser and extract content via `curl` + HTML parsing, or simply show a URL-input-only UI on macOS.

**Tech Stack:** Dart FFI (CoreGraphics, CoreFoundation), AppleScript (browser URL, window resize), macOS entitlements, Flutter multi-window

---

## Task 1: Fix macOS entitlements — add Screen Recording permission

**Files:**
- Modify: `desktop/macos/Runner/DebugProfile.entitlements`
- Modify: `desktop/macos/Runner/Release.entitlements`

**Step 1: Add screen-capture entitlement to DebugProfile.entitlements**

Add `<key>com.apple.security.screen-capture</key><true/>` to the entitlements dict, alongside the existing entries.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.screen-capture</key>
	<true/>
</dict>
</plist>
```

**Step 2: Add screen-capture entitlement to Release.entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.screen-capture</key>
	<true/>
</dict>
</plist>
```

**Step 3: Commit**

```bash
git add desktop/macos/Runner/DebugProfile.entitlements desktop/macos/Runner/Release.entitlements
git commit -m "feat(desktop): add screen-capture entitlement for macOS"
```

---

## Task 2: Rewrite macOS screen capture FFI — fix CoreFoundation usage

The existing code has these bugs:
1. CFDictionary keys are C strings (`'kCGWindowNumber'.toNativeUtf8()`) — they must be CFString objects created via `CFStringCreateWithCString`
2. `CFDataGetBytePtr` is looked up as `CFDataGetBytePointer` (wrong symbol)
3. CoreFoundation library is opened fresh for every function call
4. `ScreenCaptureResult` class is only defined in `win32_screen_capture.dart` — macOS file can't use it independently

**Files:**
- Rewrite: `desktop/lib/platform/macos_screen_capture.dart`

**Step 1: Rewrite the entire file with correct FFI**

The rewrite must:
- Cache CoreFoundation and CoreGraphics `DynamicLibrary` handles as static fields
- Use `CFStringCreateWithCString` + `kCFAllocatorDefault` to create CFString keys for dictionary lookups, and release them afterward
- Look up `CFDataGetBytePtr` with the correct symbol name
- Use `CFNumberGetValue` to extract int values from CFNumber objects (CGWindowListCopyWindowInfo returns CFNumber, not raw Int64)
- Use `CFStringGetCStringPtr` or `CFStringGetCString` to extract string values from CFString objects
- Keep the same public API: `captureScreen()`, `captureWindow(id)`, `getWindowList()`, `getWindowTitle(id)`, `isBrowserWindow(id)`, `getBrowserUrl(id)`, `getDpiScaleForWindow(id)`, `resizeWindow(id, x, y, w, h)`, `getMonitorWorkArea(id)`
- Define `ScreenCaptureResult`, `WindowInfo` classes locally (or import from shared location) with the same interface as the Win32 version

Key FFI functions needed from CoreFoundation:
```
CFStringCreateWithCString(allocator, cStr, encoding) -> CFStringRef
CFNumberGetValue(number, type, outPtr) -> bool
CFStringGetCStringPtr(cfString, encoding) -> char*
CFStringGetLength(cfString) -> CFIndex
CFDataGetBytePtr(data) -> UInt8*   (correct symbol name!)
CFDataGetLength(data) -> CFIndex
CFArrayGetCount(array) -> CFIndex
CFArrayGetValueAtIndex(array, idx) -> void*
CFDictionaryGetValue(dict, key) -> void*
CFRelease(cf) -> void
```

From CoreGraphics:
```
CGMainDisplayID() -> uint32
CGDisplayPixelsHigh(display) -> uint32
CGDisplayPixelsWide(display) -> uint32
CGDisplayCreateImage(display) -> CGImageRef
CGWindowListCreateImage(screen, option, windowID, imageOption) -> CGImageRef
CGImageGetWidth(image) -> size_t
CGImageGetHeight(image) -> size_t
CGImageGetDataProvider(image) -> CGDataProviderRef
CGDataProviderCopyData(provider) -> CFDataRef
CGImageRelease(image) -> void
CGWindowListCopyWindowInfo(option, relativeToWindow) -> CFArrayRef
```

For `getWindowList()` the correct approach:
```dart
static List<WindowInfo>? getWindowList() {
  final windowList = CGWindowListCopyWindowInfo(
    kCGWindowListOptionOnScreenOnly, kCGNullWindow);
  if (windowList == nullptr) return null;

  final count = CFArrayGetCount(windowList);
  final windows = <WindowInfo>[];

  for (var i = 0; i < count; i++) {
    final dict = CFArrayGetValueAtIndex(windowList, i);
    if (dict == nullptr) continue;

    // Create CFString keys for lookup
    final kNumber = CFStringCreateWithCString(
        kCFAllocatorDefault, 'kCGWindowNumber'.toNativeUtf8(), kCFStringEncodingUTF8);
    final kOwnerName = CFStringCreateWithCString(
        kCFAllocatorDefault, 'kCGWindowOwnerName'.toNativeUtf8(), kCFStringEncodingUTF8);
    final kName = CFStringCreateWithCString(
        kCFAllocatorDefault, 'kCGWindowName'.toNativeUtf8(), kCFStringEncodingUTF8);

    final windowID = _getInt(dict, kNumber);
    final ownerName = _getString(dict, kOwnerName);
    final windowName = _getString(dict, kName);

    CFRelease(kNumber);
    CFRelease(kOwnerName);
    CFRelease(kName);

    if (windowID != null && ownerName != null) {
      windows.add(WindowInfo(
        windowID: windowID,
        ownerName: ownerName,
        windowName: windowName,
        bounds: null, // Parse bounds dict separately if needed
      ));
    }
  }

  CFRelease(windowList);
  return windows;
}
```

For `_getInt` helper:
```dart
static int? _getInt(Pointer<Void> dict, Pointer<Void> cfKey) {
  final value = CFDictionaryGetValue(dict, cfKey);
  if (value == nullptr) return null;
  // CGWindowListCopyWindowInfo stores numbers as CFNumber
  final out = calloc<Int64>();
  final ok = CFNumberGetValue(value, kCFNumberSInt64Type, out.cast<Void>());
  final result = ok ? out.value : null;
  calloc.free(out);
  return result;
}
```

For `_getString` helper:
```dart
static String? _getString(Pointer<Void> dict, Pointer<Void> cfKey) {
  final value = CFDictionaryGetValue(dict, cfKey);
  if (value == nullptr) return null;
  // Try fast path first (CFStringGetCStringPtr)
  final fastPtr = CFStringGetCStringPtr(value, kCFStringEncodingUTF8);
  if (fastPtr != nullptr) {
    return fastPtr.cast<Utf8>().toDartString();
  }
  // Slow path: allocate buffer and copy
  final len = CFStringGetLength(value);
  if (len <= 0) return null;
  final buf = calloc<Uint8>(len * 4 + 1); // UTF-8 can be up to 4 bytes per char
  final ok = CFStringGetCString(value, buf.cast<Void>(), len * 4 + 1, kCFStringEncodingUTF8);
  if (!ok) { calloc.free(buf); return null; }
  final str = buf.cast<Utf8>().toDartString();
  calloc.free(buf);
  return str;
}
```

Remove the global `kCGWindowNumber`, `kCGWindowOwnerName`, `kCGWindowName`, `kCGWindowBounds` static allocations — they were wrong (C strings instead of CFStrings) and leaked memory.

**Step 2: Commit**

```bash
git add desktop/lib/platform/macos_screen_capture.dart
git commit -m "fix(desktop): rewrite macOS screen capture FFI with correct CoreFoundation usage"
```

---

## Task 3: Implement macOS browser URL extraction via AppleScript

**Files:**
- Modify: `desktop/lib/platform/macos_screen_capture.dart` — implement `getBrowserUrl()`

**Step 1: Implement getBrowserUrl using AppleScript**

The method already exists but returns `null`. Replace with:

```dart
static String? getBrowserUrl(int windowID) {
  if (windowID == 0) return null;
  try {
    final windows = getWindowList();
    if (windows == null) return null;

    // Find the window by ID to get owner name
    String? ownerName;
    for (final w in windows) {
      if (w.windowID == windowID) {
        ownerName = w.ownerName;
        break;
      }
    }
    if (ownerName == null) return null;

    final lower = ownerName.toLowerCase();
    String? appleScriptAppName;

    if (lower.contains('safari')) {
      appleScriptAppName = 'Safari';
    } else if (lower.contains('google chrome')) {
      appleScriptAppName = 'Google Chrome';
    } else if (lower.contains('firefox')) {
      appleScriptAppName = 'Firefox';
    } else if (lower.contains('microsoft edge')) {
      appleScriptAppName = 'Microsoft Edge';
    } else if (lower.contains('brave')) {
      appleScriptAppName = 'Brave';
    } else if (lower.contains('arc')) {
      appleScriptAppName = 'Arc';
    }

    if (appleScriptAppName == null) return null;

    // Use AppleScript to get the active tab URL
    final script = '''
      tell application "$appleScriptAppName"
        ${appleScriptAppName == 'Safari' ? 'set theURL to URL of current tab of front window' : ''}
        ${appleScriptAppName == 'Google Chrome' ? 'set theURL to URL of active tab of front window' : ''}
        ${appleScriptAppName == 'Firefox' ? 'set theURL to URL of active tab of front window' : ''}
        ${appleScriptAppName == 'Microsoft Edge' ? 'set theURL to URL of active tab of front window' : ''}
        ${appleScriptAppName == 'Brave' ? 'set theURL to URL of active tab of front window' : ''}
        ${appleScriptAppName == 'Arc' ? 'set theURL to URL of active tab of front window' : ''}
      end tell
      return theURL
    ''';

    final result = Process.runSync('osascript', ['-e', script]);
    if (result.exitCode == 0) {
      final url = result.stdout.toString().trim();
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
      }
    }
    return null;
  } catch (e) {
    debugPrint('MacosScreenCapture.getBrowserUrl: failed: $e');
    return null;
  }
}
```

Note: This is synchronous (`Process.runSync`) to match the Win32 API contract. For browsers not supporting AppleScript URL access (e.g., Firefox may restrict), fall back to regex extraction from window title.

**Step 2: Commit**

```bash
git add desktop/lib/platform/macos_screen_capture.dart
git commit -m "feat(desktop): implement macOS browser URL extraction via AppleScript"
```

---

## Task 4: Implement macOS window resize/move via AppleScript + AXUIElement

**Files:**
- Modify: `desktop/lib/platform/macos_screen_capture.dart` — implement `resizeWindow()`
- Modify: `desktop/lib/platform/macos_screen_capture.dart` — fix `getMonitorWorkArea()`

**Step 1: Implement resizeWindow**

```dart
static bool resizeWindow(int windowID, int x, int y, int w, int h) {
  if (windowID == 0) return false;
  try {
    // Get the PID for this window ID
    final windows = getWindowList();
    if (windows == null) return false;

    String? ownerName;
    for (final win in windows) {
      if (win.windowID == windowID) {
        ownerName = win.ownerName;
        break;
      }
    }
    if (ownerName == null || ownerName.isEmpty) return false;

    // Use AppleScript to set window bounds
    // Note: requires Accessibility permission
    final script = '''
      tell application "System Events"
        tell process "$ownerName"
          set position of front window to {$x, $y}
          set size of front window to {$w, $h}
        end tell
      end tell
    ''';

    final result = Process.runSync('osascript', ['-e', script]);
    return result.exitCode == 0;
  } catch (e) {
    debugPrint('MacosScreenCapture.resizeWindow: failed: $e');
    return false;
  }
}
```

**Step 2: Fix getMonitorWorkArea to use NSScreen via CoreGraphics**

```dart
static List<int>? getMonitorWorkArea(int windowID) {
  try {
    final displayID = CGDisplayMain();
    final screenWidth = CGDisplayPixelsWide(displayID);
    final screenHeight = CGDisplayPixelsHigh(displayID);

    // Use systcl to get menu bar height (default 24-25px)
    // CGDisplayBounds gives full screen, we need visible area
    // On macOS, the menu bar is typically at the top
    // Use a more accurate approach: get the Dock position
    int menuBarHeight = 25; // default
    try {
      final result = Process.runSync('defaults', ['read', '-g', 'AppleMenuBarHeight']);
      if (result.exitCode == 0) {
        menuBarHeight = int.tryParse(result.stdout.toString().trim()) ?? 25;
      }
    } catch (_) {}

    // Check dock position to determine work area
    int dockHeight = 0;
    bool dockAtBottom = true;
    try {
      final result = Process.runSync('defaults', ['read', 'com.apple.dock', 'orientation']);
      if (result.exitCode == 0) {
        dockAtBottom = result.stdout.toString().trim() == 'bottom';
      }
      final sizeResult = Process.runSync('defaults', ['read', 'com.apple.dock', 'tilesize']);
      if (sizeResult.exitCode == 0) {
        dockHeight = (double.tryParse(sizeResult.stdout.toString().trim()) ?? 48).round() + 4;
      }
      // Check if dock is hidden
      final hideResult = Process.runSync('defaults', ['read', 'com.apple.dock', 'autohide']);
      if (hideResult.exitCode == 0 && hideResult.stdout.toString().trim() == '1') {
        dockHeight = 0;
      }
    } catch (_) {}

    final top = menuBarHeight;
    final height = screenHeight - menuBarHeight - (dockAtBottom ? dockHeight : 0);

    return [0, top, screenWidth, height];
  } catch (e) {
    debugPrint('MacosScreenCapture.getMonitorWorkArea: $e');
    return null;
  }
}
```

**Step 3: Commit**

```bash
git add desktop/lib/platform/macos_screen_capture.dart
git commit -m "feat(desktop): implement macOS window resize and accurate work area"
```

---

## Task 5: Create platform-abstracted screen capture interface

Currently `note_service.dart`, `ai_lens_screen.dart`, and other files import `win32_screen_capture.dart` directly. We need a factory so call sites don't need platform checks.

**Files:**
- Create: `desktop/lib/platform/screen_capture.dart`
- Modify: `desktop/lib/services/note_service.dart` — change import
- Modify: `desktop/lib/ui/screens/ai_lens_screen.dart` — change import + remove Windows-only guard

**Step 1: Create screen_capture.dart factory**

```dart
import 'dart:io';
import 'dart:typed_data';

export 'win32_screen_capture.dart' show ScreenCaptureResult, WindowInfo;
export 'macos_screen_capture.dart' show MacosScreenCapture;

// Re-export ScreenCaptureResult from whichever platform defines it
// Both platforms define it identically
export 'win32_screen_capture.dart';

import 'win32_screen_capture.dart';
import 'macos_screen_capture.dart';

/// Platform-agnostic screen capture API.
/// Delegates to the correct platform implementation at runtime.
class ScreenCapture {
  /// Captures the primary screen. Returns null on failure.
  static ScreenCaptureResult? captureScreen() {
    if (Platform.isWindows) {
      return Win32ScreenCapture.captureScreen();
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.captureScreen();
    }
    return null;
  }

  /// Captures a specific window by platform-specific ID.
  static ScreenCaptureResult? captureWindow(int windowId) {
    if (Platform.isWindows) {
      return Win32ScreenCapture.captureWindow(windowId);
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.captureWindow(windowId);
    }
    return null;
  }

  static String getWindowTitle(int windowId) {
    if (Platform.isWindows) {
      return Win32ScreenCapture.getWindowTitle(windowId);
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.getWindowTitle(windowId);
    }
    return '';
  }

  static bool isBrowserWindow(int windowId) {
    if (Platform.isWindows) {
      return Win32ScreenCapture.isBrowserWindow(windowId);
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.isBrowserWindow(windowId);
    }
    return false;
  }

  static String? getBrowserUrl(int windowId) {
    if (Platform.isWindows) {
      return Win32ScreenCapture.getBrowserUrl(windowId);
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.getBrowserUrl(windowId);
    }
    return null;
  }

  static double getDpiScaleForWindow(int windowId) {
    if (Platform.isWindows) {
      return Win32ScreenCapture.getDpiScaleForWindow(windowId);
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.getDpiScaleForWindow(windowId);
    }
    return 1.0;
  }

  static bool resizeWindow(int windowId, int x, int y, int w, int h) {
    if (Platform.isWindows) {
      return Win32ScreenCapture.resizeWindow(windowId, x, y, w, h);
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.resizeWindow(windowId, x, y, w, h);
    }
    return false;
  }

  static List<int>? getMonitorWorkArea(int windowId) {
    if (Platform.isWindows) {
      return Win32ScreenCapture.getMonitorWorkArea(windowId);
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.getMonitorWorkArea(windowId);
    }
    return null;
  }

  static List<WindowInfo>? getWindowList() {
    if (Platform.isWindows) {
      // Win32 doesn't have getWindowList, return null
      return null;
    }
    if (Platform.isMacOS) {
      return MacosScreenCapture.getWindowList();
    }
    return null;
  }
}
```

Note: `MacosScreenCapture` must also define a `ScreenCaptureResult` class with the same interface (or we extract it to a shared file). The simplest approach: have `macos_screen_capture.dart` define its own `ScreenCaptureResult` and `WindowInfo` classes matching the Win32 signatures, and the factory re-exports the Win32 types. Since both classes have identical fields/methods, they are structurally compatible in Dart.

**Step 2: Update note_service.dart import**

Change:
```dart
import '../platform/win32_screen_capture.dart';
```
To:
```dart
import '../platform/screen_capture.dart';
```

And update all references from `Win32ScreenCapture.` to `ScreenCapture.`.

**Step 3: Update ai_lens_screen.dart**

Change:
```dart
import '../../platform/win32_screen_capture.dart';
```
To:
```dart
import '../../platform/screen_capture.dart';
```

Remove the `if (!Platform.isWindows)` guard in `AiLensScreen.show()`:
```dart
static Future<Uint8List?> show(BuildContext context) async {
  // Works on both Windows and macOS now
  final capture = ScreenCapture.captureScreen();
  if (capture == null) {
    debugPrint('AiLens: screen capture failed');
    return null;
  }
  // ... rest unchanged
}
```

**Step 4: Commit**

```bash
git add desktop/lib/platform/screen_capture.dart desktop/lib/services/note_service.dart desktop/lib/ui/screens/ai_lens_screen.dart
git commit -m "refactor(desktop): create platform-abstracted ScreenCapture factory"
```

---

## Task 6: Enable macOS AI Lens screenshot selection

**Files:**
- Modify: `desktop/lib/avatar_window_app.dart` — remove Windows-only guard in `_enterLensMode`

**Step 1: Find and update _enterLensMode**

The avatar window's AI Lens menu action likely calls `Win32ScreenCapture.captureScreen()` directly or has a Windows-only guard. Search for `_enterLensMode` in `avatar_window_app.dart` and update it to use the platform-abstracted `ScreenCapture.captureScreen()`.

If there's a `if (!Platform.isWindows) return;` guard, remove it. The `AiLensScreen.show()` method from Task 5 already handles the platform check internally.

**Step 2: Commit**

```bash
git add desktop/lib/avatar_window_app.dart
git commit -m "feat(desktop): enable AI Lens on macOS"
```

---

## Task 7: Enable macOS Avatar window anchoring and foreground polling

**Files:**
- Modify: `desktop/lib/avatar_window_app.dart` — implement macOS foreground window tracking in `_pollForeground()`

**Step 1: Implement macOS foreground window tracking**

The current `_pollForeground()` method at ~line 508 has `if (!Platform.isWindows) return;`. We need to add macOS equivalent logic using `MacosScreenCapture.getWindowList()` and `NSWorkspace` via FFI or AppleScript.

The key operations needed:
1. **Get foreground window ID**: Use `CGWindowListCopyWindowInfo` with `kCGWindowListOptionOnScreenOnly` and filter for the frontmost window (lowest window number, excluding our own windows). We can use the already-working `getWindowList()` from `MacosScreenCapture`.

2. **Get window rect (position + size)**: Parse the `kCGWindowBounds` dictionary from `CGWindowListCopyWindowInfo`. Need to implement `_getDict` properly to extract `{Height, Width, X, Y}` from the bounds CFDictionary.

3. **Check if window is fullscreen**: A window is fullscreen if its bounds match the screen bounds exactly.

4. **Check if window is minimized**: Not applicable on macOS (minimized windows don't appear in `kCGWindowListOptionOnScreenOnly`).

The implementation approach:

```dart
void _pollForeground() {
  if (!mounted) return;
  if (!Platform.isWindows && !Platform.isMacOS) return;
  if (_interactionActive) return;

  if (Platform.isMacOS) {
    _pollForegroundMacOS();
    return;
  }

  // ... existing Windows code ...
}

void _pollForegroundMacOS() {
  final windows = MacosScreenCapture.getWindowList();
  if (windows == null || windows.isEmpty) return;

  // Find the frontmost non-self, non-system window
  // CGWindowListCopyWindowInfo returns windows in front-to-back order
  for (final w in windows) {
    // Skip our own app's windows
    if (w.ownerName == 'boji_desktop') continue;
    // Skip system windows
    if (w.ownerName == 'Window Server' || w.ownerName == 'SystemUIServer') continue;
    if (w.windowName == null || w.windowName!.isEmpty) continue;
    if (w.bounds == null) continue;

    final bounds = w.bounds!;
    if (bounds['Width']! < 100 || bounds['Height']! < 100) continue;

    final fgWindowId = w.windowID;

    // Check fullscreen
    final screenW = MacosScreenCapture.getDpiScaleForWindow(0); // Not ideal, use display size
    final displayID = MacosScreenCapture.CGDisplayMain();
    // ... fullscreen check, anchoring logic ...

    // Found our foreground window
    _handleForegroundWindowMacOS(fgWindowId, w);
    return;
  }
}
```

**Important**: This task requires implementing `_getDict` in `MacosScreenCapture` to properly parse the `kCGWindowBounds` CFDictionary. The bounds dict has keys `Height`, `Width`, `X`, `Y` (as CFString keys → CFNumber values).

**Step 2: Commit**

```bash
git add desktop/lib/avatar_window_app.dart desktop/lib/platform/macos_screen_capture.dart
git commit -m "feat(desktop): enable avatar window anchoring on macOS"
```

---

## Task 8: Enable macOS Reading Companion (URL-only mode)

Since `webview_windows` is Windows-only (WebView2), the reading companion cannot use embedded webviews on macOS. Two options:
- **Option A**: Open URL in default browser (`Process.run('open', [url])`) and let user read there, with a simplified local note editor
- **Option B**: Use `url_launcher` to open the URL, then use `curl` to fetch the HTML content for extraction, and show the markdown editor locally without WebView

**Files:**
- Modify: `desktop/lib/ui/screens/reading_companion_screen.dart` — add macOS path
- Modify: `desktop/lib/main.dart` — conditional import/guard for reading companion window

**Step 1: Add macOS-compatible reading companion**

For macOS, instead of using WebView2:
1. Fetch page content via `Process.runSync('curl', ['-sL', url])` or `HttpClient`
2. Parse HTML to extract text and headings (use simple regex or string parsing — no need for full HTML parser)
3. Show the same markdown editor UI but without embedded webview (use a plain `TextField` or `TextFormField` with multi-line support instead of `Webview`)

The simplest approach: at the top of `reading_companion_screen.dart`, conditionally import:
```dart
import 'dart:io';
```

Then in `_startExtraction()`:
```dart
Future<void> _startExtraction() async {
  setState(() { _phase = _LoadPhase.connecting; _errorText = null; });

  if (Platform.isMacOS) {
    await _startExtractionMacOS();
    return;
  }
  // ... existing WebView extraction for Windows ...
}

Future<void> _startExtractionMacOS() async {
  try {
    setState(() => _phase = _LoadPhase.extracting);

    // Fetch page HTML
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(_activeUrl));
    final response = await request.close();
    final html = await response.transform(utf8.decoder).join();
    client.close();

    // Parse headings with regex
    final headingRegex = RegExp(r'<h([1-6])[^>]*>(.*?)</h\1>', dotAll: true);
    final headings = <_HeadingInfo>[];
    for (final match in headingRegex.allMatches(html)) {
      final level = int.parse(match.group(1)!);
      final text = _stripHtmlTags(match.group(2)!).trim();
      if (text.isNotEmpty) {
        headings.add(_HeadingInfo(level: level, text: text, id: ''));
      }
    }

    // Extract text from body
    final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true).firstMatch(html);
    final bodyHtml = bodyMatch?.group(1) ?? html;
    // Remove script, style tags
    final cleaned = bodyHtml
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final text = cleaned.substring(0, cleaned.length > 50000 ? 50000 : cleaned.length);

    // Extract title
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true).firstMatch(html);
    final title = _stripHtmlTags(titleMatch?.group(1) ?? '').trim();

    setState(() { _headings = headings; _phase = _LoadPhase.summarizing; });
    await _analyzeContent(text, title);
  } catch (e) {
    debugPrint('Reading extraction (macOS) failed: $e');
    if (mounted) setState(() => _errorText = 'Extraction error: $e');
  }
}

String _stripHtmlTags(String html) {
  return html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'").replaceAll('&nbsp;', ' ');
}
```

For the editor on macOS, replace `Webview(_editorController)` with a simple multi-line `TextField` wrapped in a scroll view. Add a `_buildMacOSEditor()` method.

**Step 2: Commit**

```bash
git add desktop/lib/ui/screens/reading_companion_screen.dart
git commit -m "feat(desktop): enable reading companion on macOS with curl-based extraction"
```

---

## Task 9: Enable macOS Note Capture (记一记)

**Files:**
- Modify: `desktop/lib/services/note_service.dart` — already updated in Task 5 to use `ScreenCapture` factory
- Modify: `desktop/lib/avatar_window_app.dart` — ensure note_capture action works on macOS

**Step 1: Verify note capture flow works on macOS**

After Task 5, `note_service.dart` uses `ScreenCapture.captureWindow()` which delegates to `MacosScreenCapture`. The `_handleNoteCapture()` in `avatar_window_app.dart` sends `note_capture` with `hwnd` (which on macOS is a window ID). Verify the full chain:

1. Avatar menu "记一记" → `_handleNoteCapture()` → sends `{'hwnd': _anchoredHwnd}` to main window
2. Main window receives `note_capture` → calls `NoteService.captureWindow(hwnd)`
3. `captureWindow` calls `ScreenCapture.captureWindow(hwnd)` → delegates to `MacosScreenCapture.captureWindow(windowID)`

The `_anchoredHwnd` on macOS should be set by the foreground polling from Task 7. If the foreground polling isn't ready yet, note capture will report "no anchored window" — that's acceptable for now.

**Step 2: Commit** (if any changes needed)

```bash
git add desktop/lib/services/note_service.dart desktop/lib/avatar_window_app.dart
git commit -m "feat(desktop): enable note capture on macOS"
```

---

## Task 10: Build verification and final integration test

**Files:**
- All modified files

**Step 1: Verify `flutter build macos` compiles**

```bash
cd desktop && flutter build macos
```

Expected: BUILD SUCCEEDED with no errors.

**Step 2: Verify `flutter build windows` still compiles** (if on Windows or CI)

```bash
cd desktop && flutter build windows
```

Expected: BUILD SUCCEEDED — the refactoring should not break Windows.

**Step 3: Manual test checklist on macOS**

- [ ] App launches, connects to gateway
- [ ] Avatar appears on dock area
- [ ] AI Lens menu works: captures screen, shows selection overlay, returns cropped image
- [ ] "记一记" menu captures the foreground window (if anchored)
- [ ] Reading companion window opens, URL input works, content extraction succeeds
- [ ] Browser URL extraction works for Safari/Chrome (test via note capture)

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat(desktop): complete macOS parity — screen capture, AI Lens, reading companion"
```

---

## Dependency Graph

```
Task 1 (entitlements) ──► Task 2 (FFI rewrite) ──► Task 3 (browser URL) ──► Task 5 (factory)
                          │                                                  │
                          └──► Task 4 (resize/workarea) ─────────────────────┘
                                                                             │
                    Task 5 (factory) ──► Task 6 (AI Lens)                   │
                                      ──► Task 7 (avatar anchoring)         │
                                      ──► Task 8 (reading companion)        │
                                      ──► Task 9 (note capture)             │
                                                                             │
                    Task 10 (build verification) ◄── all tasks              │
```

## Notes

- **Accessibility permission**: Tasks 3 and 4 (AppleScript for browser URL and window resize) require the user to grant Accessibility permission in System Preferences > Security & Privacy. The app should show a helpful message if the permission is missing.
- **Screen Recording permission**: Task 1 adds the entitlement, but the user must also grant Screen Recording permission in System Preferences for the capture to work.
- **WebView2 limitation**: The reading companion on macOS uses HTTP fetch + regex HTML parsing instead of embedded WebView. This is less robust than the Windows WebView2 approach but avoids adding a heavy macOS webview dependency. If needed later, consider adding `webview_flutter_wkwebview` as a macOS webview solution.
- **Testing**: Since these are all platform-specific FFI operations, they can only be tested on a macOS device. No unit tests are feasible without mocking the OS APIs.
