import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'plugin_bridge.dart';
import 'plugin_host.dart';
import 'plugin_interface.dart';
import 'plugin_manifest.dart';
import 'plugin_registry.dart';

/// Top-level facade for the plugin system.
///
/// Manages discovery, loading, activation, menu generation, and routing
/// for both built-in and sidecar plugins.
class PluginManager extends ChangeNotifier {
  late final PluginRegistry registry;
  final Map<String, BonioPlugin> _builtins = {};
  final Map<String, PluginHost> _hosts = {};

  /// Callback that handles capability requests from sidecar plugins.
  /// Set by the host (e.g., NodeRuntime) after construction.
  PluginCapabilityHandler? capabilityHandler;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize the plugin system: create dirs, load registry, scan plugins.
  Future<void> initialize() async {
    if (_initialized) return;

    final appSupport = await getApplicationSupportDirectory();
    final pluginsRoot =
        '${appSupport.path}${Platform.pathSeparator}plugins';

    registry = PluginRegistry(pluginsRootDir: pluginsRoot);
    await registry.load();

    // Register any built-in plugins that were added before init
    for (final plugin in _builtins.values) {
      registry.registerBuiltin(plugin.manifest);
    }

    _initialized = true;
    debugPrint('PluginManager: initialized with '
        '${registry.entries.length} plugins '
        '(${_builtins.length} builtin)');
    notifyListeners();
  }

  /// Register a built-in (in-process) plugin.
  void registerBuiltin(BonioPlugin plugin) {
    _builtins[plugin.manifest.id] = plugin;
    if (_initialized) {
      registry.registerBuiltin(plugin.manifest);
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------------
  // Menu
  // -------------------------------------------------------------------------

  /// Build the list of menu items for the right-click popup.
  ///
  /// Returns empty list if the plugin system hasn't initialized yet.
  List<Map<String, dynamic>> getMenuItems({
    int hwnd = 0,
    bool isBrowser = false,
  }) {
    if (!_initialized) return [];

    final plugins = registry.enabledMenuPlugins;
    final items = <Map<String, dynamic>>[];

    for (var i = 0; i < plugins.length; i++) {
      final m = plugins[i];
      final menu = m.menu!;

      if (menu.requiresContext == MenuContextRequirement.browserWindow &&
          !isBrowser) {
        continue;
      }
      if (menu.requiresContext == MenuContextRequirement.anyWindow &&
          hwnd == 0) {
        continue;
      }

      items.add({
        'id': i + 1,
        'label': menu.label.current,
        'enabled': true,
      });
    }

    return items;
  }

  /// Map of menu numeric id -> plugin id for action routing.
  Map<int, String> getMenuActions({
    int hwnd = 0,
    bool isBrowser = false,
  }) {
    if (!_initialized) return {};

    final plugins = registry.enabledMenuPlugins;
    final actions = <int, String>{};

    var menuId = 1;
    for (final m in plugins) {
      final menu = m.menu!;
      if (menu.requiresContext == MenuContextRequirement.browserWindow &&
          !isBrowser) {
        continue;
      }
      if (menu.requiresContext == MenuContextRequirement.anyWindow &&
          hwnd == 0) {
        continue;
      }
      actions[menuId] = m.id;
      menuId++;
    }

    return actions;
  }

  /// Execute a plugin's menu action by plugin id.
  Future<void> executeMenuAction(
      String pluginId, PluginMenuContext context) async {
    // Built-in plugin?
    final builtin = _builtins[pluginId];
    if (builtin != null) {
      try {
        await builtin.onMenuAction(context);
      } catch (e) {
        debugPrint('PluginManager: builtin $pluginId error: $e');
      }
      return;
    }

    // Sidecar plugin
    final manifest = registry.getManifest(pluginId);
    if (manifest == null || manifest.type != PluginType.sidecar) {
      debugPrint('PluginManager: unknown plugin $pluginId');
      return;
    }

    try {
      final host = _getOrCreateHost(manifest);
      await host.sendMenuAction(context.toJson());
    } catch (e) {
      debugPrint('PluginManager: sidecar $pluginId error: $e');
    }
  }

  PluginHost _getOrCreateHost(PluginManifest manifest) {
    return _hosts.putIfAbsent(manifest.id, () {
      return PluginHost(
        manifest: manifest,
        capabilityHandler: capabilityHandler ?? _defaultHandler,
      );
    });
  }

  Future<Map<String, dynamic>> _defaultHandler(
      String method, Map<String, dynamic> params) async {
    debugPrint('PluginManager: unhandled capability call: $method');
    return {'error': 'No capability handler registered'};
  }

  // -------------------------------------------------------------------------
  // Plugin installation
  // -------------------------------------------------------------------------

  /// Install a plugin from a zip archive file.
  Future<void> installFromZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find plugin.json in archive
    final manifestEntry = archive.files.firstWhere(
      (f) => f.name.endsWith('plugin.json'),
      orElse: () => throw StateError('No plugin.json in archive'),
    );

    final manifestJson =
        jsonDecode(utf8.decode(manifestEntry.content as List<int>))
            as Map<String, dynamic>;
    final pluginId = manifestJson['id'] as String? ?? '';
    if (pluginId.isEmpty) throw StateError('Plugin manifest has no id');

    // Extract to plugins directory
    final targetDir =
        '${registry.pluginsRootDir}${Platform.pathSeparator}$pluginId';
    final dir = Directory(targetDir);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    for (final file in archive.files) {
      if (file.isFile) {
        // Strip any leading directory from zip
        final name = file.name.contains('/')
            ? file.name.substring(file.name.indexOf('/') + 1)
            : file.name;
        if (name.isEmpty) continue;
        final outFile = File('$targetDir${Platform.pathSeparator}$name');
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }

    // Make executable runnable on macOS/Linux
    if (!Platform.isWindows) {
      final manifest = PluginManifest.fromJson(manifestJson,
          directoryPath: targetDir);
      final exe = manifest.executablePath;
      if (exe != null) {
        await Process.run('chmod', ['+x', exe]);
      }
    }

    // Reload
    final manifest =
        await PluginManifest.loadFromDirectory(targetDir);
    if (manifest != null) {
      await registry.install(manifest);
    }

    notifyListeners();
  }

  /// Uninstall a sidecar plugin by id.
  Future<void> uninstall(String pluginId) async {
    // Stop if running
    final host = _hosts.remove(pluginId);
    if (host != null) await host.stop();

    // Remove files
    final manifest = registry.getManifest(pluginId);
    if (manifest?.directoryPath != null) {
      final dir = Directory(manifest!.directoryPath!);
      if (await dir.exists()) await dir.delete(recursive: true);
    }

    await registry.unregister(pluginId);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Reload the registry (e.g., after installing a new plugin).
  Future<void> reload() async {
    await registry.load();
    for (final plugin in _builtins.values) {
      registry.registerBuiltin(plugin.manifest);
    }
    notifyListeners();
  }

  /// Stop all running sidecar processes.
  Future<void> stopAll() async {
    for (final host in _hosts.values) {
      await host.stop();
    }
    _hosts.clear();
  }

  @override
  void dispose() {
    for (final host in _hosts.values) {
      host.dispose();
    }
    _hosts.clear();
    super.dispose();
  }
}
