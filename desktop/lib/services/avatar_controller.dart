import 'dart:async' show Completer, Future, Timer, unawaited;
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/agent_avatar_models.dart';
import '../models/avatar_snapshot.dart';

/// Desktop avatar overlay state: position, activity, bubble, gestures, tint.
/// Coordinates are logical pixels within the app window (same as Android pixel cmds).
class AvatarController extends ChangeNotifier {
  static const double avatarVisualSize = 72;
  static const int _actionDisplayMs = 2200;
  static const int _temporaryStateMs = 2800;

  AgentAvatarActivity _activity = AgentAvatarActivity.idle;
  AgentAvatarActivity? _temporaryActivity;
  Timer? _temporaryTimer;

  String? _bubbleText;
  int? _bubbleBgArgb;
  int? _bubbleTextArgb;
  String? _bubbleCountdown;

  Color? _colorFilter;

  Offset _position = Offset.zero;
  bool _positionInitialized = false;
  Size _bounds = Size.zero;

  DesktopAvatarGesture _gesture = DesktopAvatarGesture.none;
  Timer? _gestureClearTimer;

  Offset? _moveTarget;
  Timer? _moveTimer;
  double _moveSpeedPxPerSec = 320;

  AgentAvatarActivity get activity => _activity;
  AgentAvatarActivity get effectiveActivity =>
      _temporaryActivity ?? _activity;

  String? get bubbleText => _bubbleText;
  int? get bubbleBgArgb => _bubbleBgArgb;
  int? get bubbleTextArgb => _bubbleTextArgb;
  String? get bubbleCountdown => _bubbleCountdown;

  Color? get colorFilter => _colorFilter;

  Offset get position => _position;
  bool get positionInitialized => _positionInitialized;
  bool get isMoving => _moveTimer != null;

  DesktopAvatarGesture get gesture => _gesture;

  /// Call from overlay on layout so movement clamps and defaults work.
  void setBounds(Size size) {
    if (size == Size.zero) return;
    final changed = size != _bounds;
    _bounds = size;
    if (!_positionInitialized && size.width > 0 && size.height > 0) {
      final compact = size.width <= avatarVisualSize + 32 &&
          size.height <= avatarVisualSize + 32;
      if (compact) {
        _position = Offset(
          (size.width - avatarVisualSize) / 2,
          (size.height - avatarVisualSize) / 2,
        );
      } else {
        _position = Offset(
          (size.width - avatarVisualSize - 16).clamp(0.0, double.infinity),
          (size.height - avatarVisualSize - 24).clamp(0.0, double.infinity),
        );
      }
      _positionInitialized = true;
      notifyListeners();
    } else if (changed) {
      _position = _clampPosition(_position);
      notifyListeners();
    }
  }

  void setActivity(AgentAvatarActivity state) {
    _temporaryTimer?.cancel();
    _temporaryTimer = null;
    _temporaryActivity = null;
    _activity = state;
    notifyListeners();
  }

  void showTemporaryState(AgentAvatarActivity state) {
    _temporaryTimer?.cancel();
    _temporaryActivity = state;
    notifyListeners();
    _temporaryTimer = Timer(
        const Duration(milliseconds: _temporaryStateMs), () {
      _temporaryActivity = null;
      _temporaryTimer = null;
      notifyListeners();
    });
  }

  Timer? _bubbleAutoHideTimer;
  static const _bubbleAutoHideMs = 10000;

  void setBubble({
    required String text,
    int? bgArgb,
    int? textArgb,
    String? countdown,
  }) {
    _bubbleText = text;
    _bubbleBgArgb = bgArgb;
    _bubbleTextArgb = textArgb;
    _bubbleCountdown = countdown;
    _restartBubbleAutoHide();
    notifyListeners();
  }

  void setBubbleCountdown(String? text) {
    _bubbleCountdown = text;
    notifyListeners();
  }

  void clearBubble() {
    _bubbleAutoHideTimer?.cancel();
    _bubbleAutoHideTimer = null;
    _bubbleText = null;
    _bubbleBgArgb = null;
    _bubbleTextArgb = null;
    _bubbleCountdown = null;
    notifyListeners();
  }

  void _restartBubbleAutoHide() {
    _bubbleAutoHideTimer?.cancel();
    _bubbleAutoHideTimer = Timer(
      const Duration(milliseconds: _bubbleAutoHideMs),
      () {
        _bubbleAutoHideTimer = null;
        clearBubble();
      },
    );
  }

  void setColorFilter(Color? color) {
    _colorFilter = color;
    notifyListeners();
  }

  void setPosition(double x, double y) {
    _cancelMovement();
    _position = _clampPosition(Offset(x, y));
    notifyListeners();
  }

  void userDragTo(Offset delta) {
    _cancelMovement();
    _position = _clampPosition(_position + delta);
    notifyListeners();
  }

  void walkTo(double x, double y) {
    _startMove(Offset(x, y), speed: 300);
  }

  void runTo(double x, double y) {
    _startMove(Offset(x, y), speed: 620);
  }

  void cancelMovement() {
    _cancelMovement();
    notifyListeners();
  }

