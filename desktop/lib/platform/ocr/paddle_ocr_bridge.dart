import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../services/app_logger.dart';

final _log = AppLogger.instance;

// C function typedefs
typedef PaddleOcrInitNative = Int32 Function(
    Pointer<Utf8> modelDir, Pointer<Utf8> ortPath);
typedef PaddleOcrInitDart = int Function(
    Pointer<Utf8> modelDir, Pointer<Utf8> ortPath);

typedef PaddleOcrRecognizeNative = Pointer<Utf8> Function(
    Pointer<Uint8> bgra, Int32 w, Int32 h);
typedef PaddleOcrRecognizeDart = Pointer<Utf8> Function(
    Pointer<Uint8> bgra, int w, int h);

typedef PaddleOcrFreeStringNative = Void Function(Pointer<Utf8> s);
typedef PaddleOcrFreeStringDart = void Function(Pointer<Utf8> s);

typedef PaddleOcrDestroyNative = Void Function();
typedef PaddleOcrDestroyDart = void Function();

/// Dart FFI wrapper for the PaddleOCR native plugin.
class PaddleOcr {
  DynamicLibrary? _lib;
  bool _initialized = false;

  PaddleOcr();

  bool get isInitialized => _initialized;

  /// Initialize the OCR engine. Call once before [recognize].
  Future<bool> init({
    required String modelDir,
    String? onnxruntimePath,
  }) async {
    if (_initialized) return true;

    try {
      final dllName = Platform.isWindows
          ? 'paddle_ocr_plugin.dll'
          : 'libpaddle_ocr_plugin.dylib';

      // Look for the DLL next to the executable
      final exeDir = Directory(Platform.resolvedExecutable).parent;
      final dllPath = '${exeDir.path}${Platform.pathSeparator}$dllName';

      if (!File(dllPath).existsSync()) {
        _log.warn('PaddleOCR: DLL not found at $dllPath');
        return false;
      }

      _lib = DynamicLibrary.open(dllPath);

      final initFn = _lib!
          .lookupFunction<PaddleOcrInitNative, PaddleOcrInitDart>('paddle_ocr_init');

      final ortPath = onnxruntimePath ??
          '${exeDir.path}${Platform.pathSeparator}onnxruntime.dll';

      final modelPtr = modelDir.toNativeUtf8();
      final ortPtr = ortPath.toNativeUtf8();
      final ret = initFn(modelPtr, ortPtr);
      calloc.free(modelPtr);
      calloc.free(ortPtr);

      if (ret != 0) {
        _log.warn('PaddleOCR: init failed with code $ret');
        return false;
      }

      _initialized = true;
      _log.info('PaddleOCR: initialized, model_dir=$modelDir');
      return true;
    } catch (e) {
      _log.warn('PaddleOCR: init error: $e');
      return false;
    }
  }

  /// Recognize text from BGRA pixel data. Returns the recognized text,
  /// or null if no text was found or an error occurred.
  String? recognize(Uint8List bgraPixels, int width, int height) {
    if (!_initialized || _lib == null) return null;

    try {
      final recognizeFn = _lib!.lookupFunction<
          PaddleOcrRecognizeNative, PaddleOcrRecognizeDart>(
          'paddle_ocr_recognize');

      final freeFn = _lib!.lookupFunction<
          PaddleOcrFreeStringNative, PaddleOcrFreeStringDart>(
          'paddle_ocr_free_string');

      final pixelsPtr = calloc.allocate<Uint8>(bgraPixels.length);
      final pixelsList = pixelsPtr.asTypedList(bgraPixels.length);
      pixelsList.setAll(0, bgraPixels);

      final resultPtr = recognizeFn(pixelsPtr, width, height);
      calloc.free(pixelsPtr);

      if (resultPtr == nullptr) return null;

      final text = resultPtr.toDartString();
      freeFn(resultPtr);
      return text.isNotEmpty ? text : null;
    } catch (e) {
      _log.warn('PaddleOCR: recognize error: $e');
      return null;
    }
  }

  /// Release native resources.
  void dispose() {
    if (!_initialized || _lib == null) return;
    try {
      final destroyFn = _lib!.lookupFunction<
          PaddleOcrDestroyNative, PaddleOcrDestroyDart>('paddle_ocr_destroy');
      destroyFn();
    } catch (_) {}
    _lib = null;
    _initialized = false;
  }
}
