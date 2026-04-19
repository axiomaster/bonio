import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'plugin_bridge.dart';
import 'plugin_manifest.dart';

/// Manages the lifecycle of a single sidecar plugin process.
///
/// Handles lazy startup, idle timeout, crash recovery, and graceful shutdown.
class PluginHost {
  final PluginManifest manifest;
  final PluginCapabilityHandler capabilityHandler;

  Process? _process;
  PluginBridge? _bridge;
  Timer? _idleTimer;
  bool _shuttingDown = false;

  static const _idleTimeout = Duration(minutes: 5);
  static const _shutdownGrace = Duration(seconds: 3);

  PluginHost({required this.manifest, required this.capabilityHandler});

  bool get isRunning => _process != null && !_shuttingDown;

  /// Start the sidecar process if not already running.
  Future<void> ensureRunning() async {
    if (isRunning) {
      _resetIdleTimer();
      return;
    }
    await _start();
  }

  Future<void> _start() async {
    final exe = manifest.executablePath;
    if (exe == null) {
      throw StateError('No executable path for plugin ${manifest.id}');
    }

    final exeFile = File(exe);
    if (!await exeFile.exists()) {
      throw StateError('Plugin executable not found: $exe');
    }

    _shuttingDown = false;
    debugPrint('PluginHost[${manifest.id}]: starting $exe');

    _process = await Process.start(exe, [],
        workingDirectory: manifest.directoryPath);

    _bridge = PluginBridge(
      stdin: _process!.stdin,
      stdout: _process!.stdout,
      onRequest: capabilityHandler,
    );
    _bridge!.listen();

    // Monitor for unexpected exit
    unawaited(_process!.exitCode.then(_onProcessExit));

    // Send initialize
    final dataDir =
        '${manifest.directoryPath}${Platform.pathSeparator}data';
    await Directory(dataDir).create(recursive: true);

    await _bridge!.sendRequest('initialize', {
      'hostVersion': '1.0.0',
      'capabilities': [
        'screen', 'window', 'browser', 'chat', 'avatar', 'tts',
        'notes', 'storage',
      ],
      'pluginDataDir': dataDir,
      'locale': Platform.localeName.startsWith('zh') ? 'zh' : 'en',
    });

    await _bridge!.sendRequest('activate', {});

    _resetIdleTimer();
    debugPrint('PluginHost[${manifest.id}]: activated');
  }

  /// Send a menu action to the running plugin.
  Future<Map<String, dynamic>> sendMenuAction(
      Map<String, dynamic> context) async {
    await ensureRunning();
    _resetIdleTimer();
    return await _bridge!.sendRequest('menuAction', context);
  }

  /// Gracefully stop the plugin process.
  Future<void> stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;

    if (_process == null || _shuttingDown) return;
    _shuttingDown = true;

    debugPrint('PluginHost[${manifest.id}]: stopping');

    try {
      await _bridge?.sendRequest('deactivate', {}).timeout(
            const Duration(seconds: 2),
            onTimeout: () => <String, dynamic>{},
          );
      await _bridge?.sendRequest('shutdown', {}).timeout(
            const Duration(seconds: 1),
            onTimeout: () => <String, dynamic>{},
          );
    } catch (_) {}

    // Wait for graceful exit
    final exitFuture = _process?.exitCode;
    if (exitFuture != null) {
      final exited = await exitFuture
          .timeout(_shutdownGrace, onTimeout: () => -1);
      if (exited == -1) {
        debugPrint('PluginHost[${manifest.id}]: force killing');
        _process?.kill(ProcessSignal.sigkill);
      }
    }

    _bridge?.dispose();
    _bridge = null;
    _process = null;
    _shuttingDown = false;
  }

  void _onProcessExit(int code) {
    if (_shuttingDown) return;
    debugPrint('PluginHost[${manifest.id}]: process exited with code $code');
    _bridge?.dispose();
    _bridge = null;
    _process = null;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      debugPrint('PluginHost[${manifest.id}]: idle timeout, stopping');
      stop();
    });
  }

  void dispose() {
    _idleTimer?.cancel();
    stop();
  }
}
