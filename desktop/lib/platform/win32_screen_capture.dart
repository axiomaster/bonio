import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'screen_capture_types.dart';

typedef _GetWindowRectNative = Int32 Function(IntPtr hwnd, Pointer rect);
typedef _GetWindowRectDart = int Function(int hwnd, Pointer rect);

typedef _PrintWindowNative = Int32 Function(IntPtr hwnd, IntPtr hdc, Uint32 flags);
typedef _PrintWindowDart = int Function(int hwnd, int hdc, int flags);

typedef _GetWindowTextWNative = Int32 Function(IntPtr hwnd, Pointer<Utf16> buf, Int32 max);
typedef _GetWindowTextWDart = int Function(int hwnd, Pointer<Utf16> buf, int max);

typedef _GetDpiForWindowNative = Uint32 Function(IntPtr hwnd);
typedef _GetDpiForWindowDart = int Function(int hwnd);

typedef _SetWindowPosNative = Int32 Function(
    IntPtr hwnd, IntPtr insertAfter, Int32 x, Int32 y, Int32 cx, Int32 cy, Uint32 flags);
typedef _SetWindowPosDart = int Function(
    int hwnd, int insertAfter, int x, int y, int cx, int cy, int flags);

typedef _MonitorFromWindowNative = IntPtr Function(IntPtr hwnd, Uint32 flags);
typedef _MonitorFromWindowDart = int Function(int hwnd, int flags);

typedef _GetMonitorInfoNative = Int32 Function(IntPtr hMonitor, Pointer info);
typedef _GetMonitorInfoDart = int Function(int hMonitor, Pointer info);

/// Win32 FFI screen/window capture using BitBlt / PrintWindow.
class Win32ScreenCapture {
  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _gdi32 = DynamicLibrary.open('gdi32.dll');

