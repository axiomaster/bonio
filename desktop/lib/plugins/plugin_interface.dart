import 'plugin_manifest.dart';

/// Context provided to a plugin when a menu action is triggered.
class PluginMenuContext {
  final int hwnd;
  final String windowTitle;
  final String windowClass;
  final bool isBrowser;
  final double screenDpi;

  const PluginMenuContext({
    this.hwnd = 0,
    this.windowTitle = '',
    this.windowClass = '',
    this.isBrowser = false,
    this.screenDpi = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'hwnd': hwnd,
        'windowTitle': windowTitle,
        'windowClass': windowClass,
        'isBrowser': isBrowser,
        'screenDpi': screenDpi,
      };

  factory PluginMenuContext.fromJson(Map<String, dynamic> json) {
    return PluginMenuContext(
      hwnd: (json['hwnd'] as num?)?.toInt() ?? 0,
      windowTitle: json['windowTitle'] as String? ?? '',
      windowClass: json['windowClass'] as String? ?? '',
      isBrowser: json['isBrowser'] as bool? ?? false,
      screenDpi: (json['screenDpi'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Interface for built-in plugins that run in-process.
///
/// Each built-in plugin implements this interface and is registered directly
/// with [PluginManager]. Sidecar plugins communicate via JSON-RPC instead
/// of this interface, but the host translates to the same lifecycle.
abstract class BojiPlugin {
  /// The plugin's manifest, declaring its id, name, menu config, etc.
  PluginManifest get manifest;

  /// Called once when the plugin is first activated. Use for setup.
  Future<void> activate() async {}

  /// Called when the user triggers this plugin's menu item.
  ///
  /// [context] provides information about the current desktop state
  /// (foreground window, whether it's a browser, etc.).
  Future<void> onMenuAction(PluginMenuContext context);

  /// Called when the plugin is deactivated (disabled or app shutting down).
  Future<void> deactivate() async {}
}
