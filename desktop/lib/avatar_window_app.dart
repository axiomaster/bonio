import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models/avatar_snapshot.dart';
import 'ui/widgets/desktop_avatar_overlay.dart';

/// Second engine: OS-level floating avatar (main BoJi window can be minimized).
class AvatarFloatingApp extends StatefulWidget {
  final String mainWindowId;

  const AvatarFloatingApp({super.key, required this.mainWindowId});

  @override
  State<AvatarFloatingApp> createState() => _AvatarFloatingAppState();
}

class _AvatarFloatingAppState extends State<AvatarFloatingApp> {
  AvatarSnapshot _snapshot = AvatarSnapshot(
    posX: 0,
    posY: 0,
    activity: 'idle',
    effectiveActivity: 'idle',
    gesture: 'none',
    isMoving: false,
  );

  @override
  void initState() {
    super.initState();
    _registerHandler();
  }

  Future<void> _registerHandler() async {
    final wc = await WindowController.fromCurrentEngine();
    await wc.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'sync':
          final raw = call.arguments;
          if (raw is Map) {
            final m = Map<String, dynamic>.from(raw);
            if (!mounted) return null;
            setState(() => _snapshot = AvatarSnapshot.fromJson(m));
          }
          return null;
        case 'window_close':
          await windowManager.close();
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
  }

  Future<void> _sendVoiceTapToMain() async {
    try {
      final main = WindowController.fromWindowId(widget.mainWindowId);
      await main.invokeMethod('avatarVoiceTap');
    } catch (_) {}
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
          snapshot: _snapshot,
          onAvatarTap: _sendVoiceTapToMain,
          isFloatingWindow: true,
        ),
      ),
    );
  }
}

/// Called from [main] before [runApp] for the avatar engine only.
///
/// The native window was already created as WS_POPUP at kFloatingWindowSize
/// by the vendored desktop_multi_window; we must NOT pass `size` or
/// `titleBarStyle` to WindowOptions — those trigger SetBounds /
/// DwmExtendFrameIntoClientArea which resize or reframe the WS_POPUP window
/// and squash the Flutter surface.
Future<void> initAvatarWindowEngine() async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(null, () async {
    await windowManager.setHasShadow(false);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setTitle('BoJi Avatar');
    await windowManager.show();
  });
}
