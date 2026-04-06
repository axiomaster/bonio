import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models/avatar_snapshot.dart';
import 'services/desktop_avatar_theme.dart';
import 'ui/widgets/desktop_avatar_overlay.dart';

/// Second engine: OS-level floating avatar (main BoJi window can be minimized).
class AvatarFloatingApp extends StatefulWidget {
  final String mainWindowId;

  const AvatarFloatingApp({super.key, required this.mainWindowId});

  @override
  State<AvatarFloatingApp> createState() => _AvatarFloatingAppState();
}

class _AvatarFloatingAppState extends State<AvatarFloatingApp>
    with WindowListener {
  AvatarSnapshot _snapshot = AvatarSnapshot(
    posX: 0,
    posY: 0,
    activity: 'idle',
    effectiveActivity: 'idle',
    gesture: 'none',
    isMoving: false,
  );

  WindowController? _wc;
  DesktopAvatarTheme? _theme;

  // Dock behavior
  bool _dockAtBottom = false;
  double _dockHeight = 0;
  double _screenWidth = 0;
  double _screenHeight = 0;
  double _dockLeft = 0;
  double _dockRight = 0;
  bool _onDock = true;
  bool _programmaticMove = false;
  String? _localActivityOverride;
  bool _facingLeft = false;

  Timer? _wanderTimer;
  Timer? _returnToDockTimer;
  Timer? _moveAnimTimer;

  static const _returnToDockTimeout = Duration(minutes: 5);
  static const _wanderMinSec = 15;
  static const _wanderMaxSec = 45;
  static final _rng = Random();

  final _windowSize = AvatarSnapshot.kFloatingWindowSize;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _registerHandler();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _wanderTimer?.cancel();
    _returnToDockTimer?.cancel();
    _moveAnimTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Dock detection & initial positioning
  // ---------------------------------------------------------------------------

  Future<void> _initDockBehavior() async {
    if (!Platform.isMacOS) return;
    final wc = _wc;
    if (wc == null) return;
    try {
      // Use the native plugin's getDockInfo — it reads from the window's
      // own screen, so coordinates match setPosition exactly.
      final dockInfo = await wc.getDockInfo();
      if (dockInfo == null) return;

      _screenWidth = (dockInfo['screenWidth'] as num?)?.toDouble() ?? 0;
      _screenHeight = (dockInfo['screenHeight'] as num?)?.toDouble() ?? 0;
      _dockAtBottom = dockInfo['dockAtBottom'] as bool? ?? false;
      _dockHeight = (dockInfo['dockHeight'] as num?)?.toDouble() ?? 0;

      // Estimate Dock horizontal span via `defaults read`.
      final dockMetrics = await _readDockMetrics();
      final tileSize = dockMetrics.tileSize;
      final itemCount = dockMetrics.itemCount;
      final dockWidth = itemCount * (tileSize + 4) + 24;
      _dockLeft = ((_screenWidth - dockWidth) / 2).clamp(0.0, _screenWidth);
      _dockRight = ((_screenWidth + dockWidth) / 2).clamp(0.0, _screenWidth);

      debugPrint('AvatarDock: screen=${_screenWidth}x$_screenHeight, '
          'dockAtBottom=$_dockAtBottom, dockHeight=$_dockHeight, '
          'dockX=[$_dockLeft..$_dockRight] (items=$itemCount, tile=$tileSize)');

      if (_dockAtBottom) {
        _onDock = true;
        await _moveToDockPosition(animate: false);
        _scheduleNextWander();
      }
    } catch (e) {
      debugPrint('AvatarDock: init failed: $e');
    }
  }

  static Future<({double tileSize, int itemCount})> _readDockMetrics() async {
    double tileSize = 48;
    int itemCount = 12;

    try {
      final tsResult = await Process.run(
          'defaults', ['read', 'com.apple.dock', 'tilesize']);
      if (tsResult.exitCode == 0) {
        tileSize = double.tryParse(tsResult.stdout.toString().trim()) ?? 48;
      }
    } catch (_) {}

    try {
      final appsResult = await Process.run('defaults',
          ['read', 'com.apple.dock', 'persistent-apps']);
      int apps = 0;
      if (appsResult.exitCode == 0) {
        apps = 'tile-data'
            .allMatches(appsResult.stdout.toString())
            .length;
      }

      final othersResult = await Process.run('defaults',
          ['read', 'com.apple.dock', 'persistent-others']);
      int others = 0;
      if (othersResult.exitCode == 0) {
        others = 'tile-data'
            .allMatches(othersResult.stdout.toString())
            .length;
      }

      if (apps + others > 0) {
        itemCount = apps + others + 3;
      }
    } catch (_) {}

    return (tileSize: tileSize, itemCount: itemCount);
  }

  // ---------------------------------------------------------------------------
  // Dock positioning helpers
  // ---------------------------------------------------------------------------

  /// Flutter y for the avatar visually sitting ON the Dock bar.
  /// [inset] is the per-animation bottom transparent padding from theme.json.
  double _dockTopYFor(double inset) =>
      _screenHeight - _dockHeight - _windowSize.height +
      AvatarSnapshot.kFloatingWindowPadding + inset;

  /// Shortcut: dock Y for the currently displayed animation.
  double get _dockTopY => _dockTopYFor(_currentBottomInset);

  double get _currentBottomInset =>
      _theme?.bottomInsetFor(_displaySnapshot) ?? 10;

  Future<void> _moveToDockPosition({bool animate = true}) async {
    final wc = _wc;
    if (wc == null) return;

    final minX = _dockLeft.clamp(0.0, double.infinity);
    final maxX = (_dockRight - _windowSize.width).clamp(minX, double.infinity);
    final targetX = minX + _rng.nextDouble() * (maxX - minX);
    final target = Offset(targetX, _dockTopY);

    if (animate) {
      await _animateWindowTo(target);
    } else {
      _programmaticMove = true;
      await wc.setPosition(target);
      _programmaticMove = false;
    }
  }

  Future<void> _animateWindowTo(Offset target) async {
    final wc = _wc;
    if (wc == null) return;

    _moveAnimTimer?.cancel();
    _programmaticMove = true;

    final startPos = await wc.getPosition();
    final movingLeft = target.dx < startPos.dx;
    if (mounted) {
      setState(() {
        _localActivityOverride = 'walking';
        _facingLeft = movingLeft;
      });
    }

    final distance = (target - startPos).distance;
    if (distance < 4) {
      _programmaticMove = false;
      if (mounted) setState(() { _localActivityOverride = null; _facingLeft = false; });
      return;
    }

    final durationMs = (distance / 0.25).clamp(400.0, 4000.0).toInt();
    final steps = (durationMs / 16).round().clamp(1, 250);
    final completer = Completer<void>();
    var step = 0;

    _moveAnimTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      step++;
      final p = (step / steps).clamp(0.0, 1.0);
      final ease = p < 0.5
          ? 2 * p * p
          : 1 - (-2 * p + 2) * (-2 * p + 2) / 2;

      final pos = Offset(
        startPos.dx + (target.dx - startPos.dx) * ease,
        startPos.dy + (target.dy - startPos.dy) * ease,
      );
      wc.setPosition(pos);

      if (step >= steps) {
        t.cancel();
        _moveAnimTimer = null;
        _programmaticMove = false;
        if (mounted) setState(() { _localActivityOverride = null; _facingLeft = false; });
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Idle wandering along the Dock
  // ---------------------------------------------------------------------------

  void _scheduleNextWander() {
    _wanderTimer?.cancel();
    if (!_onDock || !_dockAtBottom) return;

    final delaySec =
        _wanderMinSec + _rng.nextInt(_wanderMaxSec - _wanderMinSec);
    _wanderTimer = Timer(Duration(seconds: delaySec), _wander);
  }

  Future<void> _wander() async {
    if (!_onDock || !_dockAtBottom || !mounted) return;
    await _moveToDockPosition(animate: true);
    _scheduleNextWander();
  }

  // ---------------------------------------------------------------------------
  // User drag detection (WindowListener from window_manager)
  // ---------------------------------------------------------------------------

  @override
  void onWindowMoved() {
    if (_programmaticMove) return;
    if (_onDock) {
      debugPrint('AvatarDock: user dragged off dock');
      _onDock = false;
      _wanderTimer?.cancel();
    }
    _resetReturnToDockTimer();
  }

  void _resetReturnToDockTimer() {
    _returnToDockTimer?.cancel();
    if (!_dockAtBottom) return;
    _returnToDockTimer = Timer(_returnToDockTimeout, _returnToDock);
  }

  Future<void> _returnToDock() async {
    if (!_dockAtBottom || !mounted) return;
    debugPrint('AvatarDock: returning to dock after timeout');
    _onDock = true;
    await _moveToDockPosition(animate: true);
    _scheduleNextWander();
  }

  // ---------------------------------------------------------------------------
  // Method handler (sync from main engine)
  // ---------------------------------------------------------------------------

  Future<void> _registerHandler() async {
    final wc = await WindowController.fromCurrentEngine();
    _wc = wc;
    _theme = await DesktopAvatarTheme.load();
    await wc.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'sync':
          final raw = call.arguments;
          if (raw is Map) {
            final m = Map<String, dynamic>.from(raw);
            if (!mounted) return null;
            final prev = _snapshot;
            setState(() => _snapshot = AvatarSnapshot.fromJson(m));
            _adjustDockYIfNeeded(prev);
          }
          return null;
        case 'window_close':
          _wanderTimer?.cancel();
          _returnToDockTimer?.cancel();
          _moveAnimTimer?.cancel();
          await windowManager.close();
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
    // Now that we have the window controller, init dock behavior.
    unawaited(_initDockBehavior());
  }

  /// When the animation changes while on the dock, adjust Y so the cat stays
  /// visually on the Dock bar (different animations have different bottom insets).
  void _adjustDockYIfNeeded(AvatarSnapshot prev) {
    if (!_onDock || !_dockAtBottom || _programmaticMove) return;
    final theme = _theme;
    if (theme == null) return;

    final oldInset = theme.bottomInsetFor(prev);
    final newInset = _currentBottomInset;
    if ((oldInset - newInset).abs() < 1) return;

    final wc = _wc;
    if (wc == null) return;

    // Set flag synchronously to prevent onWindowMoved from falsely
    // detecting the position change as a user drag.
    _programmaticMove = true;
    wc.getPosition().then((pos) async {
      if (!mounted || !_onDock) return;
      final newY = _dockTopYFor(newInset);
      await wc.setPosition(Offset(pos.dx, newY));
    }).whenComplete(() {
      _programmaticMove = false;
    });
  }

  Future<void> _sendVoiceTapToMain() async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarVoiceTap');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  AvatarSnapshot get _displaySnapshot {
    if (_localActivityOverride == null) return _snapshot;
    return AvatarSnapshot(
      posX: _snapshot.posX,
      posY: _snapshot.posY,
      activity: _snapshot.activity,
      effectiveActivity: _localActivityOverride!,
      bubbleText: _snapshot.bubbleText,
      bubbleBgArgb: _snapshot.bubbleBgArgb,
      bubbleTextArgb: _snapshot.bubbleTextArgb,
      bubbleCountdown: _snapshot.bubbleCountdown,
      colorArgb: _snapshot.colorArgb,
      gesture: _snapshot.gesture,
      isMoving: _snapshot.isMoving,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
      ),
      home: SizedBox.expand(
        child: DesktopAvatarView(
          snapshot: _displaySnapshot,
          onAvatarTap: _sendVoiceTapToMain,
          isFloatingWindow: true,
          facingLeft: _facingLeft,
        ),
      ),
    );
  }
}

/// Called from [main] before [runApp] for the avatar engine only.
Future<void> initAvatarWindowEngine() async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(null, () async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.setTitle('BoJi Avatar');
  });
}
