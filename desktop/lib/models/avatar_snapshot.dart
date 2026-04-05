import 'package:flutter/material.dart';

import 'agent_avatar_models.dart';

/// Serializable avatar state for the floating window (separate Flutter engine).
class AvatarSnapshot {
  final double posX;
  final double posY;
  final String activity;
  final String effectiveActivity;
  final String? bubbleText;
  final int? bubbleBgArgb;
  final int? bubbleTextArgb;
  final String? bubbleCountdown;
  final int? colorArgb;
  final String gesture;
  final bool isMoving;

  const AvatarSnapshot({
    required this.posX,
    required this.posY,
    required this.activity,
    required this.effectiveActivity,
    this.bubbleText,
    this.bubbleBgArgb,
    this.bubbleTextArgb,
    this.bubbleCountdown,
    this.colorArgb,
    required this.gesture,
    required this.isMoving,
  });

  Map<String, dynamic> toJson() => {
        'posX': posX,
        'posY': posY,
        'activity': activity,
        'effectiveActivity': effectiveActivity,
        'bubbleText': bubbleText,
        'bubbleBgArgb': bubbleBgArgb,
        'bubbleTextArgb': bubbleTextArgb,
        'bubbleCountdown': bubbleCountdown,
        'colorArgb': colorArgb,
        'gesture': gesture,
        'isMoving': isMoving,
      };

  factory AvatarSnapshot.fromJson(Map<String, dynamic> m) {
    return AvatarSnapshot(
      posX: (m['posX'] as num?)?.toDouble() ?? 0,
      posY: (m['posY'] as num?)?.toDouble() ?? 0,
      activity: m['activity'] as String? ?? 'idle',
      effectiveActivity: m['effectiveActivity'] as String? ?? 'idle',
      bubbleText: m['bubbleText'] as String?,
      bubbleBgArgb: (m['bubbleBgArgb'] as num?)?.toInt(),
      bubbleTextArgb: (m['bubbleTextArgb'] as num?)?.toInt(),
      bubbleCountdown: m['bubbleCountdown'] as String?,
      colorArgb: (m['colorArgb'] as num?)?.toInt(),
      gesture: m['gesture'] as String? ?? 'none',
      isMoving: m['isMoving'] as bool? ?? false,
    );
  }

  AgentAvatarActivity get effectiveActivityEnum =>
      parseAgentAvatarActivity(effectiveActivity) ??
      AgentAvatarActivity.idle;

  DesktopAvatarGesture get gestureEnum {
    for (final g in DesktopAvatarGesture.values) {
      if (g.name == gesture) return g;
    }
    return DesktopAvatarGesture.none;
  }

  Color? get colorFilter =>
      colorArgb != null ? Color(colorArgb!) : null;

  /// OS window for the separate avatar engine: wide enough for the bubble,
  /// tall enough for bubble + avatar + padding.
  static const kFloatingWindowPadding = 12.0;
  static const _kBubbleMaxHeight = 60.0;
  /// Must match the initial size in [packages/desktop_multi_window] (Win/macOS/Linux);
  /// if this changes, update those native literals or the first Flutter surface will
  /// not match [window_manager] and the avatar can look squashed or ghost while dragging.
  static const kFloatingWindowSize = Size(
    220 + kFloatingWindowPadding * 2,
    72 + _kBubbleMaxHeight + kFloatingWindowPadding * 2,
  );
}
