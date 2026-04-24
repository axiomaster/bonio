import 'dart:ui';

import '../gui_agent.dart';
import '../screen_capture.dart';

class MacWindowAgent implements WindowAgent {
  @override
  int getForegroundWindow() => 0;

  @override
  String getWindowTitle(int handle) =>
      ScreenCapture.getWindowTitle(handle);

  @override
  String getWindowClassName(int handle) => '';

  @override
  Rect getWindowRect(int handle) {
    final windows = ScreenCapture.getWindowList();
    if (windows == null) return Rect.zero;
    final match =
        windows.where((w) => w.windowID == handle).firstOrNull;
    if (match == null || match.bounds == null) return Rect.zero;
    final b = match.bounds!;
    return Rect.fromLTWH(
      (b['X'] ?? 0).toDouble(),
      (b['Y'] ?? 0).toDouble(),
      (b['Width'] ?? 0).toDouble(),
      (b['Height'] ?? 0).toDouble(),
    );
  }

  @override
  bool isBrowserWindow(int handle) =>
      ScreenCapture.isBrowserWindow(handle);

  @override
  bool isNormalAppWindow(int handle) => true;

  @override
  List<int>? getMonitorWorkArea(int handle) =>
      ScreenCapture.getMonitorWorkArea(handle);

  @override
  bool resizeWindow(int handle, int x, int y, int w, int h) =>
      ScreenCapture.resizeWindow(handle, x, y, w, h);
}
