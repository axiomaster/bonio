import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';

class HiclawProcess extends ChangeNotifier {
  Process? _process;
  bool _isRunning = false;
  int _port = 10724;
  String? _error;

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get error => _error;

  Future<String> _resolveBinaryPath() async {
    if (Platform.isMacOS) {
      // <app>/Contents/MacOS/executable -> <app>/Contents/Resources/hiclaw
      final exePath = Platform.resolvedExecutable;
      final macosIndex = exePath.indexOf('/Contents/MacOS/');
      if (macosIndex != -1) {
        final resourcesDir =
            '${exePath.substring(0, macosIndex)}/Contents/Resources';
        final bundled = '$resourcesDir/hiclaw';
        if (await File(bundled).exists()) return bundled;
      }
      // Fallback for development: check app support dir
      final supportDir = await getApplicationSupportDirectory();
      final localBin = '${supportDir.path}/boji/hiclaw';
      if (await File(localBin).exists()) return localBin;
      throw FileSystemException('hiclaw binary not found');
    } else if (Platform.isWindows) {
      final exePath = Platform.resolvedExecutable;
      final exeDir = exePath.substring(0, exePath.lastIndexOf('\\'));
      final bundled = '$exeDir\\hiclaw.exe';
      if (await File(bundled).exists()) return bundled;
      final supportDir = await getApplicationSupportDirectory();
      final localBin = '${supportDir.path}\\boji\\hiclaw.exe';
      if (await File(localBin).exists()) return localBin;
      throw FileSystemException('hiclaw binary not found');
    }
    throw UnsupportedError('Unsupported platform');
  }

  Future<String> _workspaceDir() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        (await getApplicationSupportDirectory()).path;
    final dir = Directory('$home/.bonio');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final logsDir = Directory('${dir.path}/logs');
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }
    return dir.path;
  }

  Future<void> start({int port = 10724}) async {
    if (_isRunning) return;
    _port = port;
    _error = null;

    try {
      final binary = await _resolveBinaryPath();
      final workspace = await _workspaceDir();
      final result = await Process.start(
        binary,
        ['gateway', '--port', port.toString()],
        environment: {'HICLAW_WORKSPACE': workspace},
      );

      _process = result;
      _isRunning = true;
      notifyListeners();

      // Hiclaw stdout/stderr: console only, not written to desktop.log.
      // Hiclaw writes its own log file via spdlog at ~/.bonio/logs/hiclaw.log.
      result.stdout
          .transform(utf8.decoder)
          .listen((data) => debugPrint('[hiclaw] $data'));
      result.stderr
          .transform(utf8.decoder)
          .listen((data) => debugPrint('[hiclaw:err] $data'));

      result.exitCode.then((code) {
        _isRunning = false;
        _process = null;
        if (code != 0) {
          _error = 'hiclaw exited with code $code';
        }
        notifyListeners();
      });
    } catch (e) {
      _error = e.toString();
      log.error('[hiclaw] Failed to start: $e');
    }
  }

  Future<void> stop() async {
    if (_process == null) return;
    _process!.kill();
    await _process!.exitCode.timeout(const Duration(seconds: 5),
        onTimeout: () {
      _process!.kill(ProcessSignal.sigkill);
      return -1;
    });
    _process = null;
    _isRunning = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
