import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../services/app_logger.dart';

/// Windows built-in OCR wrapper backed by WinRT `Windows.Media.Ocr`.
///
/// This stays fully client-side and is generally more reliable than the
/// current native PaddleOCR wrapper for simple standard-font screenshots.
class WindowsOcr {
  final _log = AppLogger.instance;

  static const _scriptFileName = 'bonio_windows_ocr.ps1';

  static const _scriptContent = r'''
param([string]$ImagePath)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Media.Ocr, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

function Invoke-AsTask($op, $type) {
  $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
      $_.Name -eq 'AsTask' -and
      $_.IsGenericMethodDefinition -and
      $_.GetGenericArguments().Count -eq 1 -and
      $_.GetParameters().Count -eq 1
    } |
    Select-Object -First 1
  $generic = $method.MakeGenericMethod($type)
  return $generic.Invoke($null, @($op))
}

$file = (Invoke-AsTask ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])).Result
$stream = (Invoke-AsTask ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])).Result
$decoder = (Invoke-AsTask ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])).Result
$bitmap = (Invoke-AsTask ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])).Result

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) {
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('zh-Hans-CN'))
}
if ($null -eq $engine) {
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('en-US'))
}
if ($null -eq $engine) {
  throw 'Windows OCR engine unavailable'
}

$result = (Invoke-AsTask ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])).Result
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$result.Text
''';

  Future<String?> recognizePngBytes(Uint8List pngBytes) async {
    if (!Platform.isWindows) return null;

    File? imageFile;
    try {
      final tempDir = await Directory.systemTemp.createTemp('bonio-ocr-');
      final scriptFile = File(
          '${tempDir.path}${Platform.pathSeparator}$_scriptFileName');
      await scriptFile.writeAsString(_scriptContent);

      imageFile = File(
          '${tempDir.path}${Platform.pathSeparator}capture.png');
      await imageFile.writeAsBytes(pngBytes, flush: true);

      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptFile.path,
          imageFile.path,
        ],
        runInShell: false,
      );

      if (result.exitCode != 0) {
        _log.warn(
            'WindowsOCR: exit=${result.exitCode}, stderr=${result.stderr}');
        return null;
      }

      final text = (result.stdout is String)
          ? result.stdout as String
          : utf8.decode(result.stdout as List<int>);
      final normalized = text.replaceAll('\r\n', '\n').trim();
      _log.info('WindowsOCR: result length=${normalized.length}');
      return normalized.isEmpty ? null : normalized;
    } catch (e) {
      _log.warn('WindowsOCR: recognize error: $e');
      return null;
    } finally {
      try {
        if (imageFile != null) {
          final dir = imageFile.parent;
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      } catch (_) {}
    }
  }
}
