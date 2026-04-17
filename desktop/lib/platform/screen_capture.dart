import 'dart:io';

import 'macos_screen_capture.dart' as mac;
import 'screen_capture_types.dart';
import 'win32_screen_capture.dart' as win;

export 'screen_capture_types.dart';

/// Platform-agnostic screen capture API.
/// Delegates to the correct platform implementation at runtime.
class ScreenCapture {
  static ScreenCaptureResult? captureScreen() {
    if (Platform.isWindows) return win.Win32ScreenCapture.captureScreen();
    if (Platform.isMacOS) return mac.MacosScreenCapture.captureScreen();
    return null;
  }

  static ScreenCaptureResult? captureWindow(int windowId) {
    if (Platform.isWindows) return win.Win32ScreenCapture.captureWindow(windowId);
    if (Platform.isMacOS) return mac.MacosScreenCapture.captureWindow(windowId);
    return null;
  }

  static String getWindowTitle(int windowId) {
    if (Platform.isWindows) return win.Win32ScreenCapture.getWindowTitle(windowId);
    if (Platform.isMacOS) return mac.MacosScreenCapture.getWindowTitle(windowId);
    return '';
  }

  static bool isBrowserWindow(int windowId) {
    if (Platform.isWindows) return win.Win32ScreenCapture.isBrowserWindow(windowId);
    if (Platform.isMacOS) return mac.MacosScreenCapture.isBrowserWindow(windowId);
    return false;
  }

  static String? getBrowserUrl(int windowId) {
    if (Platform.isWindows) return win.Win32ScreenCapture.getBrowserUrl(windowId);
    if (Platform.isMacOS) return mac.MacosScreenCapture.getBrowserUrl(windowId);
    return null;
  }

  static double getDpiScaleForWindow(int windowId) {
    if (Platform.isWindows) return win.Win32ScreenCapture.getDpiScaleForWindow(windowId);
    if (Platform.isMacOS) return mac.MacosScreenCapture.getDpiScaleForWindow(windowId);
    return 1.0;
  }

  static bool resizeWindow(int windowId, int x, int y, int w, int h) {
    if (Platform.isWindows) return win.Win32ScreenCapture.resizeWindow(windowId, x, y, w, h);
    if (Platform.isMacOS) return mac.MacosScreenCapture.resizeWindow(windowId, x, y, w, h);
    return false;
  }

  static List<int>? getMonitorWorkArea(int windowId) {
    if (Platform.isWindows) return win.Win32ScreenCapture.getMonitorWorkArea(windowId);
    if (Platform.isMacOS) return mac.MacosScreenCapture.getMonitorWorkArea(windowId);
    return null;
  }

  static List<WindowInfo>? getWindowList() {
    if (Platform.isMacOS) return mac.MacosScreenCapture.getWindowList();
    return null;
  }
}
