import 'dart:io' show exit;

import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_strings.dart';

/// Manages the system tray icon and menu for the main Bonio window.
///
/// - Left-click on tray icon: show the main window.
/// - Right-click on tray icon: pop up context menu (Show / Exit).
/// - "Exit" terminates the application (including avatar).
class TrayService {
  final SystemTray _systemTray = SystemTray();

  /// Called before force-exit so the app can clean up (close avatar, etc.).
  /// Must complete within 2 seconds or the process is killed anyway.
  Future<void> Function()? onExitRequested;

  Future<void> init() async {
    const iconPath = 'assets/app_icon.ico';
    await _systemTray.initSystemTray(
      title: '',
      iconPath: iconPath,
      toolTip: S.current.appName,
    );

    await _systemTray.setContextMenu([
      MenuItem(
        label: S.current.trayShow,
        onClicked: _showMainWindow,
      ),
      MenuSeparator(),
      MenuItem(
        label: S.current.trayExit,
        onClicked: _exitApp,
      ),
    ]);

    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == 'leftMouseUp') {
        _showMainWindow();
      } else if (eventName == 'rightMouseUp') {
        _systemTray.popUpContextMenu();
      }
    });
  }

  void _showMainWindow() {
    windowManager.show();
    windowManager.focus();
  }

  void _exitApp() {
    debugPrint('TrayService: Exit requested');
    final cleanup = onExitRequested;
    if (cleanup != null) {
      cleanup().timeout(const Duration(seconds: 2), onTimeout: () {
        debugPrint('TrayService: cleanup timed out, forcing exit');
      }).then((_) => exit(0), onError: (_) => exit(0));
    } else {
      exit(0);
    }
    Future.delayed(const Duration(seconds: 3), () => exit(0));
  }
}
