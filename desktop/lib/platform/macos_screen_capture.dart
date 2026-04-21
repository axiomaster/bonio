import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'screen_capture_types.dart';

// ---------------------------------------------------------------------------
// CoreFoundation / CoreGraphics constants
// ---------------------------------------------------------------------------

const int _kCFAllocatorDefault = 0; // nullptr
const int _kCFStringEncodingUTF8 = 0x08000100;
const int _kCFNumberSInt64Type = 4;

const int _kCGWindowListOptionOnScreenOnly = 0x00000001;
const int _kCGWindowListOptionIncludingWindow = 0x00000002;
const int _kCGWindowImageBoundsIgnoreFraming = 0x00000001;
const int _kCGNullWindow = 0;

// ---------------------------------------------------------------------------
// Cached DynamicLibrary handles
// ---------------------------------------------------------------------------

DynamicLibrary? _cfLib;
DynamicLibrary? _cgLib;

DynamicLibrary get _cf {
  _cfLib ??= DynamicLibrary.open(
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
  return _cfLib!;
}

DynamicLibrary get _cg {
  _cgLib ??= DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
  return _cgLib!;
}

// ---------------------------------------------------------------------------
// FFI typedefs – CoreFoundation
// ---------------------------------------------------------------------------

typedef _CFStringCreateWithCStringNative = Pointer<Void> Function(
    Pointer<Void> alloc, Pointer<Char> cStr, Uint32 encoding);
typedef _CFStringCreateWithCStringDart = Pointer<Void> Function(
    Pointer<Void> alloc, Pointer<Char> cStr, int encoding);

typedef _CFNumberGetValueNative = Int8 Function(
    Pointer<Void> number, Int32 theType, Pointer<Void> outValue);
typedef _CFNumberGetValueDart = int Function(
    Pointer<Void> number, int theType, Pointer<Void> outValue);

typedef _CFStringGetCStringPtrNative = Pointer<Char> Function(
    Pointer<Void> theString, Uint32 encoding);
typedef _CFStringGetCStringPtrDart = Pointer<Char> Function(
    Pointer<Void> theString, int encoding);

typedef _CFStringGetLengthNative = IntPtr Function(Pointer<Void> theString);
typedef _CFStringGetLengthDart = int Function(Pointer<Void> theString);

typedef _CFStringGetCStringNative = Int8 Function(
    Pointer<Void> theString, Pointer<Char> buffer, IntPtr bufferSize, Uint32 encoding);
typedef _CFStringGetCStringDart = int Function(
    Pointer<Void> theString, Pointer<Char> buffer, int bufferSize, int encoding);

typedef _CFDataGetBytePtrNative = Pointer<Uint8> Function(Pointer<Void> data);
typedef _CFDataGetBytePtrDart = Pointer<Uint8> Function(Pointer<Void> data);

typedef _CFDataGetLengthNative = IntPtr Function(Pointer<Void> data);
typedef _CFDataGetLengthDart = int Function(Pointer<Void> data);

typedef _CFArrayGetCountNative = IntPtr Function(Pointer<Void> array);
typedef _CFArrayGetCountDart = int Function(Pointer<Void> array);

typedef _CFArrayGetValueAtIndexNative = Pointer<Void> Function(
    Pointer<Void> array, IntPtr idx);
typedef _CFArrayGetValueAtIndexDart = Pointer<Void> Function(
    Pointer<Void> array, int idx);

typedef _CFDictionaryGetValueNative = Pointer<Void> Function(
    Pointer<Void> dict, Pointer<Void> key);
typedef _CFDictionaryGetValueDart = Pointer<Void> Function(
    Pointer<Void> dict, Pointer<Void> key);

typedef _CFReleaseNative = Void Function(Pointer<Void> cf);
typedef _CFReleaseDart = void Function(Pointer<Void> cf);

// ---------------------------------------------------------------------------
// FFI typedefs – CoreGraphics
// ---------------------------------------------------------------------------

typedef _CGMainDisplayIDNative = Uint32 Function();
typedef _CGMainDisplayIDDart = int Function();

typedef _CGDisplayPixelsHighNative = Uint32 Function(Uint32 display);
typedef _CGDisplayPixelsHighDart = int Function(int display);

typedef _CGDisplayPixelsWideNative = Uint32 Function(Uint32 display);
typedef _CGDisplayPixelsWideDart = int Function(int display);

typedef _CGDisplayCreateImageNative = Pointer<Void> Function(Uint32 display);
typedef _CGDisplayCreateImageDart = Pointer<Void> Function(int display);

typedef _CGWindowListCreateImageNative = Pointer<Void> Function(
    Uint32 screenRect, Int32 listOption, Uint32 windowID, Int32 imageOption);
typedef _CGWindowListCreateImageDart = Pointer<Void> Function(
    int screenRect, int listOption, int windowID, int imageOption);

typedef _CGImageGetWidthNative = IntPtr Function(Pointer<Void> image);
typedef _CGImageGetWidthDart = int Function(Pointer<Void> image);

typedef _CGImageGetHeightNative = IntPtr Function(Pointer<Void> image);
typedef _CGImageGetHeightDart = int Function(Pointer<Void> image);

typedef _CGImageGetDataProviderNative = Pointer<Void> Function(
    Pointer<Void> image);
typedef _CGImageGetDataProviderDart = Pointer<Void> Function(
    Pointer<Void> image);

typedef _CGDataProviderCopyDataNative = Pointer<Void> Function(
    Pointer<Void> provider);
typedef _CGDataProviderCopyDataDart = Pointer<Void> Function(
    Pointer<Void> provider);

typedef _CGImageReleaseNative = Void Function(Pointer<Void> image);
typedef _CGImageReleaseDart = void Function(Pointer<Void> image);

typedef _CGWindowListCopyWindowInfoNative = Pointer<Void> Function(
    Int32 option, Uint32 relativeToWindow);
typedef _CGWindowListCopyWindowInfoDart = Pointer<Void> Function(
    int option, int relativeToWindow);

// ---------------------------------------------------------------------------
// Resolved FFI function lookups (lazy, cached via getter)
// ---------------------------------------------------------------------------

// We resolve each function once and store the Dart-side callable.

final _cfStringCreateWithCString = _cf.lookupFunction<
    _CFStringCreateWithCStringNative, _CFStringCreateWithCStringDart>(
  'CFStringCreateWithCString',
);

final _cfNumberGetValue = _cf.lookupFunction<
    _CFNumberGetValueNative, _CFNumberGetValueDart>(
  'CFNumberGetValue',
);

final _cfStringGetCStringPtr = _cf.lookupFunction<
    _CFStringGetCStringPtrNative, _CFStringGetCStringPtrDart>(
  'CFStringGetCStringPtr',
);

final _cfStringGetLength = _cf.lookupFunction<
    _CFStringGetLengthNative, _CFStringGetLengthDart>(
  'CFStringGetLength',
);

final _cfStringGetCString = _cf.lookupFunction<
    _CFStringGetCStringNative, _CFStringGetCStringDart>(
  'CFStringGetCString',
);

final _cfDataGetBytePtr = _cf.lookupFunction<
    _CFDataGetBytePtrNative, _CFDataGetBytePtrDart>(
  'CFDataGetBytePtr',
);

final _cfDataGetLength = _cf.lookupFunction<
    _CFDataGetLengthNative, _CFDataGetLengthDart>(
  'CFDataGetLength',
);

final _cfArrayGetCount = _cf.lookupFunction<
    _CFArrayGetCountNative, _CFArrayGetCountDart>(
  'CFArrayGetCount',
);

final _cfArrayGetValueAtIndex = _cf.lookupFunction<
    _CFArrayGetValueAtIndexNative, _CFArrayGetValueAtIndexDart>(
  'CFArrayGetValueAtIndex',
);

final _cfDictionaryGetValue = _cf.lookupFunction<
    _CFDictionaryGetValueNative, _CFDictionaryGetValueDart>(
  'CFDictionaryGetValue',
);

final _cfRelease = _cf.lookupFunction<
    _CFReleaseNative, _CFReleaseDart>(
  'CFRelease',
);

final _cgMainDisplayID = _cg.lookupFunction<
    _CGMainDisplayIDNative, _CGMainDisplayIDDart>(
  'CGMainDisplayID',
);

final _cgDisplayPixelsHigh = _cg.lookupFunction<
    _CGDisplayPixelsHighNative, _CGDisplayPixelsHighDart>(
  'CGDisplayPixelsHigh',
);

final _cgDisplayPixelsWide = _cg.lookupFunction<
    _CGDisplayPixelsWideNative, _CGDisplayPixelsWideDart>(
  'CGDisplayPixelsWide',
);

final _cgDisplayCreateImage = _cg.lookupFunction<
    _CGDisplayCreateImageNative, _CGDisplayCreateImageDart>(
  'CGDisplayCreateImage',
);

final _cgWindowListCreateImage = _cg.lookupFunction<
    _CGWindowListCreateImageNative, _CGWindowListCreateImageDart>(
  'CGWindowListCreateImage',
);

final _cgImageGetWidth = _cg.lookupFunction<
    _CGImageGetWidthNative, _CGImageGetWidthDart>(
  'CGImageGetWidth',
);

final _cgImageGetHeight = _cg.lookupFunction<
    _CGImageGetHeightNative, _CGImageGetHeightDart>(
  'CGImageGetHeight',
);

final _cgImageGetDataProvider = _cg.lookupFunction<
    _CGImageGetDataProviderNative, _CGImageGetDataProviderDart>(
  'CGImageGetDataProvider',
);

final _cgDataProviderCopyData = _cg.lookupFunction<
    _CGDataProviderCopyDataNative, _CGDataProviderCopyDataDart>(
  'CGDataProviderCopyData',
);

final _cgImageRelease = _cg.lookupFunction<
    _CGImageReleaseNative, _CGImageReleaseDart>(
  'CGImageRelease',
);

final _cgWindowListCopyWindowInfo = _cg.lookupFunction<
    _CGWindowListCopyWindowInfoNative, _CGWindowListCopyWindowInfoDart>(
  'CGWindowListCopyWindowInfo',
);

// ---------------------------------------------------------------------------
// CF helper – create a CFString from a Dart string. Caller must CFRelease.
// ---------------------------------------------------------------------------

Pointer<Void> _makeCFString(String s) {
  final cstr = s.toNativeUtf8();
  final cfStr = _cfStringCreateWithCString(
      Pointer.fromAddress(_kCFAllocatorDefault),
      cstr.cast<Char>(),
      _kCFStringEncodingUTF8);
  calloc.free(cstr);
  return cfStr;
}

// ---------------------------------------------------------------------------
// CF helper – extract int from a CFDictionary key (value must be CFNumber)
// ---------------------------------------------------------------------------

int? _dictGetInt(Pointer<Void> dict, Pointer<Void> cfKey) {
  final value = _cfDictionaryGetValue(dict, cfKey);
  if (value == nullptr) return null;
  final out = calloc<Int64>();
  final ok = _cfNumberGetValue(
      value, _kCFNumberSInt64Type, out.cast<Void>());
  final result = ok != 0 ? out.value : null;
  calloc.free(out);
  return result;
}

// ---------------------------------------------------------------------------
// CF helper – extract String from a CFDictionary key (value must be CFString)
// ---------------------------------------------------------------------------

String? _dictGetString(Pointer<Void> dict, Pointer<Void> cfKey) {
  final value = _cfDictionaryGetValue(dict, cfKey);
  if (value == nullptr) return null;
  return _cfStringToDart(value);
}

/// Convert a CFStringRef to a Dart String.
String? _cfStringToDart(Pointer<Void> cfString) {
  if (cfString == nullptr) return null;

  // Fast path: direct C-string pointer.
  final cPtr =
      _cfStringGetCStringPtr(cfString, _kCFStringEncodingUTF8);
  if (cPtr != nullptr) {
    return cPtr.cast<Utf8>().toDartString();
  }

  // Slow path: copy into buffer.
  final len = _cfStringGetLength(cfString);
  if (len <= 0) return null;
  // UTF-8 worst case: 4 bytes per char + NUL.
  final bufSize = len * 4 + 1;
  final buf = calloc<Uint8>(bufSize);
  final ok = _cfStringGetCString(
      cfString, buf.cast<Char>(), bufSize, _kCFStringEncodingUTF8);
  final result = ok != 0 ? buf.cast<Utf8>().toDartString() : null;
  calloc.free(buf);
  return result;
}

// ---------------------------------------------------------------------------
// CF helper – extract a bounds CFDictionary into Map<String,int>
// ---------------------------------------------------------------------------

Map<String, int>? _dictGetBounds(Pointer<Void> parent, Pointer<Void> cfKey) {
  final value = _cfDictionaryGetValue(parent, cfKey);
  if (value == nullptr) return null;

  // Create CFString keys for the bounds sub-dictionary.
  final kHeight = _makeCFString('Height');
  final kWidth = _makeCFString('Width');
  final kX = _makeCFString('X');
  final kY = _makeCFString('Y');

  final h = _dictGetInt(value, kHeight);
  final w = _dictGetInt(value, kWidth);
  final x = _dictGetInt(value, kX);
  final y = _dictGetInt(value, kY);

  _cfRelease(kHeight);
  _cfRelease(kWidth);
  _cfRelease(kX);
  _cfRelease(kY);

  if (h == null && w == null && x == null && y == null) return null;

  return {
    'Height': h ?? 0,
    'Width': w ?? 0,
    'X': x ?? 0,
    'Y': y ?? 0,
  };
}

// ---------------------------------------------------------------------------
// MacosScreenCapture
// ---------------------------------------------------------------------------

/// macOS screen capture using CoreGraphics FFI.
/// Note: Requires Screen Recording permission
/// (System Preferences > Privacy & Security > Screen Recording).
class MacosScreenCapture {
  /// Captures the primary screen. Returns null on failure.
  /// Result contains raw BGRA pixels and dimensions.
  static ScreenCaptureResult? captureScreen() {
    try {
      final displayID = _cgMainDisplayID();

      final image = _cgDisplayCreateImage(displayID);
      if (image == nullptr) {
        debugPrint('MacosScreenCapture: CGDisplayCreateImage failed');
        return null;
      }

      final result = _imageToResult(image);
      _cgImageRelease(image);
      return result;
    } catch (e) {
      debugPrint('MacosScreenCapture.captureScreen: failed: $e');
      return null;
    }
  }

  /// Captures a specific window by window ID.
  static ScreenCaptureResult? captureWindow(int windowID) {
    if (windowID == 0) return null;
    try {
      // CGRectNull = pass 0 as screenRect parameter
      final image = _cgWindowListCreateImage(
        _kCGNullWindow,
        _kCGWindowListOptionIncludingWindow,
        windowID,
        _kCGWindowImageBoundsIgnoreFraming,
      );

      if (image == nullptr) {
        debugPrint(
            'MacosScreenCapture: CGWindowListCreateImage failed for window $windowID');
        return null;
      }

      final result = _imageToResult(image);
      _cgImageRelease(image);
      return result;
    } catch (e) {
      debugPrint('MacosScreenCapture.captureWindow: failed: $e');
      return null;
    }
  }

  static ScreenCaptureResult? _imageToResult(Pointer<Void> image) {
    final width = _cgImageGetWidth(image);
    final height = _cgImageGetHeight(image);

    if (width <= 0 || height <= 0) return null;

    // Get pixel data via CGDataProvider
    final dataProvider = _cgImageGetDataProvider(image);
    if (dataProvider == nullptr) return null;

    final data = _cgDataProviderCopyData(dataProvider);
    if (data == nullptr) return null;

    // Get the actual data pointer and length
    final ptr = _cfDataGetBytePtr(data);
    final length = _cfDataGetLength(data);

    // Copy into Dart-managed Uint8List
    final pixels = Uint8List(length);
    for (var i = 0; i < length; i++) {
      pixels[i] = ptr[i];
    }

    _cfRelease(data);

    return ScreenCaptureResult(
      width: width,
      height: height,
      bgraPixels: pixels,
      dpiScale: 1.0,
    );
  }

  /// Get list of on-screen windows.
  static List<WindowInfo>? getWindowList() {
    try {
      final windowList = _cgWindowListCopyWindowInfo(
          _kCGWindowListOptionOnScreenOnly, _kCGNullWindow);
      if (windowList == nullptr) return null;

      final count = _cfArrayGetCount(windowList);
      final windows = <WindowInfo>[];

      // Pre-create CFString keys (reuse across iterations).
      final kNumber = _makeCFString('kCGWindowNumber');
      final kOwnerName = _makeCFString('kCGWindowOwnerName');
      final kName = _makeCFString('kCGWindowName');
      final kBounds = _makeCFString('kCGWindowBounds');

      for (var i = 0; i < count; i++) {
        final dict = _cfArrayGetValueAtIndex(windowList, i);
        if (dict == nullptr) continue;

        final windowID = _dictGetInt(dict, kNumber);
        final ownerName = _dictGetString(dict, kOwnerName);
        final windowName = _dictGetString(dict, kName);
        final bounds = _dictGetBounds(dict, kBounds);

        if (windowID != null && ownerName != null) {
          windows.add(WindowInfo(
            windowID: windowID,
            ownerName: ownerName,
            windowName: windowName,
            bounds: bounds,
          ));
        }
      }

      // Release CFString keys.
      _cfRelease(kNumber);
      _cfRelease(kOwnerName);
      _cfRelease(kName);
      _cfRelease(kBounds);

      _cfRelease(windowList);
      return windows;
    } catch (e) {
      debugPrint('MacosScreenCapture.getWindowList: failed: $e');
      return null;
    }
  }

  /// Returns the title of a window by window ID.
  /// Falls back to owner name if window name is unavailable.
  static String getWindowTitle(int windowID) {
    if (windowID == 0) return '';
    try {
      final windowList = _cgWindowListCopyWindowInfo(
          _kCGWindowListOptionIncludingWindow, windowID);
      if (windowList == nullptr) return '';

      String result = '';

      final kNumber = _makeCFString('kCGWindowNumber');
      final kName = _makeCFString('kCGWindowName');
      final kOwnerName = _makeCFString('kCGWindowOwnerName');

      final count = _cfArrayGetCount(windowList);
      for (var i = 0; i < count; i++) {
        final dict = _cfArrayGetValueAtIndex(windowList, i);
        final wID = _dictGetInt(dict, kNumber);
        if (wID == windowID) {
          final name = _dictGetString(dict, kName);
          final owner = _dictGetString(dict, kOwnerName);
          result = name ?? owner ?? '';
          break;
        }
      }

      _cfRelease(kNumber);
      _cfRelease(kName);
      _cfRelease(kOwnerName);
      _cfRelease(windowList);
      return result;
    } catch (e) {
      debugPrint('MacosScreenCapture.getWindowTitle: failed: $e');
      return '';
    }
  }

  /// Check if a window belongs to a known browser by owner name.
  static bool isBrowserWindow(int windowID) {
    if (windowID == 0) return false;
    try {
      final windowList = _cgWindowListCopyWindowInfo(
          _kCGWindowListOptionIncludingWindow, windowID);
      if (windowList == nullptr) return false;

      bool result = false;

      final kNumber = _makeCFString('kCGWindowNumber');
      final kOwnerName = _makeCFString('kCGWindowOwnerName');

      final count = _cfArrayGetCount(windowList);
      for (var i = 0; i < count; i++) {
        final dict = _cfArrayGetValueAtIndex(windowList, i);
        final wID = _dictGetInt(dict, kNumber);
        if (wID == windowID) {
          final owner = _dictGetString(dict, kOwnerName);
          if (owner != null) {
            final lower = owner.toLowerCase();
            result = lower.contains('chrome') ||
                lower.contains('safari') ||
                lower.contains('firefox') ||
                lower.contains('edge') ||
                lower.contains('opera') ||
                lower.contains('vivaldi') ||
                lower.contains('brave');
          }
          break;
        }
      }

      _cfRelease(kNumber);
      _cfRelease(kOwnerName);
      _cfRelease(windowList);
      return result;
    } catch (e) {
      debugPrint('MacosScreenCapture.isBrowserWindow: failed: $e');
      return false;
    }
  }

  /// Get browser URL using AppleScript, with regex fallback from window title.
  static String? getBrowserUrl(int windowID) {
    if (windowID == 0) return null;
    try {
      // Look up the window to find the owner (browser) name.
      final windows = getWindowList();
      if (windows == null) return _browserUrlFallback(windowID);

      final match = windows.where((w) => w.windowID == windowID).firstOrNull;
      if (match == null) return _browserUrlFallback(windowID);

      final ownerName = match.ownerName;
      final appName = _mapBrowserAppName(ownerName);
      if (appName == null) return _browserUrlFallback(windowID);

      // Build AppleScript to retrieve the active tab URL.
      String script;
      switch (appName) {
        case 'Safari':
          script = 'tell application "Safari" to get URL of current tab of front window';
          break;
        case 'Firefox':
          // Firefox does not expose URL via AppleScript reliably.
          return _browserUrlFallback(windowID);
        default:
          // Chrome, Edge, Brave, Arc all use "active tab".
          script = 'tell application "$appName" to get URL of active tab of front window';
          break;
      }

      final result = Process.runSync('osascript', ['-e', script]);
      final url = result.stdout?.toString().trim();
      if (result.exitCode == 0 && url != null && url.isNotEmpty && url != 'missing value') {
        return url;
      }

      // Fall back to regex from window title.
      return _browserUrlFallback(windowID);
    } catch (e) {
      debugPrint('MacosScreenCapture.getBrowserUrl: failed: $e');
      return _browserUrlFallback(windowID);
    }
  }

  /// Map a window owner name to the AppleScript application name.
  /// Returns null if the owner is not a recognised browser.
  static String? _mapBrowserAppName(String ownerName) {
    final lower = ownerName.toLowerCase();
    if (lower.contains('safari')) return 'Safari';
    if (lower.contains('chrome') && !lower.contains('chromium')) return 'Google Chrome';
    if (lower.contains('firefox')) return 'Firefox';
    if (lower.contains('edge')) return 'Microsoft Edge';
    if (lower.contains('brave')) return 'Brave';
    if (lower.contains('arc')) return 'Arc';
    return null;
  }

  /// Fall back to extracting a URL from the window title via regex.
  static String? _browserUrlFallback(int windowID) {
    final title = getWindowTitle(windowID);
    if (title.isEmpty) return null;
    final urlMatch = RegExp(r'https?://\S+').firstMatch(title);
    return urlMatch?.group(0);
  }

  /// Extract visible page text from a browser tab via AppleScript JavaScript.
  /// Returns null if extraction fails or the window is not a browser.
  static String? getBrowserPageText(int windowID) {
    if (windowID == 0) return null;
    try {
      final windows = getWindowList();
      if (windows == null) return null;
      final match = windows.where((w) => w.windowID == windowID).firstOrNull;
      if (match == null) return null;
      final appName = _mapBrowserAppName(match.ownerName);
      if (appName == null) return null;

      String script;
      if (appName == 'Safari') {
        script = 'tell application "Safari" to do JavaScript '
            '"document.body.innerText" in current tab of front window';
      } else if (appName == 'Firefox') {
        return null; // Firefox doesn't support JS via AppleScript
      } else {
        // Chrome, Edge, Brave, Arc
        script = 'tell application "$appName" to execute front window\'s '
            'active tab javascript "document.body.innerText"';
      }

      final result = Process.runSync('osascript', ['-e', script],
          runInShell: true);
      if (result.exitCode != 0) return null;
      final text = result.stdout?.toString().trim() ?? '';
      return text.isNotEmpty ? text : null;
    } catch (e) {
      debugPrint('MacosScreenCapture.getBrowserPageText: $e');
      return null;
    }
  }

  /// Returns the DPI scale factor.
  /// On macOS Retina, Flutter already handles scaling, so this returns 2.0
  /// to reflect that CGImage pixels are in physical (Retina) resolution
  /// while logical coordinates are halved.
  static double getDpiScaleForWindow(int windowID) {
    try {
      final displayID = _cgMainDisplayID();
      final wide = _cgDisplayPixelsWide(displayID);
      if (wide <= 0) return 2.0;
      // Compare physical pixels to a common logical width (1440 for 16-inch).
      // A more robust approach would query NSScreen, but this suffices for now.
      return wide > 2000 ? 2.0 : 1.0;
    } catch (_) {
      return 2.0;
    }
  }

  /// Returns the main display size in physical pixels as [width, height].
  /// Returns null on failure.
  static List<int>? getScreenSize() {
    try {
      final displayID = _cgMainDisplayID();
      final w = _cgDisplayPixelsWide(displayID);
      final h = _cgDisplayPixelsHigh(displayID);
      if (w <= 0 || h <= 0) return null;
      return [w, h];
    } catch (_) {
      return null;
    }
  }

  /// Returns the main display size in logical points as [width, height].
  /// CGWindowListCopyWindowInfo bounds are in points, so use this for comparison.
  static List<double>? getScreenSizePoints() {
    try {
      final displayID = _cgMainDisplayID();
      final physW = _cgDisplayPixelsWide(displayID);
      final physH = _cgDisplayPixelsHigh(displayID);
      if (physW <= 0 || physH <= 0) return null;
      final scale = getDpiScaleForWindow(0);
      return [physW / scale, physH / scale];
    } catch (_) {
      return null;
    }
  }

  /// Resize and reposition a window using AppleScript via System Events.
  /// Requires Accessibility permission (System Preferences > Privacy & Security > Accessibility).
  static bool resizeWindow(int windowID, int x, int y, int w, int h) {
    if (windowID == 0) return false;
    try {
      // Find the window owner name so we can target the correct process.
      final windows = getWindowList();
      if (windows == null) return false;

      final match = windows.where((w) => w.windowID == windowID).firstOrNull;
      if (match == null) return false;

      final ownerName = match.ownerName;

      final script = '''
tell application "System Events"
  tell process "$ownerName"
    set position of front window to {$x, $y}
    set size of front window to {$w, $h}
  end tell
end tell
''';

      final result = Process.runSync('osascript', ['-e', script]);
      if (result.exitCode != 0) {
        debugPrint('MacosScreenCapture.resizeWindow: osascript failed: ${result.stderr}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('MacosScreenCapture.resizeWindow: $e');
      return false;
    }
  }

  /// Returns the work area (excluding menu bar and dock) as [x, y, w, h].
  /// Uses CGDisplay APIs for screen size and reads dock configuration via defaults.
  static List<int>? getMonitorWorkArea(int windowID) {
    try {
      final displayID = _cgMainDisplayID();
      final screenHeight = _cgDisplayPixelsHigh(displayID);
      final screenWidth = _cgDisplayPixelsWide(displayID);

      // Menu bar height.
      int menuBarHeight = _readIntDefault('-g', 'AppleMenuBarHeight') ?? 25;

      // Dock configuration.
      final dockOrientation = _readStringDefault('com.apple.dock', 'orientation') ?? 'bottom';
      final dockTileSize = _readIntDefault('com.apple.dock', 'tilesize') ?? 64;
      final dockAutohide = _readBoolDefault('com.apple.dock', 'autohide') ?? false;

      // If dock is hidden, it doesn't consume space (a thin stripe still appears
      // on hover, but the work area is considered full).
      final dockThickness = dockAutohide ? 0 : dockTileSize;

      int top = menuBarHeight;
      int height = screenHeight - menuBarHeight;
      int workX = 0;
      int workWidth = screenWidth;

      switch (dockOrientation) {
        case 'bottom':
          height -= dockThickness;
          break;
        case 'left':
          workX = dockThickness;
          workWidth -= dockThickness;
          break;
        case 'right':
          workWidth -= dockThickness;
          break;
      }

      return [workX, top, workWidth, height];
    } catch (e) {
      debugPrint('MacosScreenCapture.getMonitorWorkArea: $e');
      return null;
    }
  }

  /// Read an integer default value via `defaults read`.
  static int? _readIntDefault(String domain, String key) {
    try {
      final result = Process.runSync('defaults', ['read', domain, key]);
      if (result.exitCode == 0) {
        return int.tryParse(result.stdout.toString().trim());
      }
    } catch (_) {}
    return null;
  }

  /// Read a string default value via `defaults read`.
  static String? _readStringDefault(String domain, String key) {
    try {
      final result = Process.runSync('defaults', ['read', domain, key]);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}
    return null;
  }

  /// Read a boolean default value via `defaults read`.
  static bool? _readBoolDefault(String domain, String key) {
    try {
      final result = Process.runSync('defaults', ['read', domain, key]);
      if (result.exitCode == 0) {
        final val = result.stdout.toString().trim().toLowerCase();
        return val == '1' || val == 'true' || val == 'yes';
      }
    } catch (_) {}
    return null;
  }
}
