import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Cross-platform desktop speech: no native Flutter plugin (avoids Windows NuGet / CMake).
///
/// - **Windows**: PowerShell + .NET `System.Speech` (SAPI), temp `.ps1` UTF-8 with BOM.
/// - **macOS**: `/usr/bin/say` (optionally via temp file for odd characters).
/// - **Linux**: `spd-say`, then `espeak-ng`, then `espeak` if present in `PATH`.
class DesktopTts {
  Process? _process;

  Future<void> speak(String text) async {
    await stop();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    if (Platform.isWindows) {
      await _speakWindows(trimmed);
    } else if (Platform.isMacOS) {
      await _speakMacOS(trimmed);
    } else if (Platform.isLinux) {
      await _speakLinux(trimmed);
    } else {
      debugPrint('DesktopTts: unsupported platform ${Platform.operatingSystem}');
    }
  }

  Future<void> stop() async {
    final p = _process;
    _process = null;
    if (p != null) {
      try {
        // On Windows, POSIX signals don't work; use kill() which sends
        // SIGTERM on POSIX and TerminateProcess on Windows.
        p.kill();
      } catch (_) {}
      try {
        await p.exitCode.timeout(const Duration(milliseconds: 500));
      } catch (_) {
        try {
          p.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
      // On Windows, kill the entire process tree to stop SAPI speech
      if (Platform.isWindows) {
        try {
          await Process.run('taskkill', ['/F', '/T', '/PID', '${p.pid}']);
        } catch (_) {}
      }
    }
  }

  Future<void> _speakWindows(String text) async {
    final b64 = base64Encode(utf8.encode(text));
    final script = StringBuffer()
      ..writeln("\$bytes = [Convert]::FromBase64String('$b64')")
      ..writeln(r'$t = [Text.Encoding]::UTF8.GetString($bytes)')
      ..writeln('Add-Type -AssemblyName System.Speech')
      ..writeln(
          r'$s = New-Object System.Speech.Synthesis.SpeechSynthesizer')
      ..writeln(r'$s.Speak($t)');
    final dir = await Directory.systemTemp.createTemp('boji_tts_');
    final ps1 = File('${dir.path}${Platform.pathSeparator}speak.ps1');
    final body = utf8.encode(script.toString());
    await ps1.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...body]);
    try {
      _process = await Process.start(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          ps1.path,
        ],
        mode: ProcessStartMode.normal,
      );
      await _process!.exitCode;
    } catch (e, st) {
      debugPrint('DesktopTts Windows: $e\n$st');
    } finally {
      _process = null;
      try {
        if (await ps1.exists()) await ps1.delete();
        await dir.delete();
      } catch (_) {}
    }
  }

  Future<void> _speakMacOS(String text) async {
    debugPrint('DesktopTts: macOS say starting (${text.length} chars)');
    final dir = await Directory.systemTemp.createTemp('boji_tts_');
    final txt = File('${dir.path}${Platform.pathSeparator}say.txt');
    await txt.writeAsString(text, encoding: utf8);
    try {
      _process = await Process.start(
        '/usr/bin/say',
        ['-f', txt.path],
        mode: ProcessStartMode.normal,
      );
      final exitCode = await _process!.exitCode;
      debugPrint('DesktopTts: macOS say finished (exit=$exitCode)');
    } catch (e, st) {
      debugPrint('DesktopTts macOS: $e\n$st');
    } finally {
      _process = null;
      try {
        if (await txt.exists()) await txt.delete();
        await dir.delete();
      } catch (_) {}
    }
  }

  Future<void> _speakLinux(String text) async {
    final candidates = <List<String>>[
      ['spd-say', text],
      ['espeak-ng', text],
      ['espeak', text],
    ];
    for (final args in candidates) {
      final bin = args.first;
      if (!await _which(bin)) continue;
      try {
        _process = await Process.start(
          bin,
          args.sublist(1),
          mode: ProcessStartMode.normal,
        );
        await _process!.exitCode;
        _process = null;
        return;
      } catch (e, st) {
        debugPrint('DesktopTts Linux ($bin): $e\n$st');
        _process = null;
      }
    }
    debugPrint(
        'DesktopTts Linux: no spd-say/espeak-ng/espeak in PATH; skipping TTS');
  }

  static Future<bool> _which(String name) async {
    try {
      final r = await Process.run('which', [name], runInShell: false);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
