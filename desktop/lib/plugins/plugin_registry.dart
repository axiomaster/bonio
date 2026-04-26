import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'plugin_manifest.dart';

/// Persisted state for a single installed plugin.
class PluginRegistryEntry {
  final String id;
  bool enabled;
  int menuOrder;
  final DateTime installedAt;
  DateTime? updatedAt;

  PluginRegistryEntry({
    required this.id,
    this.enabled = true,
    this.menuOrder = 100,
    DateTime? installedAt,
    this.updatedAt,
  }) : installedAt = installedAt ?? DateTime.now();

  factory PluginRegistryEntry.fromJson(Map<String, dynamic> json) {
    return PluginRegistryEntry(
      id: json['id'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      menuOrder: (json['menuOrder'] as num?)?.toInt() ?? 100,
      installedAt: DateTime.tryParse(json['installedAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'menuOrder': menuOrder,
        'installedAt': installedAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}

/// Manages the set of installed plugins, their enabled/disabled state,
/// menu ordering, and persists to `registry.json`.
class PluginRegistry extends ChangeNotifier {
  final String pluginsRootDir;
  final Map<String, PluginRegistryEntry> _entries = {};
  final Map<String, PluginManifest> _manifests = {};

  PluginRegistry({required this.pluginsRootDir});

  String get _registryPath =>
      '$pluginsRootDir${Platform.pathSeparator}registry.json';

  List<PluginRegistryEntry> get entries =>
      List.unmodifiable(_entries.values.toList());

  List<PluginManifest> get manifests =>
      List.unmodifiable(_manifests.values.toList());

  PluginRegistryEntry? getEntry(String id) => _entries[id];
  PluginManifest? getManifest(String id) => _manifests[id];

  bool isEnabled(String id) => _entries[id]?.enabled ?? false;

  /// Load registry from disk + scan plugin directories for manifests.
  Future<void> load() async {
    await _loadRegistryFile();
    await _scanPluginDirs();
    notifyListeners();
  }

  Future<void> _loadRegistryFile() async {
    try {
      final file = File(_registryPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final plugins = json['plugins'] as List<dynamic>? ?? [];
        for (final p in plugins) {
          final entry =
              PluginRegistryEntry.fromJson(p as Map<String, dynamic>);
          _entries[entry.id] = entry;
        }
      }
    } catch (e) {
      debugPrint('PluginRegistry: failed to load registry.json: $e');
    }
  }

  /// Scan `~/.bonio/plugins/*/plugin.json` for installed plugins.
  Future<void> _scanPluginDirs() async {
    final root = Directory(pluginsRootDir);
    if (!await root.exists()) {
      await root.create(recursive: true);
      return;
    }

    await for (final entity in root.list()) {
      if (entity is Directory) {
        final manifest =
            await PluginManifest.loadFromDirectory(entity.path);
        if (manifest != null && manifest.id.isNotEmpty) {
          _manifests[manifest.id] = manifest;
          _entries.putIfAbsent(
            manifest.id,
            () => PluginRegistryEntry(
              id: manifest.id,
              menuOrder: manifest.menu?.order ?? 100,
            ),
          );
        }
      }
    }
  }

  /// Register a built-in plugin (no filesystem directory needed).
  void registerBuiltin(PluginManifest manifest) {
    _manifests[manifest.id] = manifest;
    _entries.putIfAbsent(
      manifest.id,
      () => PluginRegistryEntry(
        id: manifest.id,
        menuOrder: manifest.menu?.order ?? 100,
      ),
    );
    notifyListeners();
  }

  /// Toggle a plugin's enabled state and persist.
  Future<void> setEnabled(String id, bool enabled) async {
    final entry = _entries[id];
    if (entry == null) return;
    entry.enabled = enabled;
    await _save();
    notifyListeners();
  }

  /// Update menu ordering for a plugin and persist.
  Future<void> setMenuOrder(String id, int order) async {
    final entry = _entries[id];
    if (entry == null) return;
    entry.menuOrder = order;
    await _save();
    notifyListeners();
  }

  /// Reorder plugins by providing the full ordered id list.
  Future<void> reorder(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      final entry = _entries[orderedIds[i]];
      if (entry != null) {
        entry.menuOrder = (i + 1) * 10;
      }
    }
    await _save();
    notifyListeners();
  }

  /// Register a newly installed sidecar plugin.
  Future<void> install(PluginManifest manifest) async {
    _manifests[manifest.id] = manifest;
    _entries[manifest.id] = PluginRegistryEntry(
      id: manifest.id,
      menuOrder: manifest.menu?.order ?? 100,
    );
    await _save();
    notifyListeners();
  }

  /// Remove a plugin from the registry (does not delete files).
  Future<void> unregister(String id) async {
    _entries.remove(id);
    _manifests.remove(id);
    await _save();
    notifyListeners();
  }

  /// Persist registry to disk.
  Future<void> _save() async {
    try {
      final root = Directory(pluginsRootDir);
      if (!await root.exists()) await root.create(recursive: true);
      final data = {
        'version': 1,
        'plugins':
            _entries.values.map((e) => e.toJson()).toList(),
      };
      await File(_registryPath)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } catch (e) {
      debugPrint('PluginRegistry: failed to save: $e');
    }
  }

  /// Menu-relevant plugins sorted by order, filtered by enabled + platform.
  List<PluginManifest> get enabledMenuPlugins {
    final results = <PluginManifest>[];
    final sorted = _entries.values.toList()
      ..sort((a, b) => a.menuOrder.compareTo(b.menuOrder));
    for (final entry in sorted) {
      if (!entry.enabled) continue;
      final m = _manifests[entry.id];
      if (m == null || m.menu == null) continue;
      if (!m.supportsPlatform) continue;
      results.add(m);
    }
    return results;
  }
}