  void performAction(String type, double? x, double? y) {
    final g = parseDesktopAvatarGesture(type);
    if (g == DesktopAvatarGesture.none) return;

    Future<void> run() async {
      if (x != null && y != null) {
        final target = Offset(x, y);
        if ((_position - target).distance > 4) {
          await _moveToAwait(target, speed: 300);
        }
      }
      _showGesture(g);
    }

    unawaited(run());
  }

  void _showGesture(DesktopAvatarGesture g) {
    _gestureClearTimer?.cancel();
    _gesture = g;
    notifyListeners();
    _gestureClearTimer = Timer(
        const Duration(milliseconds: _actionDisplayMs), () {
      _gesture = DesktopAvatarGesture.none;
      _gestureClearTimer = null;
      notifyListeners();
    });
  }

  void _cancelMovement() {
    _moveTimer?.cancel();
    _moveTimer = null;
    _moveTarget = null;
  }

  void _startMove(Offset target, {required double speed}) {
    if (_bounds == Size.zero) {
      _position = target;
      notifyListeners();
      return;
    }
    _moveTarget = _clampPosition(target);
    _moveSpeedPxPerSec = speed;
    _moveTimer?.cancel();
    _moveTimer =
        Timer.periodic(const Duration(milliseconds: 16), _onMoveTick);
    notifyListeners();
  }

  void _onMoveTick(Timer t) {
    final target = _moveTarget;
    if (target == null) {
      t.cancel();
      return;
    }
    final step = _moveSpeedPxPerSec * 0.016;
    final to = target - _position;
    final d = to.distance;
    if (d <= step || d < 0.5) {
      _position = target;
      _cancelMovement();
      notifyListeners();
      return;
    }
    _position = _position + to * (step / d);
    _position = _clampPosition(_position);
    notifyListeners();
  }

  Future<void> _moveToAwait(Offset target, {required double speed}) {
    final completer = Completer<void>();
    if (_bounds == Size.zero) {
      _position = _clampPosition(target);
      notifyListeners();
      completer.complete();
      return completer.future;
    }
    _cancelMovement();
    _moveTarget = _clampPosition(target);
    _moveSpeedPxPerSec = speed;
    _moveTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      final to = _moveTarget;
      if (to == null) {
        t.cancel();
        _moveTimer = null;
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final step = _moveSpeedPxPerSec * 0.016;
      final delta = to - _position;
      final d = delta.distance;
      if (d <= step || d < 0.5) {
        _position = to;
        _cancelMovement();
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      _position = _clampPosition(_position + delta * (step / d));
      notifyListeners();
    });
    return completer.future;
  }

  Offset _clampPosition(Offset o) {
    if (_bounds == Size.zero) return o;
    final maxX = math.max(0.0, _bounds.width - avatarVisualSize);
    final maxY = math.max(0.0, _bounds.height - avatarVisualSize);
    return Offset(
      o.dx.clamp(0.0, maxX),
      o.dy.clamp(0.0, maxY),
    );
  }

  static final _clickAnimations = [
    AgentAvatarActivity.happy,
    AgentAvatarActivity.bored,
    AgentAvatarActivity.watching,
    AgentAvatarActivity.confused,
    AgentAvatarActivity.angry,
  ];

  static const _emotionBubbles = [
    '(=^・ω・^=)',
    '(=^-ω-^=) zzZ',
    '(ↀДↀ)⁼³₌₃',
    '(=^・^=)',
    '₍˄·͈༝·͈˄₎◞ ̑̑',
    '♪(=^∇^=)',
    '(=ↀωↀ=)✧',
    '(=^◡^=)',
    'ฅ(^・ω・^ฅ)',
    '(≧◡≦)',
  ];

  Timer? _clickBubbleTimer;
  bool _showInput = false;
  bool get showInput => _showInput;

  void toggleInput() {
    _showInput = !_showInput;
    notifyListeners();
  }

  void hideInput() {
    if (!_showInput) return;
    _showInput = false;
    notifyListeners();
  }

  void triggerClickReaction() {
    final rng = math.Random();
    final anim = _clickAnimations[rng.nextInt(_clickAnimations.length)];
    final emoji = _emotionBubbles[rng.nextInt(_emotionBubbles.length)];

    showTemporaryState(anim);

    _clickBubbleTimer?.cancel();
    setBubble(text: emoji);
    _clickBubbleTimer = Timer(const Duration(seconds: 3), () {
      clearBubble();
      _clickBubbleTimer = null;
    });
  }

  /// For the floating avatar window (separate engine).
  AvatarSnapshot toSnapshot() {
    return AvatarSnapshot(
      posX: _position.dx,
      posY: _position.dy,
      activity: _activity.name,
      effectiveActivity: effectiveActivity.name,
      bubbleText: _bubbleText,
      bubbleBgArgb: _bubbleBgArgb,
      bubbleTextArgb: _bubbleTextArgb,
      bubbleCountdown: _bubbleCountdown,
      colorArgb: _colorFilter?.toARGB32(),
      gesture: _gesture.name,
      isMoving: isMoving,
      showInput: _showInput,
    );
  }

  @override
  void dispose() {
    _temporaryTimer?.cancel();
    _gestureClearTimer?.cancel();
    _moveTimer?.cancel();
    _clickBubbleTimer?.cancel();
    super.dispose();
  }
}