  static int _getSystemMetrics(int nIndex) {
    final fn = _user32.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'GetSystemMetrics');
    return fn(nIndex);
  }

  static int _getDpiForSystem() {
    try {
      final fn = _user32
          .lookupFunction<Uint32 Function(), int Function()>('GetDpiForSystem');
      return fn();
    } catch (_) {
      return 96;
    }
  }

  /// Captures the primary screen. Returns null on failure.
  /// Result contains raw BGRA pixels and dimensions in physical pixels.
  static ScreenCaptureResult? captureScreen() {
    try {
      final scale = _getDpiForSystem() / 96.0;
      final screenW = _getSystemMetrics(0); // SM_CXSCREEN
      final screenH = _getSystemMetrics(1); // SM_CYSCREEN
      final physW = screenW;
      final physH = screenH;

      final getDC = _user32
          .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
      final releaseDC = _user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr), int Function(int, int)>('ReleaseDC');
      final createCompatibleDC = _gdi32.lookupFunction<
          IntPtr Function(IntPtr), int Function(int)>('CreateCompatibleDC');
      final createCompatibleBitmap = _gdi32.lookupFunction<
          IntPtr Function(IntPtr, Int32, Int32),
          int Function(int, int, int)>('CreateCompatibleBitmap');
      final selectObject = _gdi32.lookupFunction<
          IntPtr Function(IntPtr, IntPtr),
          int Function(int, int)>('SelectObject');
      final bitBlt = _gdi32.lookupFunction<
          Int32 Function(IntPtr, Int32, Int32, Int32, Int32, IntPtr, Int32,
              Int32, Uint32),
          int Function(int, int, int, int, int, int, int, int,
              int)>('BitBlt');
      final getDIBits = _gdi32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Uint32, Uint32, Pointer<Void>,
              Pointer<_BITMAPINFO>, Uint32),
          int Function(int, int, int, int, Pointer<Void>, Pointer<_BITMAPINFO>,
              int)>('GetDIBits');
      final deleteObject = _gdi32.lookupFunction<
          Int32 Function(IntPtr), int Function(int)>('DeleteObject');
      final deleteDC = _gdi32.lookupFunction<
          Int32 Function(IntPtr), int Function(int)>('DeleteDC');

      final screenDC = getDC(0);
      if (screenDC == 0) return null;

      final memDC = createCompatibleDC(screenDC);
      final bitmap = createCompatibleBitmap(screenDC, physW, physH);
      selectObject(memDC, bitmap);

      // SRCCOPY = 0x00CC0020
      bitBlt(memDC, 0, 0, physW, physH, screenDC, 0, 0, 0x00CC0020);

      final bmi = calloc<_BITMAPINFO>();
      bmi.ref.bmiHeader.biSize = sizeOf<_BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = physW;
      bmi.ref.bmiHeader.biHeight = -physH; // top-down
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = 0; // BI_RGB

      final bufferSize = physW * physH * 4;
      final pixelBuffer = calloc<Uint8>(bufferSize);

      getDIBits(memDC, bitmap, 0, physH, pixelBuffer.cast<Void>(), bmi, 0);

      final pixels = Uint8List.fromList(
          pixelBuffer.asTypedList(bufferSize));

      calloc.free(pixelBuffer);
      calloc.free(bmi);
      deleteObject(bitmap);
      deleteDC(memDC);
      releaseDC(0, screenDC);

      return ScreenCaptureResult(
        width: physW,
        height: physH,
        bgraPixels: pixels,
        dpiScale: scale,
      );
    } catch (e) {
      debugPrint('Win32ScreenCapture: failed: $e');
      return null;
    }
  }

  /// Captures a specific window by HWND using PrintWindow.
  /// Returns null on failure.
  static ScreenCaptureResult? captureWindow(int hwnd) {
    if (hwnd == 0) return null;
    try {
      final getWindowRect = _user32
          .lookupFunction<_GetWindowRectNative, _GetWindowRectDart>('GetWindowRect');
      final printWindow = _user32
          .lookupFunction<_PrintWindowNative, _PrintWindowDart>('PrintWindow');

      double dpiScale = 1.0;
      try {
        final getDpiForWindow = _user32
            .lookupFunction<_GetDpiForWindowNative, _GetDpiForWindowDart>('GetDpiForWindow');
        dpiScale = getDpiForWindow(hwnd) / 96.0;
      } catch (_) {}

      final rectBuf = calloc<Int32>(4);
      getWindowRect(hwnd, rectBuf);
      final left = rectBuf[0];
      final top = rectBuf[1];
      final right = rectBuf[2];
      final bottom = rectBuf[3];
      calloc.free(rectBuf);

      final physW = right - left;
      final physH = bottom - top;
      if (physW <= 0 || physH <= 0) return null;

      final getDC = _user32
          .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
      final releaseDC = _user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr), int Function(int, int)>('ReleaseDC');
      final createCompatibleDC = _gdi32.lookupFunction<
          IntPtr Function(IntPtr), int Function(int)>('CreateCompatibleDC');
      final createCompatibleBitmap = _gdi32.lookupFunction<
          IntPtr Function(IntPtr, Int32, Int32),
          int Function(int, int, int)>('CreateCompatibleBitmap');
      final selectObject = _gdi32.lookupFunction<
          IntPtr Function(IntPtr, IntPtr),
          int Function(int, int)>('SelectObject');
      final getDIBits = _gdi32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Uint32, Uint32, Pointer<Void>,
              Pointer<_BITMAPINFO>, Uint32),
          int Function(int, int, int, int, Pointer<Void>, Pointer<_BITMAPINFO>,
              int)>('GetDIBits');
      final deleteObject = _gdi32.lookupFunction<
          Int32 Function(IntPtr), int Function(int)>('DeleteObject');
      final deleteDC = _gdi32.lookupFunction<
          Int32 Function(IntPtr), int Function(int)>('DeleteDC');

      final windowDC = getDC(hwnd);
      if (windowDC == 0) return null;

      final memDC = createCompatibleDC(windowDC);
      final bitmap = createCompatibleBitmap(windowDC, physW, physH);
      selectObject(memDC, bitmap);

      // PW_RENDERFULLCONTENT = 2
      final ok = printWindow(hwnd, memDC, 2);
      if (ok == 0) {
        // Fallback to BitBlt
        final bitBlt = _gdi32.lookupFunction<
            Int32 Function(IntPtr, Int32, Int32, Int32, Int32, IntPtr, Int32,
                Int32, Uint32),
            int Function(int, int, int, int, int, int, int, int,
                int)>('BitBlt');
        bitBlt(memDC, 0, 0, physW, physH, windowDC, 0, 0, 0x00CC0020);
      }

      final bmi = calloc<_BITMAPINFO>();
      bmi.ref.bmiHeader.biSize = sizeOf<_BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = physW;
      bmi.ref.bmiHeader.biHeight = -physH; // top-down
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = 0;

      final bufferSize = physW * physH * 4;
      final pixelBuffer = calloc<Uint8>(bufferSize);

      getDIBits(memDC, bitmap, 0, physH, pixelBuffer.cast<Void>(), bmi, 0);

      final pixels = Uint8List.fromList(pixelBuffer.asTypedList(bufferSize));

      calloc.free(pixelBuffer);
      calloc.free(bmi);
      deleteObject(bitmap);
      deleteDC(memDC);
      releaseDC(hwnd, windowDC);

      return ScreenCaptureResult(
        width: physW,
        height: physH,
        bgraPixels: pixels,
        dpiScale: dpiScale,
      );
    } catch (e) {
      debugPrint('Win32ScreenCapture.captureWindow: failed: $e');
      return null;
    }
  }

  /// Returns the title of a window by HWND.
  static String getWindowTitle(int hwnd) {
    if (hwnd == 0) return '';
    try {
      final getWindowTextW = _user32
          .lookupFunction<_GetWindowTextWNative, _GetWindowTextWDart>('GetWindowTextW');
      final buf = calloc<Uint16>(512);
      final len = getWindowTextW(hwnd, buf.cast<Utf16>(), 512);
      final title = len > 0 ? buf.cast<Utf16>().toDartString() : '';
      calloc.free(buf);
      return title;
    } catch (e) {
      debugPrint('Win32ScreenCapture.getWindowTitle: failed: $e');
      return '';
    }
  }

  /// Attempts to extract a URL from a browser window's address bar.
  /// Works with Chrome, Edge, Firefox by detecting their window class names
  /// and using UI Automation to read the address bar value.
  /// Returns null if not a browser or URL cannot be extracted.
  /// Check if a window belongs to a known browser by class name.
  static bool isBrowserWindow(int hwnd) {
    if (hwnd == 0) return false;
    try {
      final getClassName = _user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)>('GetClassNameW');
      final classBuf = calloc<Uint16>(256);
      final classLen = getClassName(hwnd, classBuf.cast<Utf16>(), 256);
      final className =
          classLen > 0 ? classBuf.cast<Utf16>().toDartString() : '';
      calloc.free(classBuf);
      return className == 'Chrome_WidgetWin_1' ||
          className == 'MozillaWindowClass' ||
          className.contains('Opera') ||
          className.contains('Vivaldi');
    } catch (_) {
      return false;
    }
  }

  static String? getBrowserUrl(int hwnd) {
    if (hwnd == 0) return null;
    try {
      if (!isBrowserWindow(hwnd)) return null;

      final title = getWindowTitle(hwnd);
      if (title.isEmpty) return null;

      // Some browsers include the URL directly in the title
      final urlMatch = RegExp(r'https?://\S+').firstMatch(title);
      if (urlMatch != null) return urlMatch.group(0);

      return null;
    } catch (e) {
      debugPrint('Win32ScreenCapture.getBrowserUrl: failed: $e');
      return null;
    }
  }

  /// Extract the browser URL by simulating Ctrl+L (select address bar),
  /// Ctrl+C (copy), then reading the clipboard. Works for Chrome, Edge,
  /// Firefox, Opera, Vivaldi.
  static Future<String?> getBrowserUrlViaKeyboard(int hwnd) async {
    if (hwnd == 0) return null;
    if (!Platform.isWindows) return null;
    try {
      final setFg = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'SetForegroundWindow');
      final keybdEvent = _user32.lookupFunction<
          Void Function(Uint8, Uint8, Uint32, IntPtr),
          void Function(int, int, int, int)>('keybd_event');
      final openClipboard =
          _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('OpenClipboard');
      final closeClipboard =
          _user32.lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
      final getClipboardData =
          _user32.lookupFunction<IntPtr Function(Uint32), int Function(int)>('GetClipboardData');
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final globalLock =
          kernel32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalLock');
      final globalUnlock =
          kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('GlobalUnlock');

      const vkControl = 0x11;
      const vkL = 0x4C;
      const vkC = 0x43;
      const vkEscape = 0x1B;
      const keyeventfKeyup = 0x0002;
      const cfUnicodeText = 13;

      // Activate the browser window
      setFg(hwnd);
      await Future.delayed(const Duration(milliseconds: 100));

      // Ctrl+L — select address bar
      keybdEvent(vkControl, 0, 0, 0);
      keybdEvent(vkL, 0, 0, 0);
      keybdEvent(vkL, 0, keyeventfKeyup, 0);
      keybdEvent(vkControl, 0, keyeventfKeyup, 0);
      await Future.delayed(const Duration(milliseconds: 80));

      // Ctrl+C — copy URL
      keybdEvent(vkControl, 0, 0, 0);
      keybdEvent(vkC, 0, 0, 0);
      keybdEvent(vkC, 0, keyeventfKeyup, 0);
      keybdEvent(vkControl, 0, keyeventfKeyup, 0);
      await Future.delayed(const Duration(milliseconds: 80));

      // Escape — deselect address bar
      keybdEvent(vkEscape, 0, 0, 0);
      keybdEvent(vkEscape, 0, keyeventfKeyup, 0);

      // Read clipboard via Win32 API
      if (openClipboard(0) == 0) return null;
      try {
        final hData = getClipboardData(cfUnicodeText);
        if (hData == 0) return null;
        final ptr = globalLock(hData);
        if (ptr == 0) return null;
        try {
          final text = Pointer<Utf16>.fromAddress(ptr).toDartString().trim();
          if (text.startsWith('http://') || text.startsWith('https://')) {
            return text;
          }
          return null;
        } finally {
          globalUnlock(hData);
        }
      } finally {
        closeClipboard();
      }
    } catch (e) {
      debugPrint('Win32ScreenCapture.getBrowserUrlViaKeyboard: $e');
      return null;
    }
  }

  /// Returns the DPI scale factor for the monitor containing [hwnd].
  /// Falls back to system DPI or 1.0 on failure.
  static double getDpiScaleForWindow(int hwnd) {
    if (hwnd == 0) return 1.0;
    try {
      final getDpiForWindow = _user32
          .lookupFunction<_GetDpiForWindowNative, _GetDpiForWindowDart>(
              'GetDpiForWindow');
      return getDpiForWindow(hwnd) / 96.0;
    } catch (_) {
      try {
        return _getDpiForSystem() / 96.0;
      } catch (_) {
        return 1.0;
      }
    }
  }

  /// Resize and reposition a window using Win32 SetWindowPos.
  static bool resizeWindow(int hwnd, int x, int y, int w, int h) {
    if (hwnd == 0) return false;
    try {
      final setWindowPos = _user32.lookupFunction<
          _SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');
      const swpNoZOrder = 0x0004;
      const swpNoActivate = 0x0010;
      return setWindowPos(hwnd, 0, x, y, w, h, swpNoZOrder | swpNoActivate) != 0;
    } catch (e) {
      debugPrint('Win32ScreenCapture.resizeWindow: $e');
      return false;
    }
  }

  /// Returns the work area (excluding taskbar) of the monitor containing [hwnd]
  /// as [left, top, width, height] in physical pixels.
  static List<int>? getMonitorWorkArea(int hwnd) {
    if (hwnd == 0) return null;
    try {
      final monitorFromWindow = _user32.lookupFunction<
          _MonitorFromWindowNative, _MonitorFromWindowDart>('MonitorFromWindow');
      const monitorDefaultToNearest = 2;
      final hMonitor = monitorFromWindow(hwnd, monitorDefaultToNearest);
      if (hMonitor == 0) return null;

      // MONITORINFO: cbSize(4) + rcMonitor(16) + rcWork(16) + dwFlags(4) = 40 bytes
      final info = calloc<Uint8>(40);
      info.cast<Uint32>().value = 40; // cbSize
      final getMonitorInfo = _user32.lookupFunction<
          _GetMonitorInfoNative, _GetMonitorInfoDart>('GetMonitorInfoW');
      final ok = getMonitorInfo(hMonitor, info.cast());
      if (ok == 0) {
        calloc.free(info);
        return null;
      }
      // rcWork starts at offset 20 (after cbSize=4 + rcMonitor=16)
      final rcWork = info.cast<Int32>().elementAt(5); // offset 20 / 4
      final left = rcWork[0];
      final top = rcWork[1];
      final right = rcWork[2];
      final bottom = rcWork[3];
      calloc.free(info);
      return [left, top, right - left, bottom - top];
    } catch (e) {
      debugPrint('Win32ScreenCapture.getMonitorWorkArea: $e');
      return null;
    }
  }
}

// Win32 structs for BITMAPINFO
base class _BITMAPINFOHEADER extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

base class _BITMAPINFO extends Struct {
  external _BITMAPINFOHEADER bmiHeader;
  // bmiColors follows; we don't need it for BI_RGB
}
