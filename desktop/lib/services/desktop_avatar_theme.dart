import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/avatar_snapshot.dart';

/// Loads [theme.json] (same schema as Android `default-cat`) and maps
/// [AvatarSnapshot] to a bundled `.json` Lottie asset path.
///
/// Android uses `.lottie` files; the desktop bundle uses the same basenames
/// with `.json` (Bodymovin). Missing files are not listed here — use
/// [fallbackLottieAsset] and let [Lottie.asset] [errorBuilder] handle it.
class DesktopAvatarTheme {
  DesktopAvatarTheme._(this._states, this._motionStates, this._actionStates, this._bottomInsets);

  final Map<String, String> _states;
  final Map<String, String> _motionStates;
  final Map<String, String> _actionStates;

  /// Per-animation vertical offset (pixels at render size) to compensate for
  /// transparent padding below the visible content in each Lottie canvas.
  /// Keyed by `.lottie` filename; `"default"` provides the fallback.
  final Map<String, double> _bottomInsets;

  static const fallbackLottieAsset = 'assets/themes/default-cat/cat-idle.json';

  static Future<DesktopAvatarTheme> load() async {
    final raw = await rootBundle.loadString('assets/themes/default-cat/theme.json');
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final states = (root['states'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as String));
    final motions = (root['motionStates'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as String));
    final actions = (root['actionStates'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as String));
    final insets = (root['bottomInsets'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
    return DesktopAvatarTheme._(states, motions, actions, insets);
  }

  /// Primary animation for the current snapshot.
  /// Priority: gesture action → motion state → regular state → idle fallback.
  String lottieAssetFor(AvatarSnapshot s) {
    final g = s.gesture;
    if (g.isNotEmpty && g != 'none') {
      final key = _themeActionKeyForGesture(g);
      final file = _actionStates[key];
      if (file != null) return _toAssetPath(file);
    }
    final activity = s.effectiveActivity;
    final file = _motionStates[activity] ?? _states[activity] ?? _states['idle'];
    if (file != null) return _toAssetPath(file);
    return fallbackLottieAsset;
  }

  /// Bottom inset (pixels) for the animation currently resolved by [s].
  double bottomInsetFor(AvatarSnapshot s) {
    final lottieFile = _lottieFileFor(s);
    return _bottomInsets[lottieFile] ?? _bottomInsets['default'] ?? 10;
  }

  /// Returns the `.lottie` filename (theme key) for the given snapshot.
  String _lottieFileFor(AvatarSnapshot s) {
    final g = s.gesture;
    if (g.isNotEmpty && g != 'none') {
      final key = _themeActionKeyForGesture(g);
      final file = _actionStates[key];
      if (file != null) return file;
    }
    final activity = s.effectiveActivity;
    return _motionStates[activity] ?? _states[activity] ?? _states['idle'] ?? 'cat-idle.lottie';
  }

  String _toAssetPath(String lottieFileName) {
    final base = lottieFileName.replaceAll('.lottie', '.json');
    return 'assets/themes/default-cat/$base';
  }

  /// [theme.json] action keys are lowercase; [AvatarSnapshot.gesture] uses enum names.
  static String _themeActionKeyForGesture(String gestureName) =>
      gestureName.toLowerCase();

  @override
  String toString() =>
      'DesktopAvatarTheme(states=${_states.keys.toList()}, actions=${_actionStates.keys.toList()})';
}
