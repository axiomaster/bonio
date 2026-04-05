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
  DesktopAvatarTheme._(this._states, this._actionStates);

  final Map<String, String> _states;
  final Map<String, String> _actionStates;

  static const fallbackLottieAsset = 'assets/themes/default-cat/cat-idle.json';

  static Future<DesktopAvatarTheme> load() async {
    final raw = await rootBundle.loadString('assets/themes/default-cat/theme.json');
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final states = (root['states'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as String));
    final actions = (root['actionStates'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as String));
    return DesktopAvatarTheme._(states, actions);
  }

  /// Primary animation for the current snapshot (gesture overrides activity).
  String lottieAssetFor(AvatarSnapshot s) {
    final g = s.gesture;
    if (g.isNotEmpty && g != 'none') {
      final key = _themeActionKeyForGesture(g);
      final file = _actionStates[key];
      if (file != null) return _toAssetPath(file);
    }
    final file = _states[s.effectiveActivity] ?? _states['idle'];
    if (file != null) return _toAssetPath(file);
    return fallbackLottieAsset;
  }

  String _toAssetPath(String lottieFileName) {
    final base = lottieFileName.replaceAll('.lottie', '.json');
    return 'assets/themes/default-cat/$base';
  }

  /// [theme.json] action keys are lowercase; [AvatarSnapshot.gesture] uses enum names.
  static String _themeActionKeyForGesture(String gestureName) =>
      gestureName.toLowerCase();
}
