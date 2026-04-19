import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';

import '../gui_agent.dart';
import '../win32_screen_capture.dart';

/// Windows [WindowAgent] implementation using Win32 FFI.
///
/// Delegates to [Win32ScreenCapture] for methods already implemented there,
/// and adds new Win32 calls for foreground tracking and window classification.
class Win32WindowAgent implements WindowAgent {
  static final _user32 = DynamicLibrary.open('user32.dll');

  @override
  int getForegroundWindow() {
    try {
      final fn = _user32.lookupFunction<IntPtr Function(), int Function()>(
          'GetForegroundWindow');
      return fn();
    } catch (_) {
      return 0;
    }
  }

  @override
  String getWindowTitle(int handle) =>
      Win32ScreenCapture.getWindowTitle(handle);

  @override
  String getWindowClassName(int handle) {
    if (handle == 0) return '';
    try {
      final getClassName = _user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)>('GetClassNameW');
      final buf = calloc<Uint16>(256);
      final len = getClassName(handle, buf.cast<Utf16>(), 256);
      final name = len > 0 ? buf.cast<Utf16>().toDartString() : '';
      calloc.free(buf);
      return name;
    } catch (_) {
      return '';
    }
  }

  @override
  Rect getWindowRect(int handle) {
    if (handle == 0) return Rect.zero;
    try {
      final getWinRect = _user32.lookupFunction<
          Int32 Function(IntPtr, Pointer),
          int Function(int, Pointer)>('GetWindowRect');
      final buf = calloc<Int32>(4);
      getWinRect(handle, buf);
      final rect = Rect.fromLTRB(
        buf[0].toDouble(),
        buf[1].toDouble(),
        buf[2].toDouble(),
        buf[3].toDouble(),
      );
      calloc.free(buf);
      return rect;
    } catch (_) {
      return Rect.zero;
    }
  }

  @override
  bool isBrowserWindow(int handle) =>
      Win32ScreenCapture.isBrowserWindow(handle);

  @override
  bool isNormalAppWindow(int handle) {
    if (handle == 0) return false;
    try {
      final getWindowLong = _user32.lookupFunction<
          Int32 Function(IntPtr, Int32),
          int Function(int, int)>('GetWindowLongW');
      const gwlStyle = -16;
      const gwlExStyle = -20;
      const wsVisible = 0x10000000;
      const wsExToolWindow = 0x00000080;
      const wsExNoActivate = 0x08000000;
      final style = getWindowLong(handle, gwlStyle);
      final exStyle = getWindowLong(handle, gwlExStyle);
      if (style & wsVisible == 0) return false;
      if (exStyle & wsExToolWindow != 0) return false;
      if (exStyle & wsExNoActivate != 0) return false;

      final className = getWindowClassName(handle);
      const systemClasses = [
        'Shell_TrayWnd', 'Shell_SecondaryTrayWnd', 'Progman',
        'WorkerW', 'Windows.UI.Core.CoreWindow',
        'Windows.UI.Input.InputSite.WindowClass',
      ];
      if (systemClasses.contains(className)) return false;

      final rect = getWindowRect(handle);
      if (rect.width < 50 || rect.height < 50) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  List<int>? getMonitorWorkArea(int handle) =>
      Win32ScreenCapture.getMonitorWorkArea(handle);

  @override
  bool resizeWindow(int handle, int x, int y, int w, int h) =>
      Win32ScreenCapture.resizeWindow(handle, x, y, w, h);
}
