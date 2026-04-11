import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:window_manager/window_manager.dart';

import 'avatar_window_app.dart';
import 'l10n/app_strings.dart';
import 'providers/app_state.dart';
import 'services/tray_service.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/reading_companion_screen.dart';
import 'ui/screens/search_similar_screen.dart';

/// Resolves `bojiWindow: avatar` JSON from plugin + entrypoint args.
///
/// On Windows the child engine sometimes exposes a bad/non-JSON
/// [WindowController.arguments] while [args] from
/// `set_dart_entrypoint_arguments(["multi_window", id, json])` is correct.
/// We therefore try **`args[2]` first** when present, then `wc.arguments`.
String _trimJsonCandidate(String raw) {
  var t = raw.trim();
  if (t.isNotEmpty && t.codeUnitAt(0) == 0xFEFF) {
    t = t.substring(1).trim();
  }
  return t;
}

Map<String, dynamic>? _decodeWindowPayload(String raw) {
  final t = _trimJsonCandidate(raw);
  if (t.isEmpty || !t.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(t);
    if (decoded is! Map) return null;
    final m = Map<String, dynamic>.from(decoded);
    if (m.containsKey('bojiWindow')) return m;
  } catch (_) {}
  return null;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  sherpa.initBindings();
  final locale = await S.loadLocale();
  S.setLocale(locale);
  final wc = await WindowController.fromCurrentEngine();

  final candidates = <String>[];
  if (args.length >= 3 && args[0] == 'multi_window') {
    candidates.add(args[2]);
  }
  final wArg = wc.arguments.trim();
  if (wArg.isNotEmpty && !candidates.contains(wArg)) {
    candidates.add(wArg);
  }

  Map<String, dynamic>? payload;
  for (final c in candidates) {
    payload = _decodeWindowPayload(c);
    if (payload != null) break;
  }

  if (payload == null) {
    if (candidates.isEmpty || candidates.every((c) => c.trim().isEmpty)) {
      await _initMainWindow();
      runApp(const BoJiDesktopApp());
      return;
    }
    debugPrint(
      'sub-window engine: could not parse bojiWindow; '
      'candidates=$candidates fullArgs=$args',
    );
    runApp(const _AvatarErrorApp(message: 'Invalid window arguments'));
    return;
  }

  final windowType = payload['bojiWindow'] as String?;

  if (windowType == 'search_similar') {
    final imagePath = payload['imagePath'] as String? ?? '';
    runApp(SearchSimilarApp(imagePath: imagePath));
    return;
  }

  if (windowType == 'reading_companion') {
    final url = payload['url'] as String? ?? '';
    final mainId = payload['mainWindowId']?.toString() ?? '';
    runApp(ReadingCompanionApp(url: url, mainWindowId: mainId));
    return;
  }

  if (windowType == 'avatar') {
    final mainId = payload['mainWindowId']?.toString();
    if (mainId == null || mainId.isEmpty) {
      runApp(const _AvatarErrorApp(message: 'Missing mainWindowId'));
      return;
    }
    await initAvatarWindowEngine();
    runApp(AvatarFloatingApp(mainWindowId: mainId));
    return;
  }

  runApp(_AvatarErrorApp(message: 'Unknown window type: $windowType'));
}

class _AvatarErrorApp extends StatelessWidget {
  final String message;
  const _AvatarErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text(message))),
    );
  }
}

/// Initializes [windowManager] for the main (primary) window: close → hide to tray.
Future<void> _initMainWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await windowManager.setTitle(S.current.appName);
}

class BoJiDesktopApp extends StatefulWidget {
  const BoJiDesktopApp({super.key});

  @override
  State<BoJiDesktopApp> createState() => _BoJiDesktopAppState();
}

class _BoJiDesktopAppState extends State<BoJiDesktopApp> with WindowListener {
  final TrayService _trayService = TrayService();
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _appState = AppState();
    _trayService.onExitRequested = _realExit;
    _trayService.init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  bool _exiting = false;

  /// Close button → hide to tray (avatar stays visible).
  @override
  void onWindowClose() {
    if (_exiting) return;
    windowManager.hide();
  }

  /// Tray "Exit" → close avatar window, then let TrayService call exit(0).
  /// Do NOT call windowManager.destroy() here — it kills the event loop
  /// and prevents exit(0) from firing in TrayService.
  Future<void> _realExit() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await _appState.runtime.desktopTts.stop();
    } catch (_) {}
    try {
      await _appState.runtime.syncAvatarFloatingWindow(show: false);
    } catch (_) {}
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: MaterialApp(
        title: S.current.appName,
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.dark),
        home: const MainScreen(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      brightness: brightness,
      surface: isDark ? const Color(0xFF0F1117) : Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      fontFamily: 'Segoe UI',
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isDark ? const Color(0xFF1A1D27) : Colors.grey[50],
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF252830) : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? const Color(0xFF13151C) : Colors.grey[100],
        indicatorColor: colorScheme.primary.withOpacity(0.15),
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme:
            IconThemeData(color: colorScheme.onSurface.withOpacity(0.5)),
      ),
    );
  }
}
