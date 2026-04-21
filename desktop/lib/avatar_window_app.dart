import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_strings.dart';
import 'models/avatar_snapshot.dart';
import 'models/chat_models.dart';
import 'platform/macos_screen_capture.dart';
import 'platform/screen_capture.dart';
import 'platform/win32_screen_capture.dart';
import 'services/desktop_avatar_theme.dart';
import 'ui/widgets/desktop_avatar_overlay.dart';

enum _PlacementState { anchoredWindow, fullscreenCorner, userOffset, onDock }

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

  // Screen / dock geometry (for ON_DOCK fallback)
  bool _dockAtBottom = false;
  double _dockHeight = 0;
  double _screenWidth = 0;
  double _screenHeight = 0;
  double _dockLeft = 0;
  double _dockRight = 0;

  // Placement state machine
  _PlacementState _placement = _PlacementState.onDock;
  int _anchoredHwnd = 0;

  // User-drag offset: relative X from window top-center (0 = centered)
  double _userOffsetX = 0;

  bool _programmaticMove = false;
  String? _localActivityOverride;
  bool _facingLeft = false;

  Timer? _wanderTimer;
  Timer? _moveAnimTimer;
  Completer<void>? _moveAnimCompleter;
  Timer? _fgPollTimer;
  Timer? _anchorTrackTimer;
  Timer? _springTimer;

  int _readingCompanionHwnd = 0;

  // Elastic spring tracking
  double _targetX = 0;
  double _targetY = 0;
  double _currentX = 0;
  double _currentY = 0;
  bool _springActive = false;

  // Last known anchored window rect — skip setPosition when unchanged
  double _lastAnchoredLeft = 0;
  double _lastAnchoredTop = 0;
  double _lastAnchoredWidth = 0;

  // BoJi Lens (圈一圈) annotation state
  bool _lensActive = false;
  bool _searchSimilarMode = false; // true when lens is used for 搜同款
  ScreenCaptureResult? _lensCapture;
  List<Rect> _lensRects = [];
  Rect? _lensDrawingRect; // rect currently being drawn
  String _lensWindowTitle = '';
  // Saved avatar position before lens expansion
  double _lensPreX = 0;
  double _lensPreY = 0;
  Size _lensPreSize = Size.zero;

  static const _fgPollInterval = Duration(seconds: 3);
  static const _anchorTrackInterval = Duration(milliseconds: 50);
  static const _springInterval = Duration(milliseconds: 16);
  static const _springFactor = 0.12; // lerp factor per 16ms frame (~200ms settle)
  static const _springThreshold = 0.5; // stop when within 0.5px

  static const _idleMinSec = 10;
  static const _idleMaxSec = 30;
  static const _walkSpeed = 0.04; // px per ms
  static final _rng = Random();

  /// DPI scale of the avatar window (physical pixels per logical pixel).
  double get _avatarDpiScale {
    if (Platform.isMacOS) {
      // On macOS, CGWindowListCopyWindowInfo returns bounds in logical points.
      // _toPhysical should be a no-op so we work entirely in points.
      return 1.0;
    }
    if (_avatarSelfHwnd != 0) {
      return _getWinDpiScaleForWindow(_avatarSelfHwnd);
    }
    return _getWinDpiScaleSystem();
  }

  /// Convert a logical-pixel value to physical using the avatar's DPI.
  double _toPhysical(double logical) => logical * _avatarDpiScale;

  Size get _windowSize => _snapshot.showInput
      ? AvatarSnapshot.kFloatingWindowSizeWithInput
      : AvatarSnapshot.kFloatingWindowSize;

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
    _moveAnimTimer?.cancel();
    _fgPollTimer?.cancel();
    _anchorTrackTimer?.cancel();
    _springTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> _initPlacement() async {
    final wc = _wc;
    if (wc == null) return;
    try {
      // Always init dock/screen geometry for fallback
      if (Platform.isMacOS) {
        await _initDockMacOS(wc);
      } else if (Platform.isWindows) {
        await _initTaskbarWindows(wc);
      }

      // Find our own HWND so we can distinguish the avatar window from
      // other windows in the same process (e.g. the main BoJi window).
      if (Platform.isWindows) {
        _avatarSelfHwnd = _findWindowByTitle(S.current.avatarWindowTitle);
        if (_avatarSelfHwnd == 0) {
          // Fallback: use GetActiveWindow which should be the avatar at this point
          _avatarSelfHwnd = _getActiveWindow();
        }
        debugPrint('AvatarPlacement: selfHwnd=$_avatarSelfHwnd');
      }

      debugPrint('AvatarPlacement: screen=${_screenWidth}x$_screenHeight, '
          'dockAtBottom=$_dockAtBottom, dockHeight=$_dockHeight');

      // Try to anchor to the current foreground window immediately
      if (Platform.isWindows) {
        final fgInfo = _getWinForegroundInfo();
        final isAvatar = fgInfo != null &&
            (fgInfo.hwnd == _avatarSelfHwnd || _isLikelyAvatarWindow(fgInfo));
        final isDesktop = fgInfo?.isDesktop ?? false;
        if (fgInfo != null && !isAvatar && !isDesktop && !fgInfo.isFullscreen &&
            fgInfo.hwnd != 0 && fgInfo.width > 50 && fgInfo.height > 50) {
          _anchorToWindow(fgInfo.hwnd, fgInfo);
        } else if (fgInfo != null && !isAvatar && !isDesktop && fgInfo.isFullscreen) {
          _transitionToFullscreenCorner();
        } else {
          _transitionToDock();
        }
      } else if (Platform.isMacOS) {
        final fgWindow = _getMacForegroundWindow();
        if (fgWindow != null && fgWindow.bounds != null &&
            fgWindow.bounds!['Width']! > 50 && fgWindow.bounds!['Height']! > 50) {
          _transitionToAnchoredWindowMacOS(fgWindow);
        } else {
          _transitionToDock();
        }
      } else {
        _transitionToDock();
      }

      _startForegroundPolling();
    } catch (e) {
      debugPrint('AvatarPlacement: init failed: $e');
    }
  }

  Future<void> _initDockMacOS(WindowController wc) async {
    final dockInfo = await wc.getDockInfo();
    if (dockInfo == null) return;

    _screenWidth = (dockInfo['screenWidth'] as num?)?.toDouble() ?? 0;
    _screenHeight = (dockInfo['screenHeight'] as num?)?.toDouble() ?? 0;
    _dockAtBottom = dockInfo['dockAtBottom'] as bool? ?? false;
    _dockHeight = (dockInfo['dockHeight'] as num?)?.toDouble() ?? 0;

    final dockMetrics = await _readDockMetrics();
    final tileSize = dockMetrics.tileSize;
    final itemCount = dockMetrics.itemCount;
    final dockWidth = itemCount * (tileSize + 4) + 24;
    _dockLeft = ((_screenWidth - dockWidth) / 2).clamp(0.0, _screenWidth);
    _dockRight = ((_screenWidth + dockWidth) / 2).clamp(0.0, _screenWidth);
  }

  Future<void> _initTaskbarWindows(WindowController wc) async {
    final info = _getWindowsTaskbarInfo();
    if (info == null) return;

    _screenWidth = info.screenWidth;
    _screenHeight = info.screenHeight;
    _dockAtBottom = info.atBottom;
    _dockHeight = info.taskbarHeight;
    _dockLeft = info.taskbarLeft;
    _dockRight = info.taskbarRight;
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
  // Dock positioning helpers (ON_DOCK fallback)
  // ---------------------------------------------------------------------------

  /// Always use the base (non-input) window height for anchor calculations.
  /// The input area extends the window downward; the anchor Y never changes.
  static final double _anchorHeight = AvatarSnapshot.kFloatingWindowSize.height;

  double _dockTopYFor(double inset) =>
      _screenHeight - _dockHeight - _toPhysical(_anchorHeight) +
      _toPhysical(AvatarSnapshot.kFloatingWindowPadding) + _toPhysical(inset);

  double get _dockTopY => _dockTopYFor(_currentBottomInset);

  double get _currentBottomInset =>
      _theme?.bottomInsetFor(_displaySnapshot) ?? 10;

  Future<void> _moveToDockPosition({bool animate = true}) async {
    final wc = _wc;
    if (wc == null) return;

    final minX = _dockLeft.clamp(0.0, double.infinity);
    final maxX = (_dockRight - _toPhysical(_windowSize.width)).clamp(minX, double.infinity);
    final targetX = minX + _rng.nextDouble() * (maxX - minX);
    final target = Offset(targetX, _dockTopY);

    if (animate) {
      await _animateWindowTo(target);
    } else {
      _programmaticMove = true;
      await wc.setPositionPhysical(target.dx, target.dy);
      _currentX = target.dx;
      _currentY = target.dy;
      _programmaticMove = false;
    }
  }

  /// Lift the avatar a few pixels above the window edge so that lying-down
  /// animations (sleeping, bored) don't overlap the visible title bar.
  /// On Windows 10/11 GetWindowRect includes the invisible shadow frame
  /// (~7px above the visible edge), so a 5px lift keeps the avatar clearly
  /// above the visible title bar content.
  static const _titleBarClearance = 5.0;

  /// Window top-center Y for a given window rect.
  /// Uses constant base height (not the dynamic _windowSize) so that the
  /// anchor position is independent of whether the input field is visible.
  /// On macOS, sits on the title bar instead of above it (menu bar blocks
  /// placement above the window).
  double _windowTopY(_WindowRectInfo info) {
    final inset = _currentBottomInset;
    if (Platform.isMacOS) {
      // macOS: sit on the title bar, overlapping slightly.
      // The avatar bottom sits near the window top edge.
      return info.top +
          _toPhysical(AvatarSnapshot.kFloatingWindowPadding + inset);
    }
    return info.top - _toPhysical(_anchorHeight) +
        _toPhysical(AvatarSnapshot.kFloatingWindowPadding + inset) - _toPhysical(_titleBarClearance);
  }

  /// Window top-center X for a given window rect (centered).
  double _windowCenterX(_WindowRectInfo info) {
    return info.left + (info.width - _toPhysical(_windowSize.width)) / 2;
  }

  // ---------------------------------------------------------------------------
  // Movement animation
  // ---------------------------------------------------------------------------

  Future<void> _animateWindowTo(Offset target, {bool stroll = false}) async {
    final wc = _wc;
    if (wc == null) return;

    _moveAnimTimer?.cancel();
    _programmaticMove = true;

    final startPos = Platform.isWindows
        ? await wc.getPositionPhysical()
        : await wc.getPosition();
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

    final speed = stroll ? _walkSpeed : _walkSpeed * 3;
    final durationMs = (distance / speed).clamp(300.0, 20000.0).toInt();
    final steps = (durationMs / 16).round().clamp(1, 1250);
    final completer = Completer<void>();
    _moveAnimCompleter = completer;
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
      if (Platform.isWindows) {
        wc.setPositionPhysical(pos.dx, pos.dy);
      } else {
        wc.setPosition(pos);
      }

      if (step >= steps) {
        t.cancel();
        _moveAnimTimer = null;
        _moveAnimCompleter = null;
        _programmaticMove = false;
        _currentX = target.dx;
        _currentY = target.dy;
        if (mounted) setState(() { _localActivityOverride = null; _facingLeft = false; });
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Walk cancellation — single entry point for stopping any walk/wander
  // ---------------------------------------------------------------------------

  /// Immediately stops any in-progress walk animation and wander timer,
  /// resets the walking visual state (activity override + facing direction).
  /// Must be called from every user-interaction entry point and every
  /// placement transition that should NOT show the cat walking.
  void _cancelWalk() {
    _wanderTimer?.cancel();
    _wanderTimer = null;
    if (_moveAnimTimer != null) {
      _moveAnimTimer?.cancel();
      _moveAnimTimer = null;
      _programmaticMove = false;
      if (_moveAnimCompleter != null && !_moveAnimCompleter!.isCompleted) {
        _moveAnimCompleter!.complete();
      }
      _moveAnimCompleter = null;
    }
    if (_localActivityOverride != null || _facingLeft) {
      if (mounted) {
        setState(() {
          _localActivityOverride = null;
          _facingLeft = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Idle wandering
  // ---------------------------------------------------------------------------

  bool get _interactionActive => _menuVisible || _snapshot.showInput || _lensActive;

  void _scheduleNextWander() {
    _wanderTimer?.cancel();
    if (_interactionActive) return;
    if (_placement == _PlacementState.userOffset ||
        _placement == _PlacementState.fullscreenCorner) return;

    final delaySec =
        _idleMinSec + _rng.nextInt(_idleMaxSec - _idleMinSec);
    _wanderTimer = Timer(Duration(seconds: delaySec), _wander);
  }

  Future<void> _wander() async {
    if (!mounted || _interactionActive) return;
    if (_placement == _PlacementState.userOffset ||
        _placement == _PlacementState.fullscreenCorner) return;

    final legs = 2 + _rng.nextInt(3);
    for (var i = 0; i < legs; i++) {
      if (!mounted || _interactionActive ||
          _placement == _PlacementState.userOffset ||
          _placement == _PlacementState.fullscreenCorner) break;

      final target = _pickStrollTarget();
      if (target == null) break;
      await _animateWindowTo(target, stroll: true);

      if (i < legs - 1 && mounted) {
        final pauseMs = 500 + _rng.nextInt(1500);
        await Future.delayed(Duration(milliseconds: pauseMs));
      }
    }

    _scheduleNextWander();
  }

  Offset? _pickStrollTarget() {
    if (_placement == _PlacementState.onDock) {
      return _pickDockTarget();
    } else if (_placement == _PlacementState.anchoredWindow && _anchoredHwnd != 0) {
      final info = _getWindowRect(_anchoredHwnd);
      if (info != null) return _pickWindowTarget(info);
    }
    return null;
  }

  Offset? _pickDockTarget() {
    final minX = _dockLeft.clamp(0.0, double.infinity);
    final maxX = (_dockRight - _toPhysical(_windowSize.width)).clamp(minX, double.infinity);
    final targetX = minX + _rng.nextDouble() * (maxX - minX);
    return Offset(targetX, _dockTopY);
  }

  Offset? _pickWindowTarget(_WindowRectInfo info) {
    final avatarW = _toPhysical(_windowSize.width);
    final minX = info.left;
    final maxX = (info.left + info.width - avatarW).clamp(minX, double.infinity);
    final targetX = minX + _rng.nextDouble() * (maxX - minX);
    final targetY = _windowTopY(info);
    return Offset(targetX, targetY);
  }

  // ---------------------------------------------------------------------------
  // User drag detection
  // ---------------------------------------------------------------------------

  @override
  void onWindowMoved() {
    if (_programmaticMove) return;

    _cancelWalk();

    if (_placement == _PlacementState.anchoredWindow && _anchoredHwnd != 0) {
      final info = _getWindowRect(_anchoredHwnd);
      if (info != null) {
        final centerX = _windowCenterX(info);
        _wc?.getPositionPhysical().then((pos) {
          _userOffsetX = pos.dx - centerX;
          debugPrint('AvatarDrag: user offset from center = $_userOffsetX');
        });
      }
      _placement = _PlacementState.userOffset;
      _stopAnchorTracking();
      debugPrint('AvatarDrag: entered USER_OFFSET');
    } else if (_placement == _PlacementState.onDock) {
      _placement = _PlacementState.userOffset;
      debugPrint('AvatarDrag: dragged off dock');
    } else if (_placement == _PlacementState.fullscreenCorner) {
      _placement = _PlacementState.userOffset;
      debugPrint('AvatarDrag: dragged off fullscreen corner');
    }
  }

  // ---------------------------------------------------------------------------
  // Foreground polling & state transitions
  // ---------------------------------------------------------------------------

  void _startForegroundPolling() {
    _fgPollTimer?.cancel();
    if (!Platform.isWindows && !Platform.isMacOS) return;
    _fgPollTimer = Timer.periodic(_fgPollInterval, (_) => _pollForeground());
  }

  void _pollForeground() {
    if (!mounted) return;
    if (!Platform.isWindows && !Platform.isMacOS) return;
    if (_interactionActive) return;

    if (Platform.isMacOS) {
      _pollForegroundMacOS();
      return;
    }

    // --- Health check for anchored window ---
    if ((_placement == _PlacementState.anchoredWindow ||
         _placement == _PlacementState.userOffset) && _anchoredHwnd != 0) {
      if (!_isWindowValid(_anchoredHwnd) || _isWindowMinimized(_anchoredHwnd)) {
        debugPrint('AvatarAnchor: anchored window lost');
        _anchoredHwnd = 0;
        _handleAnchoredWindowLost();
        return;
      }
      final rect = _getWindowRect(_anchoredHwnd);
      if (rect != null && rect.isFullscreen) {
        debugPrint('AvatarAnchor: anchored window went fullscreen');
        _transitionToFullscreenCorner();
        return;
      }
    }

    // --- Foreground window tracking ---
    final fgInfo = _getWinForegroundInfo();
    if (fgInfo == null || fgInfo.hwnd == 0) return;

    // Skip the avatar window itself (but NOT the main BoJi window)
    if (fgInfo.hwnd == _avatarSelfHwnd) return;

    // Skip the reading companion window — avatar stays on the browser
    if (fgInfo.hwnd == _readingCompanionHwnd) return;

    // Safety net: if selfHwnd wasn't resolved, check by remembering the HWND now
    if (_avatarSelfHwnd == 0 && fgInfo.isSelf) {
      final avatarW = _toPhysical(_windowSize.width);
      final avatarH = _toPhysical(_windowSize.height);
      if ((fgInfo.width - avatarW).abs() < 2 &&
          (fgInfo.height - avatarH).abs() < 2) {
        _avatarSelfHwnd = fgInfo.hwnd;
        debugPrint('AvatarPlacement: resolved selfHwnd=${fgInfo.hwnd} by size match');
        return;
      }
    }

    // Desktop shell windows (Progman, WorkerW) = "no app window"
    if (fgInfo.isDesktop) {
      if (_placement == _PlacementState.anchoredWindow ||
          _placement == _PlacementState.userOffset) {
        // Keep anchored — user just clicked on desktop but our window is still there
        if (_anchoredHwnd != 0 && _isWindowValid(_anchoredHwnd) &&
            !_isWindowMinimized(_anchoredHwnd)) {
          return;
        }
        _handleAnchoredWindowLost();
      }
      return;
    }

    final fgHwnd = fgInfo.hwnd;

    if (fgInfo.isFullscreen) {
      if (_placement != _PlacementState.fullscreenCorner) {
        _transitionToFullscreenCorner();
      }
      return;
    }

    // Ignore tiny windows (e.g., tooltips)
    if (fgInfo.width < 100 || fgInfo.height < 100) return;

    // Ignore system popups, flyouts, and transient panels
    if (_isSystemPopup(fgHwnd)) return;

    // Already anchored to this window
    if (_placement == _PlacementState.anchoredWindow && fgHwnd == _anchoredHwnd) return;

    // USER_OFFSET on same window — window geometry change will reset
    if (_placement == _PlacementState.userOffset && fgHwnd == _anchoredHwnd) return;

    // New foreground window — switch immediately
    _anchorToWindow(fgHwnd, fgInfo);
  }

  // ---------------------------------------------------------------------------
  // macOS foreground window tracking
  // ---------------------------------------------------------------------------

  /// Find the frontmost usable window on macOS via CGWindowListCopyWindowInfo.
  /// Returns null if no suitable window is found.
  WindowInfo? _getMacForegroundWindow() {
    final windows = MacosScreenCapture.getWindowList();
    if (windows == null || windows.isEmpty) return null;

    for (final w in windows) {
      // Skip our own app's windows
      if (w.ownerName == 'boji_desktop') continue;
      // Skip system/daemon windows (both English and localized names)
      final owner = w.ownerName.toLowerCase();
      if (owner.contains('window server') || owner.contains('systemuiserver') ||
          owner.contains('dock') || owner.contains('程序坞') ||
          owner.contains('controlcenter') || owner.contains('控制中心') ||
          owner.contains('notification center') || owner.contains('通知中心') ||
          owner.contains('loginwindow')) continue;
      debugPrint('AvatarFG macOS: candidate owner=${w.ownerName} '
          'name=${w.windowName} id=${w.windowID} bounds=${w.bounds}');
      // Skip windows without names
      if (w.windowName == null || w.windowName!.isEmpty) continue;
      // Skip tiny windows
      if (w.bounds != null && (w.bounds!['Width']! < 100 || w.bounds!['Height']! < 100)) continue;
      debugPrint('AvatarFG macOS: PICKED owner=${w.ownerName} '
          'name=${w.windowName} id=${w.windowID} bounds=${w.bounds}');
      return w;
    }
    debugPrint('AvatarFG macOS: no suitable window found (total=${windows.length})');
    return null;
  }

  /// Check if a macOS window bounds represent a fullscreen window.
  /// On macOS, floating-level windows appear above fullscreen apps, so
  /// fullscreen detection is not needed. Always returns false.
  bool _isMacWindowFullscreen(Map<String, int> bounds) {
    return false;
  }

  void _pollForegroundMacOS() {
    final w = _getMacForegroundWindow();
    if (w == null) return;

    final fgWindowId = w.windowID;
    debugPrint('AvatarPoll macOS: fg=$fgWindowId '
        '${w.ownerName}/${w.windowName} placement=$_placement anchored=$_anchoredHwnd');

    // --- Health check for anchored window ---
    if ((_placement == _PlacementState.anchoredWindow ||
         _placement == _PlacementState.userOffset) && _anchoredHwnd != 0) {
      final anchored = _getMacWindowRect(_anchoredHwnd);
      if (anchored == null) {
        debugPrint('AvatarAnchor macOS: anchored window lost');
        _anchoredHwnd = 0;
        _handleAnchoredWindowLostMacOS();
        return;
      }
    }

    // Already anchored to this window
    if (_placement == _PlacementState.anchoredWindow && fgWindowId == _anchoredHwnd) return;

    // USER_OFFSET on same window
    if (_placement == _PlacementState.userOffset && fgWindowId == _anchoredHwnd) return;

    // New foreground window — anchor to it
    if (w.bounds == null || w.bounds!['Width']! < 100 || w.bounds!['Height']! < 100) return;
    _transitionToAnchoredWindowMacOS(w);
  }

  void _handleAnchoredWindowLostMacOS() {
    _stopAnchorTracking();
    _stopSpring();
    final w = _getMacForegroundWindow();
    if (w != null && w.bounds != null &&
        w.bounds!['Width']! >= 100 && w.bounds!['Height']! >= 100) {
      _transitionToAnchoredWindowMacOS(w);
    } else {
      _transitionToDock();
    }
  }

  void _transitionToAnchoredWindowMacOS(WindowInfo w) {
    if (w.bounds == null) {
      _transitionToDock();
      return;
    }
    final b = w.bounds!;
    final centerX = b['X']! + b['Width']! / 2 - _windowSize.width / 2;
    // macOS: sit on the title bar instead of above it (menu bar blocks).
    final topY = b['Y']!.toDouble() +
        AvatarSnapshot.kFloatingWindowPadding + _currentBottomInset;

    debugPrint('AvatarAnchor macOS: anchoring to windowID=${w.windowID} '
        'owner=${w.ownerName} (${b['X']},${b['Y']}) ${b['Width']}x${b['Height']}');

    _cancelWalk();
    _stopAnchorTracking();
    _stopSpring();
    _placement = _PlacementState.anchoredWindow;
    _anchoredHwnd = w.windowID;
    _userOffsetX = 0;

    _lastAnchoredLeft = b['X']!.toDouble();
    _lastAnchoredTop = b['Y']!.toDouble();
    _lastAnchoredWidth = b['Width']!.toDouble();

    _programmaticMove = true;
    final targetX = centerX;
    final targetY = topY;
    _wc?.setPosition(Offset(targetX, targetY)).then((_) {
      _currentX = targetX;
      _currentY = targetY;
      _targetX = targetX;
      _targetY = targetY;
      _programmaticMove = false;
    });
    _scheduleNextWander();
    _startAnchorTracking();
  }

  void _handleAnchoredWindowLost() {
    _stopAnchorTracking();
    _stopSpring();
    final fgInfo = _getWinForegroundInfo();
    if (fgInfo != null && fgInfo.hwnd != _avatarSelfHwnd &&
        !_isLikelyAvatarWindow(fgInfo) && !fgInfo.isDesktop &&
        !fgInfo.isFullscreen && fgInfo.hwnd != 0 &&
        fgInfo.width >= 100 && fgInfo.height >= 100 &&
        !_isSystemPopup(fgInfo.hwnd) &&
        _isWindowValid(fgInfo.hwnd) && !_isWindowMinimized(fgInfo.hwnd)) {
      _anchorToWindow(fgInfo.hwnd, fgInfo);
    } else {
      _transitionToDock();
    }
  }

  bool _isLikelyAvatarWindow(_ForegroundWindowInfo info) {
    if (info.hwnd == _avatarSelfHwnd && _avatarSelfHwnd != 0) return true;
    if (!info.isSelf) return false;
    final aw = _toPhysical(_windowSize.width);
    final ah = _toPhysical(_windowSize.height);
    return (info.width - aw).abs() < 2 && (info.height - ah).abs() < 2;
  }

  void _transitionToDock() {
    debugPrint('AvatarPlacement: -> ON_DOCK');
    _cancelWalk();
    _placement = _PlacementState.onDock;
    _anchoredHwnd = 0;
    _userOffsetX = 0;
    _stopAnchorTracking();
    _stopSpring();
    if (_dockAtBottom) {
      _moveToDockPosition(animate: false);
    }
    _scheduleNextWander();
  }

  void _transitionToFullscreenCorner() {
    debugPrint('AvatarPlacement: -> FULLSCREEN_CORNER');
    _cancelWalk();
    _placement = _PlacementState.fullscreenCorner;
    _stopAnchorTracking();
    _stopSpring();

    final wc = _wc;
    if (wc == null) return;
    final x = _screenWidth - _toPhysical(_windowSize.width) - 20;
    final y = _toPhysical(8.0);
    _programmaticMove = true;
    wc.setPositionPhysical(x, y).then((_) {
      _currentX = x;
      _currentY = y;
      _programmaticMove = false;
    });
  }

  void _anchorToWindow(int hwnd, _ForegroundWindowInfo info) {
    final wc = _wc;
    if (wc == null) return;

    debugPrint('AvatarAnchor: anchoring to hwnd=$hwnd '
        '(${info.left},${info.top}) ${info.width}x${info.height}');

    _cancelWalk();
    _stopAnchorTracking();
    _stopSpring();
    _placement = _PlacementState.anchoredWindow;
    _anchoredHwnd = hwnd;
    _userOffsetX = 0;

    _lastAnchoredLeft = info.left;
    _lastAnchoredTop = info.top;
    _lastAnchoredWidth = info.width;

    final rectInfo = _WindowRectInfo(
      left: info.left, top: info.top,
      width: info.width, height: info.height,
      isFullscreen: info.isFullscreen,
    );
    final x = _windowCenterX(rectInfo);
    final y = _windowTopY(rectInfo);

    _programmaticMove = true;
    wc.setPositionPhysical(x, y).then((_) {
      _currentX = x;
      _currentY = y;
      _targetX = x;
      _targetY = y;
      _programmaticMove = false;
    });
    _scheduleNextWander();
    _startAnchorTracking();
  }

  // ---------------------------------------------------------------------------
  // Fast anchor tracking (50ms) + elastic spring (16ms)
  // ---------------------------------------------------------------------------

  void _startAnchorTracking() {
    _anchorTrackTimer?.cancel();
    if (!Platform.isWindows && !Platform.isMacOS) return;
    _anchorTrackTimer = Timer.periodic(
        _anchorTrackInterval, (_) => _trackAnchoredWindow());
  }

  void _stopAnchorTracking() {
    _anchorTrackTimer?.cancel();
    _anchorTrackTimer = null;
  }

  void _trackAnchoredWindow() {
    if (!mounted || _anchoredHwnd == 0) {
      _stopAnchorTracking();
      return;
    }
    if (_interactionActive) return;
    if (_placement != _PlacementState.anchoredWindow &&
        _placement != _PlacementState.userOffset) {
      _stopAnchorTracking();
      return;
    }

    final info = _getWindowRect(_anchoredHwnd);
    if (info == null) return;

    final moved = (info.left - _lastAnchoredLeft).abs() > 0.5 ||
        (info.top - _lastAnchoredTop).abs() > 0.5;
    final resized = (info.width - _lastAnchoredWidth).abs() > 0.5;

    if (!moved && !resized) return;

    _lastAnchoredLeft = info.left;
    _lastAnchoredTop = info.top;
    _lastAnchoredWidth = info.width;

    _cancelWalk();

    // If USER_OFFSET and window geometry changed, reset to center
    if (_placement == _PlacementState.userOffset && (moved || resized)) {
      debugPrint('AvatarAnchor: window moved/resized, resetting to center');
      _placement = _PlacementState.anchoredWindow;
      _userOffsetX = 0;
    }

    // Compute target position
    final y = _windowTopY(info);
    double x;
    if (_placement == _PlacementState.userOffset) {
      x = _windowCenterX(info) + _userOffsetX;
      final avatarW = _toPhysical(_windowSize.width);
      x = x.clamp(info.left, info.left + info.width - avatarW);
    } else {
      x = _windowCenterX(info);
    }

    _targetX = x;
    _targetY = y;
    _startSpring();
  }

  void _startSpring() {
    if (_springActive) return;
    _springActive = true;
    _springTimer?.cancel();
    _springTimer = Timer.periodic(_springInterval, (_) => _stepSpring());
  }

  void _stopSpring() {
    _springActive = false;
    _springTimer?.cancel();
    _springTimer = null;
  }

  void _stepSpring() {
    if (!mounted || !_springActive) {
      _stopSpring();
      return;
    }

    final dx = _targetX - _currentX;
    final dy = _targetY - _currentY;

    if (dx.abs() < _springThreshold && dy.abs() < _springThreshold) {
      _currentX = _targetX;
      _currentY = _targetY;
      _stopSpring();
      final wc = _wc;
      if (wc != null) {
        _programmaticMove = true;
        wc.setPositionPhysical(_currentX, _currentY).then((_) {
          _programmaticMove = false;
        });
      }
      return;
    }

    _currentX += dx * _springFactor;
    _currentY += dy * _springFactor;

    final wc = _wc;
    if (wc != null) {
      _programmaticMove = true;
      wc.setPositionPhysical(_currentX, _currentY).then((_) {
        _programmaticMove = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Method handler (sync from main engine)
  // ---------------------------------------------------------------------------

  Future<void> _registerHandler() async {
    final wc = await WindowController.fromCurrentEngine();
    _wc = wc;
    _theme = await DesktopAvatarTheme.load();

    // Listen for native OLE drag-and-drop events on the dedicated channel
    // created on this engine's messenger by the C++ side.
    const dropChannel = MethodChannel('boji/avatar_drop');
    dropChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'avatarDragEnter':
          if (mounted) {
            _cancelWalk();
            setState(() => _localActivityOverride = 'openmouth');
          }
          return null;
        case 'avatarDragLeave':
          if (mounted) {
            setState(() => _localActivityOverride = null);
            _scheduleNextWander();
          }
          return null;
        case 'avatarDrop':
          _handleDropEvent(call.arguments);
          return null;
        default:
          return null;
      }
    });

    await wc.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'sync':
          final raw = call.arguments;
          if (raw is Map) {
            final m = Map<String, dynamic>.from(raw);
            if (!mounted) return null;
            final prev = _snapshot;
            setState(() => _snapshot = AvatarSnapshot.fromJson(m));
            _adjustYIfNeeded(prev);
            _handleInputVisibilityChange(prev.showInput, _snapshot.showInput);
          }
          return null;
        case 'syncPluginMenu':
          final raw = call.arguments;
          if (raw is List) {
            _pluginMenuItems = raw.cast<Map<String, dynamic>>();
          }
          return null;
        case 'syncReadingHwnd':
          _readingCompanionHwnd = (call.arguments as num?)?.toInt() ?? 0;
          debugPrint('AvatarPlacement: readingCompanionHwnd=$_readingCompanionHwnd');
          return null;
        case 'window_close':
          _wanderTimer?.cancel();
          _moveAnimTimer?.cancel();
          _fgPollTimer?.cancel();
          _anchorTrackTimer?.cancel();
          _springTimer?.cancel();
          await windowManager.close();
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
    unawaited(_initPlacement());
  }

  void _adjustYIfNeeded(AvatarSnapshot prev) {
    if (_programmaticMove) return;
    if (_placement != _PlacementState.onDock &&
        _placement != _PlacementState.anchoredWindow) return;
    final theme = _theme;
    if (theme == null) return;

    final oldInset = theme.bottomInsetFor(prev);
    final newInset = _currentBottomInset;
    if ((oldInset - newInset).abs() < 1) return;

    final wc = _wc;
    if (wc == null) return;

    _programmaticMove = true;
    (Platform.isWindows ? wc.getPositionPhysical() : wc.getPosition()).then((pos) async {
      if (!mounted) return;
      double newY;
      if (_placement == _PlacementState.onDock) {
        newY = _dockTopYFor(newInset);
      } else if (_placement == _PlacementState.anchoredWindow && _anchoredHwnd != 0) {
        final info = _getWindowRect(_anchoredHwnd);
        if (info == null) return;
        newY = info.top - _toPhysical(_anchorHeight) +
            _toPhysical(AvatarSnapshot.kFloatingWindowPadding + newInset) - _toPhysical(_titleBarClearance);
      } else {
        return;
      }
      await wc.setPositionPhysical(pos.dx, newY);
      _currentY = newY;
    }).whenComplete(() {
      _programmaticMove = false;
    });
  }

  void _handleInputVisibilityChange(bool wasVisible, bool isVisible) {
    if (wasVisible == isVisible) return;

    final newSize = isVisible
        ? AvatarSnapshot.kFloatingWindowSizeWithInput
        : AvatarSnapshot.kFloatingWindowSize;

    // Just resize — the window expands/shrinks downward.
    // The Stack layout in DesktopAvatarView keeps the avatar at a fixed
    // position from the (new) bottom, so it stays visually in place.
    windowManager.setSize(newSize);

    if (isVisible) {
      _cancelWalk();
    } else {
      // Clear lens attachments when input is dismissed
      if (mounted) {
        setState(() {
          _pendingLensAttachments = null;
          _pendingLensPrompt = null;
        });
      }
      _scheduleNextWander();
    }
  }

  Future<void> _sendVoiceStartToMain() async {
    _cancelWalk();
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarVoiceStart');
    } catch (_) {}
  }

  Future<void> _sendVoiceStopToMain() async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarVoiceStop');
    } catch (_) {}
  }

  Future<void> _sendClickToMain() async {
    _cancelWalk();
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarClick');
    } catch (_) {}
  }

  Future<void> _sendDoubleClickToMain() async {
    _cancelWalk();
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarDoubleClick');
    } catch (_) {}
  }

  Future<void> _sendMenuActionToMain(String action) async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarMenuAction', action);
    } catch (_) {}
  }

  Future<void> _sendPluginActionToMain(String pluginId) async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('pluginMenuAction', {
        'pluginId': pluginId,
        'hwnd': _anchoredHwnd,
        'isBrowser': _anchoredHwnd != 0
            ? Win32ScreenCapture.isBrowserWindow(_anchoredHwnd)
            : false,
      });
    } catch (e) {
      debugPrint('sendPluginActionToMain error: $e');
    }
  }

  bool _menuVisible = false;

  /// Dynamic plugin menu items pushed from the main window.
  List<Map<String, dynamic>> _pluginMenuItems = [];

  Future<void> _onShowNativeMenu() async {
    if (_menuVisible) return;
    _menuVisible = true;

    _cancelWalk();

    final wc = _wc;
    if (wc == null) {
      _menuVisible = false;
      return;
    }

    try {
      final s = S.current;

      // Build menu items: use plugin system if available, else fallback
      final List<Map<String, dynamic>> items;
      final Map<int, String> actions;
      if (_pluginMenuItems.isNotEmpty) {
        items = [
          ..._pluginMenuItems,
          {'id': 0, 'label': '', 'enabled': false},
          {'id': 9990, 'label': s.appName, 'enabled': true},
        ];
        actions = {
          for (final item in _pluginMenuItems)
            (item['id'] as int): item['pluginId'] as String? ?? '',
          9990: 'show_main',
        };
      } else {
        items = [
          {'id': 1, 'label': s.menuTakeNote, 'enabled': true},
          {'id': 4, 'label': s.menuAiLens, 'enabled': true},
          {'id': 5, 'label': s.menuSearchSimilar, 'enabled': true},
          {'id': 6, 'label': s.menuStartReading, 'enabled': true},
          {'id': 0, 'label': '', 'enabled': false},
          {'id': 2, 'label': s.appName, 'enabled': true},
          {'id': 3, 'label': s.menuSwitchWindow, 'enabled': false},
        ];
        actions = const {
          1: 'note_capture', 4: 'ai_lens', 5: 'search_similar',
          6: 'start_reading', 2: 'show_main', 3: 'switch_window',
        };
      }

      final action = await wc.showPopupMenu(
        items: items,
        actions: actions,
      );

      _menuVisible = false;
      if (!mounted) return;

      // Static built-in actions handled locally in avatar engine
      if (action == 'ai_lens') {
        await _enterLensMode();
        return;
      }

      if (action == 'search_similar') {
        await _enterLensMode(searchSimilar: true);
        return;
      }

      if (action == 'note_capture') {
        _handleNoteCapture();
        return;
      }

      if (action == 'start_reading') {
        await _handleStartReading();
        return;
      }

      _scheduleNextWander();

      if (action == 'show_main') {
        _sendMenuActionToMain(action);
        return;
      }

      // Plugin action -- forward to main window with context
      if (action.isNotEmpty) {
        _sendPluginActionToMain(action);
      }
    } catch (e) {
      debugPrint('showPopupMenu error: $e');
      _menuVisible = false;
      if (mounted) _scheduleNextWander();
    }
  }

  // ---------------------------------------------------------------------------
  // 记一记 — quick window capture
  // ---------------------------------------------------------------------------

  void _handleNoteCapture() {
    if (_anchoredHwnd == 0) {
      debugPrint('NoteCapture: no anchored window');
      _scheduleNextWander();
      return;
    }
    _sendMenuActionToMainWithData('note_capture', {'hwnd': _anchoredHwnd});
    _scheduleNextWander();
  }

  Future<void> _handleStartReading() async {
    if (_anchoredHwnd == 0) {
      debugPrint('StartReading: no anchored window');
      _scheduleNextWander();
      return;
    }
    if (!ScreenCapture.isBrowserWindow(_anchoredHwnd)) {
      debugPrint('StartReading: not a browser window');
      _scheduleNextWander();
      return;
    }

    var url = '';
    // On Windows, try keyboard-based extraction first (most reliable)
    if (Platform.isWindows) {
      url = await Win32ScreenCapture.getBrowserUrlViaKeyboard(_anchoredHwnd) ?? '';
    }
    // Fallback to window-title regex
    if (url.isEmpty) {
      url = ScreenCapture.getBrowserUrl(_anchoredHwnd) ?? '';
    }

    final title = ScreenCapture.getWindowTitle(_anchoredHwnd);
    await _sendMenuActionToMainWithData('start_reading', {
      'hwnd': _anchoredHwnd,
      'url': url,
      'title': title,
    });
    _scheduleNextWander();
  }

  Future<void> _sendMenuActionToMainWithData(
      String action, Map<String, dynamic> data) async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarMenuActionWithData', {
        'action': action,
        ...data,
      });
    } catch (e) {
      debugPrint('sendMenuActionToMainWithData error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Drag & Drop handling (from native IDropTarget)
  // ---------------------------------------------------------------------------

  void _handleDropEvent(dynamic args) {
    if (args == null) return;
    final data = Map<String, dynamic>.from(args as Map);
    // Show "eating" animation briefly, then forward to main engine
    if (mounted) {
      setState(() => _localActivityOverride = 'eating');
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _localActivityOverride = 'satisfied');
      }
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() => _localActivityOverride = null);
          _scheduleNextWander();
        }
      });
    });
    _sendDropToMain(data);
  }

  Future<void> _sendDropToMain(Map<String, dynamic> data) async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarDrop', data);
    } catch (e) {
      debugPrint('sendDropToMain error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // BoJi Lens (圈一圈) — annotation mode
  // ---------------------------------------------------------------------------

  Future<void> _enterLensMode({bool searchSimilar = false}) async {
    if (_lensActive) return;
    if (_anchoredHwnd == 0) {
      debugPrint('BoJiLens: no anchored window');
      _scheduleNextWander();
      return;
    }
    if (!Platform.isWindows && !Platform.isMacOS) return;

    // Capture anchored window screenshot before any UI changes
    final capture = ScreenCapture.captureWindow(_anchoredHwnd);
    if (capture == null) {
      debugPrint('BoJiLens: capture failed');
      _scheduleNextWander();
      return;
    }
    final title = ScreenCapture.getWindowTitle(_anchoredHwnd);

    // Get anchored window rect for expansion
    final info = _getWindowRect(_anchoredHwnd);
    if (info == null) {
      debugPrint('BoJiLens: cannot get window rect');
      _scheduleNextWander();
      return;
    }

    // Save current avatar position and size
    _lensPreX = _currentX;
    _lensPreY = _currentY;
    _lensPreSize = _windowSize;

    final wc = _wc;
    if (wc == null) return;

    // Expand avatar window to cover anchored window (physical pixels)
    final expandW = info.width;
    final expandH = info.height;
    _programmaticMove = true;
    await windowManager.setSize(Size(expandW, expandH));
    await wc.setPositionPhysical(info.left, info.top);
    _currentX = info.left;
    _currentY = info.top;
    _programmaticMove = false;

    if (!mounted) return;
    setState(() {
      _lensActive = true;
      _searchSimilarMode = searchSimilar;
      _lensCapture = capture;
      _lensRects = [];
      _lensDrawingRect = null;
      _lensWindowTitle = title;
    });

    debugPrint('BoJiLens: entered annotation mode for "$title" '
        '(${capture.width}x${capture.height}), '
        'searchSimilar=$searchSimilar');
  }

  // Pending lens attachments to push into the input field after lens exit
  List<OutgoingAttachment>? _pendingLensAttachments;
  String? _pendingLensPrompt;

  Future<void> _exitLensMode({bool submit = false}) async {
    if (!_lensActive) return;
    final isSearchSimilar = _searchSimilarMode;
    debugPrint('BoJiLens: exiting annotation mode (submit=$submit, '
        'rects=${_lensRects.length}, hasCapture=${_lensCapture != null}, '
        'searchSimilar=$isSearchSimilar)');

    // For search_similar: crop the first rect → send to main window
    if (isSearchSimilar && submit && _lensCapture != null && _lensRects.isNotEmpty) {
      final croppedBase64 = await _buildSearchSimilarCrop();
      await _restoreLensWindow();
      if (croppedBase64 != null) {
        _sendMenuActionToMainWithData('search_similar', {
          'pngBase64': croppedBase64,
          'avatarX': _currentX,
          'avatarY': _currentY,
        });
      } else {
        _scheduleNextWander();
      }
      return;
    }

    List<OutgoingAttachment>? lensAttachments;
    String? lensPrompt;

    if (submit && _lensCapture != null) {
      final result = await _buildLensAttachment();
      if (result != null) {
        lensAttachments = [result.attachment];
        lensPrompt = result.prompt;
      }
    }

    await _restoreLensWindow(
      attachments: lensAttachments,
      prompt: lensPrompt,
    );

    if (lensAttachments != null) {
      _sendDoubleClickToMain();
    } else {
      _scheduleNextWander();
    }
    debugPrint('BoJiLens: exited annotation mode');
  }

  Future<void> _restoreLensWindow({
    List<OutgoingAttachment>? attachments,
    String? prompt,
  }) async {
    final wc = _wc;
    if (wc == null) return;

    _programmaticMove = true;
    if (attachments != null) {
      await windowManager.setSize(AvatarSnapshot.kFloatingWindowSizeWithInput);
    } else {
      await windowManager.setSize(_lensPreSize);
    }
    await wc.setPositionPhysical(_lensPreX, _lensPreY);
    _currentX = _lensPreX;
    _currentY = _lensPreY;
    _programmaticMove = false;

    if (!mounted) return;
    setState(() {
      _lensActive = false;
      _searchSimilarMode = false;
      _lensCapture = null;
      _lensRects = [];
      _lensDrawingRect = null;
      _lensWindowTitle = '';
      _pendingLensAttachments = attachments;
      _pendingLensPrompt = prompt;
    });
  }

  /// Crop the first selection rect from the capture for search_similar.
  Future<String?> _buildSearchSimilarCrop() async {
    final capture = _lensCapture;
    if (capture == null || _lensRects.isEmpty) return null;

    final r = _lensRects.first;
    final px = (r.left * capture.dpiScale).round();
    final py = (r.top * capture.dpiScale).round();
    final pw = (r.width * capture.dpiScale).round();
    final ph = (r.height * capture.dpiScale).round();

    debugPrint('SearchSimilar: cropping (${px}x$py, ${pw}x$ph) from '
        '${capture.width}x${capture.height}');

    final png = await capture.cropToPng(px, py, pw, ph);
    if (png == null) {
      debugPrint('SearchSimilar: crop failed');
      return null;
    }

    return base64Encode(png);
  }

  /// Build an OutgoingAttachment + prompt from the current lens state.
  Future<({OutgoingAttachment attachment, String prompt})?> _buildLensAttachment() async {
    final capture = _lensCapture;
    if (capture == null) return null;

    debugPrint('BoJiLens: encoding PNG (${capture.width}x${capture.height})...');
    final png = await capture.toPng();
    if (png == null) {
      debugPrint('BoJiLens: PNG encoding failed');
      return null;
    }
    debugPrint('BoJiLens: PNG encoded, ${png.length} bytes');

    final b64 = base64Encode(png);

    final buf = StringBuffer();
    buf.writeln('[BoJi Lens capture] Window: "$_lensWindowTitle"');
    if (_lensRects.isNotEmpty) {
      buf.writeln('Annotated regions:');
      for (var i = 0; i < _lensRects.length; i++) {
        final r = _lensRects[i];
        final x = (r.left * capture.dpiScale).round();
        final y = (r.top * capture.dpiScale).round();
        final w = (r.width * capture.dpiScale).round();
        final h = (r.height * capture.dpiScale).round();
        buf.writeln('  ${i + 1}. ($x, $y): ${w}x$h');
      }
    }

    return (
      attachment: OutgoingAttachment(
        type: 'image',
        mimeType: 'image/png',
        fileName: 'boji_lens_capture.png',
        base64: b64,
      ),
      prompt: buf.toString(),
    );
  }

  void _onLensRectStart(Offset localPos) {
    if (!_lensActive) return;
    setState(() {
      _lensDrawingRect = Rect.fromLTWH(localPos.dx, localPos.dy, 0, 0);
    });
  }

  void _onLensRectUpdate(Offset localPos, Offset startPos) {
    if (!_lensActive) return;
    setState(() {
      _lensDrawingRect = Rect.fromPoints(startPos, localPos);
    });
  }

  void _onLensRectEnd() {
    if (!_lensActive || _lensDrawingRect == null) return;
    final r = _lensDrawingRect!;
    if (r.width.abs() >= 5 && r.height.abs() >= 5) {
      final normalized = Rect.fromLTRB(
        min(r.left, r.right), min(r.top, r.bottom),
        max(r.left, r.right), max(r.top, r.bottom),
      );
      setState(() {
        _lensRects = [..._lensRects, normalized];
        _lensDrawingRect = null;
      });
      if (_searchSimilarMode) {
        _exitLensMode(submit: true);
      }
    } else {
      setState(() => _lensDrawingRect = null);
    }
  }

  void _onLensUndo() {
    if (!_lensActive || _lensRects.isEmpty) return;
    setState(() {
      _lensRects = List.from(_lensRects)..removeLast();
    });
  }

  Future<void> _sendLensResultToMain() async {
    final capture = _lensCapture;
    if (capture == null) {
      debugPrint('BoJiLens: no capture to send');
      return;
    }

    debugPrint('BoJiLens: encoding PNG (${capture.width}x${capture.height})...');
    final png = await capture.toPng();
    if (png == null) {
      debugPrint('BoJiLens: PNG encoding failed');
      return;
    }
    debugPrint('BoJiLens: PNG encoded, ${png.length} bytes');

    final rectsJson = _lensRects.map((r) => {
      'x': (r.left * capture.dpiScale).round(),
      'y': (r.top * capture.dpiScale).round(),
      'w': (r.width * capture.dpiScale).round(),
      'h': (r.height * capture.dpiScale).round(),
    }).toList();

    final b64 = base64Encode(png);
    debugPrint('BoJiLens: base64 length=${b64.length}, rects=${rectsJson.length}, '
        'title=$_lensWindowTitle, sending to main...');

    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarLensResult', {
        'windowTitle': _lensWindowTitle,
        'rects': rectsJson,
        'pngBase64': b64,
      });
      debugPrint('BoJiLens: result sent to main window');
    } catch (e) {
      debugPrint('BoJiLens: send result failed: $e');
    }
  }

  Future<void> _sendTextSubmitToMain(String text,
      {List<OutgoingAttachment> attachments = const []}) async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      if (attachments.isEmpty) {
        await main.invokeMethod('avatarTextSubmit', text);
      } else {
        await main.invokeMethod('avatarTextSubmitWithAttachments', {
          'text': text,
          'attachments': attachments
              .map((a) => {
                    'type': a.type,
                    'mimeType': a.mimeType,
                    'fileName': a.fileName,
                    'base64': a.base64,
                  })
              .toList(),
        });
      }
    } catch (e) {
      debugPrint('AvatarInput: sendTextSubmitToMain error: $e');
    }
  }

  Future<void> _sendInputDismissToMain() async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarInputDismiss');
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
      showInput: _snapshot.showInput,
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
        child: _lensActive
            ? LensAnnotationOverlay(
                capture: _lensCapture,
                rects: _lensRects,
                drawingRect: _lensDrawingRect,
                searchSimilarMode: _searchSimilarMode,
                onRectStart: _onLensRectStart,
                onRectUpdate: _onLensRectUpdate,
                onRectEnd: _onLensRectEnd,
                onUndo: _onLensUndo,
                onCancel: () => _exitLensMode(submit: false),
                onConfirm: () => _exitLensMode(submit: true),
              )
            : DesktopAvatarView(
                snapshot: _displaySnapshot,
                onVoiceStart: _sendVoiceStartToMain,
                onVoiceStop: _sendVoiceStopToMain,
                onAvatarClick: _sendClickToMain,
                onAvatarDoubleClick: _sendDoubleClickToMain,
                onShowNativeMenu: _onShowNativeMenu,
                onTextSubmit: (text, {List<OutgoingAttachment> attachments = const []}) {
                  _sendTextSubmitToMain(text, attachments: attachments);
                },
                onInputDismiss: _sendInputDismissToMain,
                initialAttachments: _pendingLensAttachments,
                initialText: _pendingLensPrompt,
                preloadedTheme: _theme,
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
    await windowManager.setHasShadow(false);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setTitle(S.current.avatarWindowTitle);
    await windowManager.show();
  });
}

