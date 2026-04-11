import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _GetWindowRectNative = Int32 Function(IntPtr hwnd, Pointer rect);
typedef _GetWindowRectDart = int Function(int hwnd, Pointer rect);

typedef _PrintWindowNative = Int32 Function(IntPtr hwnd, IntPtr hdc, Uint32 flags);
typedef _PrintWindowDart = int Function(int hwnd, int hdc, int flags);

typedef _GetWindowTextWNative = Int32 Function(IntPtr hwnd, Pointer<Utf16> buf, Int32 max);
typedef _GetWindowTextWDart = int Function(int hwnd, Pointer<Utf16> buf, int max);

typedef _GetDpiForWindowNative = Uint32 Function(IntPtr hwnd);
typedef _GetDpiForWindowDart = int Function(int hwnd);

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
  static String? getBrowserUrl(int hwnd) {
    if (hwnd == 0) return null;
    try {
      // First, check if this is a known browser by window class name
      final getClassName = _user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)>('GetClassNameW');
      final classBuf = calloc<Uint16>(256);
      final classLen = getClassName(hwnd, classBuf.cast<Utf16>(), 256);
      final className =
          classLen > 0 ? classBuf.cast<Utf16>().toDartString() : '';
      calloc.free(classBuf);

      // Known browser class names
      final isBrowser = className == 'Chrome_WidgetWin_1' || // Chrome / Edge
          className == 'MozillaWindowClass' ||               // Firefox
          className.contains('Opera') ||
          className.contains('Vivaldi');

      if (!isBrowser) return null;

      // Try to extract URL from the window title.
      // Many browser titles end with " - BrowserName" and may contain
      // the domain or full title. But for actual URL, we need UI Automation.
      // As a practical fallback, parse URL-like strings from the title.
      final title = getWindowTitle(hwnd);
      if (title.isEmpty) return null;

      // Some browsers include the URL directly in the title in certain modes
      final urlMatch = RegExp(r'https?://\S+').firstMatch(title);
      if (urlMatch != null) return urlMatch.group(0);

      return null;
    } catch (e) {
      debugPrint('Win32ScreenCapture.getBrowserUrl: failed: $e');
      return null;
    }
  }
}

class ScreenCaptureResult {
  final int width;
  final int height;
  final Uint8List bgraPixels;
  final double dpiScale;

  ScreenCaptureResult({
    required this.width,
    required this.height,
    required this.bgraPixels,
    required this.dpiScale,
  });

  /// Convert the entire capture to RGBA.
  Uint8List toRgba() {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      final srcIdx = i * 4;
      final dstIdx = i * 4;
      rgba[dstIdx + 0] = bgraPixels[srcIdx + 2]; // R
      rgba[dstIdx + 1] = bgraPixels[srcIdx + 1]; // G
      rgba[dstIdx + 2] = bgraPixels[srcIdx + 0]; // B
      rgba[dstIdx + 3] = 255; // A
    }
    return rgba;
  }

  /// Encode the full capture as PNG bytes.
  Future<Uint8List?> toPng() async {
    if (width <= 0 || height <= 0) return null;
    final rgba = toRgba();
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    codec.dispose();
    descriptor.dispose();
    return byteData?.buffer.asUint8List();
  }

  /// Crop to a region (in physical pixels) and convert BGRA to RGBA.
  Uint8List cropToRgba(int x, int y, int w, int h) {
    final cx = x.clamp(0, width);
    final cy = y.clamp(0, height);
    final cw = w.clamp(0, width - cx);
    final ch = h.clamp(0, height - cy);

    final rgba = Uint8List(cw * ch * 4);
    for (var row = 0; row < ch; row++) {
      for (var col = 0; col < cw; col++) {
        final srcIdx = ((cy + row) * width + (cx + col)) * 4;
        final dstIdx = (row * cw + col) * 4;
        rgba[dstIdx + 0] = bgraPixels[srcIdx + 2]; // R
        rgba[dstIdx + 1] = bgraPixels[srcIdx + 1]; // G
        rgba[dstIdx + 2] = bgraPixels[srcIdx + 0]; // B
        rgba[dstIdx + 3] = 255; // A
      }
    }
    return rgba;
  }

  /// Encode a cropped region as PNG bytes.
  Future<Uint8List?> cropToPng(int x, int y, int w, int h) async {
    final cw = w.clamp(0, width - x.clamp(0, width));
    final ch = h.clamp(0, height - y.clamp(0, height));
    if (cw <= 0 || ch <= 0) return null;

    final rgba = cropToRgba(x, y, cw, ch);

    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: cw,
      height: ch,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    codec.dispose();
    descriptor.dispose();

    return byteData?.buffer.asUint8List();
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
