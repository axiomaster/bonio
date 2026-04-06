import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

/// Manages the system tray icon and menu for the main BoJi window.
///
/// - Left-click on tray icon: show the main window.
/// - Right-click on tray icon: pop up context menu (Show / Exit).
/// - "Exit" terminates the application (including avatar).
class TrayService {
  final SystemTray _systemTray = SystemTray();
  VoidCallback? onExitRequested;

  Future<void> init() async {
    const iconPath = 'assets/app_icon.ico';
    await _systemTray.initSystemTray(
      title: '',
      iconPath: iconPath,
      toolTip: 'BoJi Desktop',
    );

    await _systemTray.setContextMenu([
      MenuItem(
        label: 'Show',
        onClicked: _showMainWindow,
      ),
      MenuSeparator(),
      MenuItem(
        label: 'Exit',
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
    onExitRequested?.call();
  }
}
