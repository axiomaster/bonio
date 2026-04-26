import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Simple file logger for bonio-desktop.
/// Writes timestamped log lines to `~/.bonio/logs/desktop.log`.
class AppLogger {
  static AppLogger? _instance;
  static AppLogger get instance => _instance ??= AppLogger._();

  IOSink? _sink;
  bool _initialized = false;

  AppLogger._();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return;

    final logDir = Directory('$home/.bonio/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    final logFile = File('${logDir.path}/desktop.log');
    try {
      _sink = logFile.openWrite(mode: FileMode.append);
      info('AppLogger initialized, log file: ${logFile.path}');
    } catch (e) {
      debugPrint('[AppLogger] Failed to open log file: $e');
    }
  }

  void info(String msg) => _log('INFO', msg);
  void warn(String msg) => _log('WARN', msg);
  void error(String msg) => _log('ERR', msg);
  void debug(String msg) => _log('DEBUG', msg);

  void _log(String level, String msg) {
    final now = DateTime.now();
    final ts =
        '${now.year.toString().padLeft(4, "0")}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")} '
        '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}:${now.second.toString().padLeft(2, "0")}';
    final line = '[$ts] [$level] $msg';
    debugPrint(line);
    _sink?.writeln(line);
  }

  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}

/// Top-level convenience helpers. Import this file and call `log.info(...)` etc.
// ignore: non_constant_identifier_names
AppLogger get log => AppLogger.instance;
