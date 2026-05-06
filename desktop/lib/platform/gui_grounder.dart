import 'dart:convert';

import '../models/ui_structure.dart';
import '../services/app_logger.dart';
import 'cdp/cdp_browser_agent.dart';
import 'gui_agent.dart';

final _log = AppLogger.instance;

/// How the grounding was triggered.
enum TriggerSource {
  /// User clicked the avatar.
  manual,

  /// Automatic trigger after window switch (future).
  autoWindowSwitch,

  /// Automatic trigger after stable-frame detection (future).
  autoStableFrame,
}

/// Result of a UI grounding operation.
class GroundingResult {
  final UiStructure structure;
  final String source; // "cdp", "uia", "ocr"

  const GroundingResult({required this.structure, required this.source});
}

/// Extracts a normalised [UiStructure] from the current foreground window.
///
/// Strategy (in priority order):
/// 1. Browser windows → CDP Accessibility.getFullAXTree
/// 2. Standard Win32 apps → UIA (UI Automation) COM — not yet implemented
/// 3. Fallback → screenshot + PaddleOCR (not yet implemented)
class GuiGrounder {
  final GuiAgent agent;
  final CdpBrowserAgent? cdpAgent;

  GuiGrounder({required this.agent, this.cdpAgent});

  /// Ground the window identified by [hwnd].
  ///
  /// Returns null if all strategies fail or the window cannot be accessed.
  Future<GroundingResult?> ground(
    int hwnd, {
    TriggerSource source = TriggerSource.manual,
  }) async {
    final title = agent.window.getWindowTitle(hwnd);
    final className = agent.window.getWindowClassName(hwnd);
    final isBrowser = agent.window.isBrowserWindow(hwnd);

    _log.info('grounding hwnd=$hwnd title="$title" class="$className" '
        'isBrowser=$isBrowser source=${source.name}');

    // Strategy 1: CDP accessibility tree (browsers)
    if (isBrowser && cdpAgent != null) {
      final result = await _groundViaCdp(title);
      if (result != null) return result;
    }

    // Strategy 2: UIA (not yet implemented) — stub
    // final result = await _groundViaUia(hwnd);
    // if (result != null) return result;

    // Strategy 3: Screenshot + OCR (not yet implemented) — stub
    // final result = await _groundViaOcr(hwnd, title);
    // if (result != null) return result;

    // Minimal fallback: window-level info only
    _log.info('grounding: all strategies failed, returning window-only structure');
    return GroundingResult(
      source: 'window',
      structure: UiStructure(
        appName: className,
        title: title,
      ),
    );
  }

  Future<GroundingResult?> _groundViaCdp(String title) async {
    try {
      final raw = await cdpAgent!.getAccessibilityTree();
      if (raw == null || raw.isEmpty) return null;
      final structure = _parseCdpAxTree(raw, title);
      if (structure != null) {
        return GroundingResult(source: 'cdp', structure: structure);
      }
    } catch (e) {
      _log.warn('CDP grounding failed: $e');
    }
    return null;
  }

  /// Parse a CDP Accessibility.getFullAXTree response into [UiStructure].
  ///
  /// The CDP AXTree format:
  /// ```json
  /// {"nodes": [{"nodeId": "...", "ignored": false, "role": {...},
  ///   "name": {...}, "properties": [...]}]}
  /// ```
  static UiStructure? _parseCdpAxTree(String raw, String title) {
    try {
      final map = _jsonDecode(raw);
      if (map == null) return null;
      final nodes = map['nodes'] as List?;
      if (nodes == null || nodes.isEmpty) return null;

      final components = <UiComponent>[];
      for (final node in nodes) {
        if (node is! Map) continue;
        final ignored = node['ignored'] as bool? ?? false;
        if (ignored) continue;

        final role = _extractString(node, 'role', 'value');
        final name = _extractString(node, 'name', 'value');
        final type = _cdpRoleToType(role);

        // Skip purely structural nodes without any content
        if (type == 'container' && (name == null || name.isEmpty)) continue;

        final bbox = _extractBbox(node);

        components.add(UiComponent(
          type: type,
          left: bbox[0],
          top: bbox[1],
          width: bbox[2],
          height: bbox[3],
          text: (type == 'text' || type == 'button' || type == 'input')
              ? name
              : null,
          actionable: _cdpRoleToActionable(role),
        ));
      }

      if (components.isEmpty) return null;

      return UiStructure(
        appName: 'browser',
        title: title,
        components: components,
      );
    } catch (_) {
      return null;
    }
  }

  // --- helpers ---

  static dynamic _jsonDecode(String raw) {
    // The CDP response from our sendCommand returns the full result object.
    // The actual AXTree is in result.result.nodes.
    try {
      final outer = _parseJson(raw);
      if (outer == null) return null;
      // CDP result wrapping: {result: {nodes: [...]}}
      final result = outer['result'];
      if (result is Map) {
        if (result.containsKey('nodes')) return result;
      }
      if (outer.containsKey('nodes')) return outer;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parseJson(String raw) {
    try {
      // Use dart:convert — imported at file scope
      return _fastDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _fastDecode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  static String _extractString(Map node, String key, String subKey) {
    final obj = node[key];
    if (obj is Map) {
      final v = obj[subKey];
      if (v is String) return v;
    }
    if (obj is String) return obj;
    return '';
  }

  static List<double> _extractBbox(Map node) {
    // CDP AX nodes may have boundingBox in backendNodeId or properties
    final bb = node['boundingBox'];
    if (bb is Map) {
      return [
        (bb['x'] as num?)?.toDouble() ?? 0,
        (bb['y'] as num?)?.toDouble() ?? 0,
        (bb['width'] as num?)?.toDouble() ?? 0,
        (bb['height'] as num?)?.toDouble() ?? 0,
      ];
    }
    return [0, 0, 0, 0];
  }

  static String _cdpRoleToType(String? role) {
    switch (role) {
      case 'StaticText':
      case 'inlineTextBox':
      case 'text':
        return 'text';
      case 'image':
      case 'Image':
        return 'image';
      case 'button':
      case 'Button':
      case 'toggleButton':
        return 'button';
      case 'textbox':
      case 'textField':
      case 'searchBox':
        return 'input';
      case 'link':
      case 'Link':
        return 'link';
      default:
        return 'container';
    }
  }

  static String _cdpRoleToActionable(String? role) {
    switch (role) {
      case 'button':
      case 'Button':
      case 'toggleButton':
      case 'link':
      case 'Link':
      case 'menuItem':
      case 'menubar':
      case 'tab':
        return 'click';
      case 'textbox':
      case 'textField':
      case 'searchBox':
        return 'input';
      case 'scrollBar':
      case 'scrollArea':
        return 'scroll';
      case 'listBox':
      case 'comboBox':
      case 'radioButton':
        return 'select';
      default:
        return 'none';
    }
  }
}

