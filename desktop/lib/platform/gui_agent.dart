import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'win32_screen_capture.dart';
import 'screen_capture_types.dart';

import 'cdp/cdp_browser_agent.dart';
import 'win32/win32_screen_agent.dart';
import 'win32/win32_window_agent.dart';
import 'macos/macos_screen_agent.dart';
import 'macos/macos_window_agent.dart';

// ---------------------------------------------------------------------------
// Data classes shared across all platform implementations
// ---------------------------------------------------------------------------

class HeadingInfo {
  final int level;
  final String text;
  final String id;
  const HeadingInfo({required this.level, required this.text, required this.id});

  Map<String, dynamic> toJson() => {'level': level, 'text': text, 'id': id};

  factory HeadingInfo.fromJson(Map<String, dynamic> m) => HeadingInfo(
        level: (m['level'] as num?)?.toInt() ?? 2,
        text: m['text'] as String? ?? '',
        id: m['id'] as String? ?? '',
      );
}

class PageContent {
  final String title;
  final String url;
  final String text;
  final List<HeadingInfo> headings;
  const PageContent({
    required this.title,
    required this.url,
    required this.text,
    required this.headings,
  });
}

// ---------------------------------------------------------------------------
// Abstract interfaces
// ---------------------------------------------------------------------------

/// Captures screenshots of the screen or individual windows.
abstract class ScreenAgent {
  ScreenCaptureResult? captureScreen();
  ScreenCaptureResult? captureWindow(int windowHandle);
  double getDpiScale(int windowHandle);
}

/// Queries and manipulates OS windows.
abstract class WindowAgent {
  int getForegroundWindow();
  String getWindowTitle(int handle);
  String getWindowClassName(int handle);
  Rect getWindowRect(int handle);
  bool isBrowserWindow(int handle);
  bool isNormalAppWindow(int handle);
  List<int>? getMonitorWorkArea(int handle);
  bool resizeWindow(int handle, int x, int y, int w, int h);
}

/// Automates a browser via Chrome DevTools Protocol.
abstract class BrowserAgent {
  Future<void> ensureConnected();

  /// Try to connect to an already-running browser with remote debugging enabled.
  /// Returns true if connected. Does NOT launch a new browser instance.
  /// [urlHint] — if provided, prefer the tab matching this URL.
  Future<bool> tryConnectToExisting({String? urlHint});

  Future<String> getCurrentUrl();
  Future<String> getPageTitle();
  Future<PageContent> extractPageContent({int maxLength = 50000});
  Future<List<HeadingInfo>> extractHeadings();
  Future<dynamic> executeScript(String js);
  Future<void> navigate(String url);
  Future<Uint8List?> takeScreenshot();
  Future<void> close();
  bool get isConnected;
}

// ---------------------------------------------------------------------------
// Facade
// ---------------------------------------------------------------------------

class GuiAgent {
  final ScreenAgent screen;
  final WindowAgent window;
  final BrowserAgent browser;

  GuiAgent({required this.screen, required this.window, required this.browser});

  factory GuiAgent.create() {
    return GuiAgent(
      screen:
          Platform.isWindows ? Win32ScreenAgent() : MacScreenAgent(),
      window:
          Platform.isWindows ? Win32WindowAgent() : MacWindowAgent(),
      browser: CdpBrowserAgent(),
    );
  }

  void dispose() {
    browser.close();
  }
}
