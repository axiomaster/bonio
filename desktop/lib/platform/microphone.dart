import 'dart:io';
import 'dart:typed_data';

import 'macos_microphone.dart';
import 'win32_microphone.dart';

/// Platform-agnostic microphone that streams PCM16 (16 kHz, mono) audio.
abstract class PlatformMicrophone {
  Stream<Uint8List> start();
  Future<void> stop();

  factory PlatformMicrophone() {
    if (Platform.isWindows) return Win32Microphone();
    if (Platform.isMacOS) return MacOsMicrophone();
    throw UnsupportedError('Microphone not supported on ${Platform.operatingSystem}');
  }
}