// ---------------------------------------------------------------------------
// Windows taskbar position via SHAppBarMessage (dart:ffi)
// ---------------------------------------------------------------------------

class _WinTaskbarInfo {
  final double screenWidth;
  final double screenHeight;
  final bool atBottom;
  final double taskbarHeight;
  final double taskbarLeft;
  final double taskbarRight;

  _WinTaskbarInfo({
    required this.screenWidth,
    required this.screenHeight,
    required this.atBottom,
    required this.taskbarHeight,
    required this.taskbarLeft,
    required this.taskbarRight,
  });
}

base class _RECT extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

base class _APPBARDATA extends Struct {
  @Uint32()
  external int cbSize;
  @IntPtr()
  external int hWnd;
  @Uint32()
  external int uCallbackMessage;
  @Uint32()
  external int uEdge;
  external _RECT rc;
  @IntPtr()
  external int lParam;
}

const int _ABM_GETTASKBARPOS = 5;
const int _ABE_BOTTOM = 3;

typedef _SHAppBarMessageNative = IntPtr Function(
    Uint32 dwMessage, Pointer<_APPBARDATA> pData);
typedef _SHAppBarMessageDart = int Function(
    int dwMessage, Pointer<_APPBARDATA> pData);

typedef _GetSystemMetricsNative = Int32 Function(Int32 nIndex);
typedef _GetSystemMetricsDart = int Function(int nIndex);

