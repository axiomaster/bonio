import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../models/agent_avatar_models.dart';
import 'avatar_controller.dart';
import 'desktop_tts.dart';

/// Handles gateway `avatar.command` events (same schema as Android [AvatarCommandExecutor]).
class AvatarCommandExecutor {
  AvatarCommandExecutor({
    required this.controller,
    DesktopTts? tts,
  }) : _tts = tts ?? DesktopTts();

  final AvatarController controller;
  final DesktopTts _tts;

  void execute(String? payloadJson) {
    if (payloadJson == null || payloadJson.trim().isEmpty) return;
    try {
      final obj = jsonDecode(payloadJson) as Map<String, dynamic>;
      final action = obj['action'] as String?;
      if (action == null) return;
      final params = obj['params'];
      final paramsMap =
          params is Map<String, dynamic> ? params : <String, dynamic>{};
      unawaited(_executeAction(action, paramsMap));
    } catch (e, st) {
      debugPrint('avatar.command parse error: $e\n$st');
    }
  }

  Future<void> _executeAction(String action, Map<String, dynamic> params) async {
    switch (action) {
      case 'setState':
        await _setState(params);
        break;
      case 'moveTo':
        await _moveTo(params);
        break;
      case 'setBubble':
        _setBubble(params);
        break;
      case 'clearBubble':
        controller.clearBubble();
        break;
      case 'tts':
        await _ttsSpeak(params);
        break;
      case 'stopTts':
        await _ttsStop();
        break;
      case 'playSound':
        _playSound(params);
        break;
      case 'setColorFilter':
        _setColorFilter(params);
        break;
      case 'setPosition':
        _setPosition(params);
        break;
      case 'cancelMovement':
        controller.cancelMovement();
        break;
      case 'performAction':
        _performAction(params);
        break;
      case 'sequence':
        await _sequence(params);
        break;
      default:
        debugPrint('avatar.command unknown action: $action');
    }
  }

  Future<void> _setState(Map<String, dynamic> params) async {
    final stateName = params['state'] as String?;
    if (stateName == null) return;
    final state = parseAgentAvatarActivity(stateName);
    if (state == null) return;
    final temporary = params['temporary'] == true;
    if (temporary) {
      controller.showTemporaryState(state);
    } else {
      controller.setActivity(state);
    }
  }

  Future<void> _moveTo(Map<String, dynamic> params) async {
    final x = (params['x'] as num?)?.toDouble();
    final y = (params['y'] as num?)?.toDouble();
    if (x == null || y == null) return;
    final mode = params['mode'] as String? ?? 'walk';

    switch (mode) {
      case 'run':
        controller.runTo(x, y);
        break;
      case 'portal':
        controller.runTo(x, y);
        break;
      case 'walk':
      default:
        controller.walkTo(x, y);
        break;
    }
  }

  void _setBubble(Map<String, dynamic> params) {
    final text = params['text'] as String?;
    if (text == null) return;
    final bg = (params['bgColor'] as num?)?.toInt();
    final fg = (params['textColor'] as num?)?.toInt();
    final countdown = params['countdown'] as String?;
    controller.setBubble(
      text: text,
      bgArgb: bg,
      textArgb: fg,
      countdown: countdown,
    );
  }

  Future<void> _ttsSpeak(Map<String, dynamic> params) async {
    final text = params['text'] as String?;
    if (text == null || text.isEmpty) return;
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('avatar tts failed: $e');
    }
  }

  Future<void> _ttsStop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void _playSound(Map<String, dynamic> params) {
    final type = params['type'] as String? ?? 'notification';
    try {
      if (type == 'alarm') {
        SystemSound.play(SystemSoundType.alert);
      } else {
        SystemSound.play(SystemSoundType.click);
      }
    } catch (e) {
      debugPrint('playSound: $e');
    }
  }

  void _setColorFilter(Map<String, dynamic> params) {
    final raw = params['color'];
    if (raw == null) {
      controller.setColorFilter(null);
      return;
    }
    final n = (raw as num?)?.toInt();
    if (n == null) {
      controller.setColorFilter(null);
      return;
    }
    controller.setColorFilter(Color(n));
  }

  void _setPosition(Map<String, dynamic> params) {
    final x = (params['x'] as num?)?.toDouble();
    final y = (params['y'] as num?)?.toDouble();
    if (x == null || y == null) return;
    controller.setPosition(x, y);
  }

  void _performAction(Map<String, dynamic> params) {
    final type = params['type'] as String?;
    if (type == null) return;
    final x = (params['x'] as num?)?.toDouble();
    final y = (params['y'] as num?)?.toDouble();
    controller.performAction(type, x, y);
  }

  Future<void> _sequence(Map<String, dynamic> params) async {
    final steps = params['steps'];
    if (steps is! List) return;
    for (final step in steps) {
      if (step is! Map<String, dynamic>) continue;
      final action = step['action'] as String?;
      if (action == null) continue;
      final stepParams = step['params'];
      final pmap = stepParams is Map<String, dynamic>
          ? stepParams
          : <String, dynamic>{};
      await _executeAction(action, pmap);
      final delayMs = (step['delayMs'] as num?)?.toInt() ?? 0;
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
  }
}
