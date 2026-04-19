import 'dart:ui';

import '../gui_agent.dart';

/// macOS [WindowAgent] stub.
///
/// Phase 2 will implement via NSWorkspace / Accessibility (AXUIElement).
class MacWindowAgent implements WindowAgent {
  @override
  int getForegroundWindow() => 0;

  @override
  String getWindowTitle(int handle) => '';

  @override
  String getWindowClassName(int handle) => '';

  @override
  Rect getWindowRect(int handle) => Rect.zero;

  @override
  bool isBrowserWindow(int handle) => false;

  @override
  bool isNormalAppWindow(int handle) => false;

  @override
  List<int>? getMonitorWorkArea(int handle) => null;

  @override
  bool resizeWindow(int handle, int x, int y, int w, int h) => false;
}