const int _SM_CXSCREEN = 0;
const int _SM_CYSCREEN = 1;

typedef _GetDpiForSystemNative = Uint32 Function();
typedef _GetDpiForSystemDart = int Function();

_WinTaskbarInfo? _getWindowsTaskbarInfo() {
  try {
    final shell32 = DynamicLibrary.open('shell32.dll');
    final user32 = DynamicLibrary.open('user32.dll');

    final shAppBarMessage = shell32
        .lookupFunction<_SHAppBarMessageNative, _SHAppBarMessageDart>(
            'SHAppBarMessage');
    final getSystemMetrics = user32
        .lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>(
            'GetSystemMetrics');

    final screenW = getSystemMetrics(_SM_CXSCREEN).toDouble();
    final screenH = getSystemMetrics(_SM_CYSCREEN).toDouble();

    final abd = calloc<_APPBARDATA>();
    abd.ref.cbSize = sizeOf<_APPBARDATA>();
    final result = shAppBarMessage(_ABM_GETTASKBARPOS, abd);

    if (result == 0) {
      calloc.free(abd);
      return null;
    }

    final edge = abd.ref.uEdge;
    final rc = abd.ref.rc;
    final tbLeft = rc.left.toDouble();
    final tbTop = rc.top.toDouble();
    final tbRight = rc.right.toDouble();
    final tbBottom = rc.bottom.toDouble();
    calloc.free(abd);

    final atBottom = edge == _ABE_BOTTOM;
    final tbHeight = atBottom ? (tbBottom - tbTop) : 0.0;

    debugPrint('WinTaskbar: screen=${screenW}x$screenH, '
        'edge=$edge, rect=($tbLeft,$tbTop)-($tbRight,$tbBottom)');

    return _WinTaskbarInfo(
      screenWidth: screenW,
      screenHeight: screenH,
      atBottom: atBottom,
      taskbarHeight: tbHeight,
      taskbarLeft: tbLeft,
      taskbarRight: tbRight,
    );
  } catch (e) {
    debugPrint('_getWindowsTaskbarInfo failed: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Foreground / window rect helpers (Windows)
// ---------------------------------------------------------------------------

class _ForegroundWindowInfo {
  final int hwnd;
  final double left, top, width, height;
  final bool isFullscreen;
  final bool isSelf;
  final bool isDesktop;
  final int pid;

  _ForegroundWindowInfo({
    required this.hwnd,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.isFullscreen,
    required this.isSelf,
    required this.isDesktop,
    required this.pid,
  });
}

class _WindowRectInfo {
  final double left, top, width, height;
  final bool isFullscreen;

  _WindowRectInfo({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.isFullscreen,
  });
}

typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

typedef _GetWindowRectNative = Int32 Function(IntPtr hWnd, Pointer<_RECT> lpRect);
typedef _GetWindowRectDart = int Function(int hWnd, Pointer<_RECT> lpRect);

typedef _GetWindowThreadProcessIdNative = Uint32 Function(
    IntPtr hWnd, Pointer<Uint32> lpdwProcessId);
typedef _GetWindowThreadProcessIdDart = int Function(
    int hWnd, Pointer<Uint32> lpdwProcessId);

typedef _IsWindowNative = Int32 Function(IntPtr hWnd);
typedef _IsWindowDart = int Function(int hWnd);

typedef _IsIconicNative = Int32 Function(IntPtr hWnd);
typedef _IsIconicDart = int Function(int hWnd);

typedef _GetWindowLongNative = Int32 Function(IntPtr hWnd, Int32 nIndex);
typedef _GetWindowLongDart = int Function(int hWnd, int nIndex);

typedef _GetDpiForWindowNative = Uint32 Function(IntPtr hWnd);
typedef _GetDpiForWindowDart = int Function(int hWnd);

typedef _GetClassNameNative = Int32 Function(
    IntPtr hWnd, Pointer<Utf16> lpClassName, Int32 nMaxCount);
typedef _GetClassNameDart = int Function(
    int hWnd, Pointer<Utf16> lpClassName, int nMaxCount);

typedef _FindWindowNative = IntPtr Function(
    Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
typedef _FindWindowDart = int Function(
    Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);

late final DynamicLibrary _user32Lib = DynamicLibrary.open('user32.dll');

/// HWND of the avatar window itself, set once at startup.
/// Used to exclude self from foreground checks and for DPI-consistent positioning.
int _avatarSelfHwnd = 0;

int _getActiveWindow() {
  try {
    final fn = _user32Lib
        .lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow');
    return fn();
  } catch (_) {
    return 0;
  }
}

int _findWindowByTitle(String title) {
  try {
    final findWindow = _user32Lib
        .lookupFunction<_FindWindowNative, _FindWindowDart>('FindWindowW');
    final titlePtr = title.toNativeUtf16();
    final hwnd = findWindow(Pointer.fromAddress(0), titlePtr);
    malloc.free(titlePtr);
    return hwnd;
  } catch (_) {
    return 0;
  }
}

bool _isWindowValid(int hwnd) {
  try {
    final isWindow = _user32Lib
        .lookupFunction<_IsWindowNative, _IsWindowDart>('IsWindow');
    return isWindow(hwnd) != 0;
  } catch (_) {
    return false;
  }
}

bool _isWindowMinimized(int hwnd) {
  try {
    final isIconic = _user32Lib
        .lookupFunction<_IsIconicNative, _IsIconicDart>('IsIconic');
    return isIconic(hwnd) != 0;
  } catch (_) {
    return false;
  }
}

/// Returns the DPI scale for a specific window's monitor (per-monitor DPI).
/// Falls back to system DPI if GetDpiForWindow is unavailable.
double _getWinDpiScaleForWindow(int hwnd) {
  try {
    final getDpiForWindow = _user32Lib
        .lookupFunction<_GetDpiForWindowNative, _GetDpiForWindowDart>(
            'GetDpiForWindow');
    final dpi = getDpiForWindow(hwnd);
    if (dpi > 0) return dpi / 96.0;
  } catch (_) {}
  return _getWinDpiScaleSystem();
}

double _getWinDpiScaleSystem() {
  try {
    final getDpiForSystem = _user32Lib
        .lookupFunction<_GetDpiForSystemNative, _GetDpiForSystemDart>(
            'GetDpiForSystem');
    final dpi = getDpiForSystem();
    return dpi > 0 ? dpi / 96.0 : 1.0;
  } catch (_) {
    return 1.0;
  }
}

/// Check if a window is a desktop shell window (Progman, WorkerW).
bool _isDesktopWindow(int hwnd) {
  try {
    final getClassName = _user32Lib
        .lookupFunction<_GetClassNameNative, _GetClassNameDart>('GetClassNameW');
    final buf = calloc<Uint16>(256);
    final len = getClassName(hwnd, buf.cast<Utf16>(), 256);
    if (len <= 0) {
      calloc.free(buf);
      return false;
    }
    final className = buf.cast<Utf16>().toDartString();
    calloc.free(buf);
    return className == 'Progman' || className == 'WorkerW';
  } catch (_) {
    return false;
  }
}

/// Check if a window is a system popup, flyout, or transient panel that should
/// not receive avatar anchoring. Uses window class name + extended style bits.
bool _isSystemPopup(int hwnd) {
  try {
    final getClassName = _user32Lib
        .lookupFunction<_GetClassNameNative, _GetClassNameDart>('GetClassNameW');
    final buf = calloc<Uint16>(256);
    final len = getClassName(hwnd, buf.cast<Utf16>(), 256);
    String className = '';
    if (len > 0) {
      className = buf.cast<Utf16>().toDartString();
    }
    calloc.free(buf);

    const systemClasses = {
      'Shell_TrayWnd',
      'Shell_SecondaryTrayWnd',
      'NotifyIconOverflowWindow',
      'TaskListThumbnailWnd',
      'DV2ControlHost',
      'Shell_InputSwitchTopLevelWindow',
      'XamlExplorerHostIslandWindow',
      'TopLevelWindowForOverflowXamlIsland',
      'Windows.UI.Core.CoreWindow',
      'Windows.UI.Input.InputSite.WindowClass',
      'ForegroundStaging',
      'tooltips_class32',
      '#32768', // context menus
      '#32770', // system dialogs (some)
    };
    if (systemClasses.contains(className)) return true;

    // Flyout/system panel class names often start with these prefixes
    if (className.startsWith('Windows.UI.') ||
        className.startsWith('Shell_') ||
        className.startsWith('TaskList')) {
      return true;
    }

    // Check WS_EX_TOOLWINDOW style — common on transient system panels
    const gwlExStyle = -20;
    const wsExToolWindow = 0x00000080;
    const wsExNoActivate = 0x08000000;
    final getWindowLong = _user32Lib
        .lookupFunction<_GetWindowLongNative, _GetWindowLongDart>(
            'GetWindowLongW');
    final exStyle = getWindowLong(hwnd, gwlExStyle);
    if ((exStyle & wsExToolWindow) != 0 && (exStyle & wsExNoActivate) != 0) {
      return true;
    }
  } catch (_) {}
  return false;
}

/// Get the rect of any window by HWND.
///
/// Coordinates are returned in the **avatar window's DPI space** so that
/// `setPosition` (which multiplies by the avatar's DPI) produces the correct
/// physical position. This is critical for multi-monitor setups where the
/// target window may be on a monitor with a different DPI than the avatar.
///
/// [avatarHwnd] is the avatar window's HWND; pass 0 to fall back to system DPI.
_WindowRectInfo? _getWinWindowRect(int hwnd, {int avatarHwnd = 0}) {
  try {
    final getWindowRect = _user32Lib
        .lookupFunction<_GetWindowRectNative, _GetWindowRectDart>(
            'GetWindowRect');
    final getSystemMetrics = _user32Lib
        .lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>(
            'GetSystemMetrics');

    // Return raw physical pixels — callers use setPositionPhysical to
    // avoid DPI round-trip errors when the avatar crosses monitors with
    // different DPI.
    final rect = calloc<_RECT>();
    final ok = getWindowRect(hwnd, rect);
    if (ok == 0) {
      calloc.free(rect);
      return null;
    }
    final l = rect.ref.left.toDouble();
    final t = rect.ref.top.toDouble();
    final r = rect.ref.right.toDouble();
    final b = rect.ref.bottom.toDouble();
    calloc.free(rect);

    final w = r - l;
    final h = b - t;

    // Use physical screen metrics for fullscreen detection.
    // SM_CXSCREEN/SM_CYSCREEN return primary monitor size in physical pixels.
    final screenW = getSystemMetrics(_SM_CXSCREEN).toDouble();
    final screenH = getSystemMetrics(_SM_CYSCREEN).toDouble();
    final isFullscreen = w >= screenW * 0.95 && h >= screenH * 0.95;

    return _WindowRectInfo(
      left: l,
      top: t,
      width: w,
      height: h,
      isFullscreen: isFullscreen,
    );
  } catch (e) {
    debugPrint('_getWinWindowRect failed: $e');
    return null;
  }
}

_ForegroundWindowInfo? _getWinForegroundInfo() {
  try {
    final getForegroundWindow = _user32Lib
        .lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>(
            'GetForegroundWindow');
    final getWindowThreadProcessId = _user32Lib.lookupFunction<
        _GetWindowThreadProcessIdNative,
        _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');

    final fgHwnd = getForegroundWindow();
    if (fgHwnd == 0) return null;

    final pidPtr = calloc<Uint32>();
    getWindowThreadProcessId(fgHwnd, pidPtr);
    final fgPid = pidPtr.value;
    calloc.free(pidPtr);
    final isSelf = fgPid == pid;
    final isDesktop = _isDesktopWindow(fgHwnd);

    final rectInfo = _getWinWindowRect(fgHwnd);
    if (rectInfo == null) return null;

    return _ForegroundWindowInfo(
      hwnd: fgHwnd,
      left: rectInfo.left,
      top: rectInfo.top,
      width: rectInfo.width,
      height: rectInfo.height,
      isFullscreen: rectInfo.isFullscreen,
      isSelf: isSelf,
      isDesktop: isDesktop,
      pid: fgPid,
    );
  } catch (e) {
    debugPrint('_getWinForegroundInfo failed: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Cross-platform window rect helper
// ---------------------------------------------------------------------------

/// Returns the rect of a window by platform-specific ID.
/// On Windows, uses _getWinWindowRect (Win32 FFI).
/// On macOS, uses MacosScreenCapture.getWindowList() to look up bounds.
_WindowRectInfo? _getWindowRect(int windowId) {
  if (Platform.isWindows) {
    return _getWinWindowRect(windowId);
  }
  if (Platform.isMacOS) {
    return _getMacWindowRect(windowId);
  }
  return null;
}

/// macOS implementation: look up window bounds from getWindowList().
_WindowRectInfo? _getMacWindowRect(int windowID) {
  try {
    final windows = MacosScreenCapture.getWindowList();
    if (windows == null) return null;
    for (final w in windows) {
      if (w.windowID == windowID && w.bounds != null) {
        final b = w.bounds!;
        bool isFullscreen = false;
        final screenSize = ScreenCapture.getScreenSizePoints();
        if (screenSize != null) {
          isFullscreen = (b['Width']! - screenSize[0]).abs() < 2 &&
              (b['Height']! - screenSize[1]).abs() < 2 &&
              b['X'] == 0 && b['Y'] == 0;
        }
        return _WindowRectInfo(
          left: b['X']!.toDouble(),
          top: b['Y']!.toDouble(),
          width: b['Width']!.toDouble(),
          height: b['Height']!.toDouble(),
          isFullscreen: isFullscreen,
        );
      }
    }
    return null;
  } catch (e) {
    debugPrint('_getMacWindowRect failed: $e');
    return null;
  }
}
