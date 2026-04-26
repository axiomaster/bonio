import 'dart:convert';
import 'dart:io';

/// Internationalized string with `zh` and `en` variants.
class I18nString {
  final String zh;
  final String en;
  const I18nString({required this.zh, required this.en});

  String get current =>
      Platform.localeName.startsWith('zh') ? zh : en;

  factory I18nString.fromJson(dynamic json) {
    if (json is String) return I18nString(zh: json, en: json);
    if (json is Map<String, dynamic>) {
      return I18nString(
        zh: json['zh'] as String? ?? '',
        en: json['en'] as String? ?? '',
      );
    }
    return const I18nString(zh: '', en: '');
  }

  Map<String, dynamic> toJson() => {'zh': zh, 'en': en};
}

/// Plugin types: in-process or independent executable.
enum PluginType { builtin, sidecar }

/// What window context a menu item requires to be shown.
enum MenuContextRequirement {
  none,
  anyWindow,
  browserWindow,
}

/// Menu configuration declared in plugin.json.
class PluginMenuConfig {
  final I18nString label;
  final String? icon;
  final int order;
  final MenuContextRequirement requiresContext;

  const PluginMenuConfig({
    required this.label,
    this.icon,
    this.order = 100,
    this.requiresContext = MenuContextRequirement.none,
  });

  factory PluginMenuConfig.fromJson(Map<String, dynamic> json) {
    return PluginMenuConfig(
      label: I18nString.fromJson(json['label']),
      icon: json['icon'] as String?,
      order: (json['order'] as num?)?.toInt() ?? 100,
      requiresContext: _parseContextReq(json['requires_context']),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label.toJson(),
        if (icon != null) 'icon': icon,
        'order': order,
        'requires_context': requiresContext.name,
      };

  static MenuContextRequirement _parseContextReq(dynamic v) {
    if (v is List) {
      if (v.contains('browser_window')) {
        return MenuContextRequirement.browserWindow;
      }
      if (v.contains('any_window')) return MenuContextRequirement.anyWindow;
    }
    if (v is String) {
      if (v == 'browser_window') return MenuContextRequirement.browserWindow;
      if (v == 'any_window') return MenuContextRequirement.anyWindow;
    }
    return MenuContextRequirement.none;
  }
}

/// Optional session configuration for plugins that need their own LLM context.
class PluginSessionConfig {
  final bool independentSession;
  final String? defaultModel;
  final String? systemPrompt;

  const PluginSessionConfig({
    this.independentSession = false,
    this.defaultModel,
    this.systemPrompt,
  });

  factory PluginSessionConfig.fromJson(Map<String, dynamic> json) {
    return PluginSessionConfig(
      independentSession: json['independent_session'] as bool? ?? false,
      defaultModel: json['default_model'] as String?,
      systemPrompt: json['system_prompt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'independent_session': independentSession,
        if (defaultModel != null) 'default_model': defaultModel,
        if (systemPrompt != null) 'system_prompt': systemPrompt,
      };
}

/// Full plugin manifest parsed from `plugin.json`.
class PluginManifest {
  final String id;
  final I18nString name;
  final String version;
  final I18nString description;
  final String author;
  final String? icon;
  final PluginType type;

  /// Per-platform executable paths (sidecar only).
  final Map<String, String> entry;

  final PluginMenuConfig? menu;
  final List<String> capabilitiesRequired;
  final PluginSessionConfig? sessionConfig;
  final String? minBonioVersion;
  final List<String> platforms;

  /// Filesystem path to the directory containing this manifest.
  final String? directoryPath;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    this.icon,
    required this.type,
    this.entry = const {},
    this.menu,
    this.capabilitiesRequired = const [],
    this.sessionConfig,
    this.minBonioVersion,
    this.platforms = const ['windows', 'macos'],
    this.directoryPath,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json,
      {String? directoryPath}) {
    return PluginManifest(
      id: json['id'] as String? ?? '',
      name: I18nString.fromJson(json['name']),
      version: json['version'] as String? ?? '0.0.0',
      description: I18nString.fromJson(json['description']),
      author: json['author'] as String? ?? '',
      icon: json['icon'] as String?,
      type: (json['type'] as String?) == 'sidecar'
          ? PluginType.sidecar
          : PluginType.builtin,
      entry: _parseEntry(json['entry']),
      menu: json['menu'] is Map<String, dynamic>
          ? PluginMenuConfig.fromJson(json['menu'] as Map<String, dynamic>)
          : null,
      capabilitiesRequired: (json['capabilities_required'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
      sessionConfig: json['session_config'] is Map<String, dynamic>
          ? PluginSessionConfig.fromJson(
              json['session_config'] as Map<String, dynamic>)
          : null,
      minBonioVersion: json['min_bonio_version'] as String?,
      platforms: (json['platforms'] as List<dynamic>?)?.cast<String>() ??
          const ['windows', 'macos'],
      directoryPath: directoryPath,
    );
  }

  /// Load manifest from a plugin.json file.
  static Future<PluginManifest?> loadFromDirectory(String dirPath) async {
    try {
      final file = File('$dirPath${Platform.pathSeparator}plugin.json');
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return PluginManifest.fromJson(json, directoryPath: dirPath);
    } catch (_) {
      return null;
    }
  }

  /// Resolve the executable path for the current platform.
  String? get executablePath {
    if (type != PluginType.sidecar || directoryPath == null) return null;
    final key = Platform.isWindows ? 'windows' : 'macos';
    final exe = entry[key];
    if (exe == null) return null;
    return '$directoryPath${Platform.pathSeparator}$exe';
  }

  bool get supportsPlatform {
    if (Platform.isWindows) return platforms.contains('windows');
    if (Platform.isMacOS) return platforms.contains('macos');
    return false;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name.toJson(),
        'version': version,
        'description': description.toJson(),
        'author': author,
        if (icon != null) 'icon': icon,
        'type': type == PluginType.sidecar ? 'sidecar' : 'builtin',
        if (entry.isNotEmpty) 'entry': entry,
        if (menu != null) 'menu': menu!.toJson(),
        if (capabilitiesRequired.isNotEmpty)
          'capabilities_required': capabilitiesRequired,
        if (sessionConfig != null) 'session_config': sessionConfig!.toJson(),
        if (minBonioVersion != null) 'min_bonio_version': minBonioVersion,
        'platforms': platforms,
      };

  static Map<String, String> _parseEntry(dynamic v) {
    if (v is Map) {
      return v.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return const {};
  }
}
