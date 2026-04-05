import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../platform/win32_microphone.dart';
import 'speech_to_text_manager.dart';

/// Model directory name (same as Android's `MODEL_DIR` constant).
const _kModelDir = 'sherpa-onnx-streaming-paraformer-bilingual-zh-en';

/// Streaming Sherpa-ONNX speech manager mirroring Android's
/// `SherpaOnnxSpeechManager`.
///
/// Audio is captured via the `record` package (PCM16, 16 kHz, mono) and fed
/// into `sherpa_onnx`'s `OnlineRecognizer` / `OnlineStream` (FFI).  Endpoint
/// detection and partial/final callbacks follow the same logic as the Android
/// Kotlin implementation.
class SherpaOnnxSpeechManager {
  SherpaOnnxSpeechManager();

  sherpa.OnlineRecognizer? _recognizer;
  bool _modelReady = false;
  bool _running = false;
  bool _cancelled = false;
  SpeechToTextListener? _listener;
  Win32Microphone? _mic;
  StreamSubscription<Uint8List>? _audioSub;

  bool get isModelReady => _modelReady;

  // ── Model loading ──────────────────────────────────────────────────────

  /// Resolve the model directory next to the running executable.
  String _modelBasePath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}$_kModelDir';
  }

  /// Load the ONNX model.  Safe to call multiple times.
  Future<void> prepareModel() async {
    if (_modelReady) return;
    try {
      final base = _modelBasePath();
      final encoder = '$base${Platform.pathSeparator}encoder.int8.onnx';
      final decoder = '$base${Platform.pathSeparator}decoder.int8.onnx';
      final tokens = '$base${Platform.pathSeparator}tokens.txt';

      if (!File(encoder).existsSync()) {
        debugPrint(
          'SherpaOnnxSpeechManager: model not found at $base\n'
          'Run: dart run tool/download_model.dart   (or download manually)',
        );
        return;
      }

      final config = sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          paraformer: sherpa.OnlineParaformerModelConfig(
            encoder: encoder,
            decoder: decoder,
          ),
          tokens: tokens,
          modelType: 'paraformer',
          numThreads: 2,
          debug: false,
        ),
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.4,
        rule2MinTrailingSilence: 1.4,
        rule3MinUtteranceLength: 20.0,
      );

      _recognizer = sherpa.OnlineRecognizer(config);
      _modelReady = true;
      debugPrint('SherpaOnnxSpeechManager: model loaded from $base');
    } catch (e, st) {
      debugPrint('SherpaOnnxSpeechManager: model init failed: $e\n$st');
    }
  }

  // ── Listening ──────────────────────────────────────────────────────────

  /// Start streaming recognition.
  Future<void> startListening(SpeechToTextListener listener) async {
    _listener = listener;
    _cancelled = false;
    _running = true;

    if (!_modelReady) {
      await prepareModel();
    }
    if (!_modelReady || _recognizer == null) {
      _running = false;
      listener.onError(SttErrorCodes.client);
      return;
    }

    final stream = _recognizer!.createStream();
    _mic = Win32Microphone();

    try {
      final audioStream = _mic!.start();

      listener.onReadyForSpeech();

      String lastPartial = '';

      _audioSub = audioStream.listen(
        (chunk) {
          if (!_running || _cancelled) return;

          final samples = _pcm16ToFloat32(chunk);
          stream.acceptWaveform(samples: samples, sampleRate: 16000);

          while (_recognizer!.isReady(stream)) {
            _recognizer!.decode(stream);
          }

          final result = _recognizer!.getResult(stream);
          final text = result.text.trim();

          if (text.isNotEmpty && text != lastPartial) {
            lastPartial = text;
            _listener?.onPartialResult(text);
          }

          if (_recognizer!.isEndpoint(stream)) {
            if (text.isNotEmpty) {
              _running = false;
              _stopRecording();
              _listener?.onFinalResult(text);
              _listener?.onEndOfSpeech();
            }
            _recognizer!.reset(stream);
            lastPartial = '';
          }
        },
        onError: (e) {
          debugPrint('SherpaOnnxSpeechManager: audio error: $e');
          _running = false;
          _stopRecording();
          _listener?.onError(SttErrorCodes.audio);
        },
        onDone: () {
          if (_running && !_cancelled) {
            final result = _recognizer!.getResult(stream);
            final text = result.text.trim();
            if (text.isNotEmpty) {
              _listener?.onFinalResult(text);
            }
          }
          _running = false;
          if (!_cancelled) {
            _listener?.onEndOfSpeech();
          }
          stream.free();
        },
      );
    } catch (e, st) {
      debugPrint('SherpaOnnxSpeechManager: start failed: $e\n$st');
      _running = false;
      listener.onError(SttErrorCodes.audio);
    }
  }

  /// Stop recognition gracefully.
  void stopListening() {
    _running = false;
    _stopRecording();
  }

  /// Cancel without delivering a result.
  void cancelListening() {
    _cancelled = true;
    _running = false;
    _stopRecording();
    _listener = null;
  }

  /// Release all native resources.
  void destroy() {
    cancelListening();
    _recognizer?.free();
    _recognizer = null;
    _modelReady = false;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<void> _stopRecording() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _mic?.stop();
    } catch (_) {}
    _mic = null;
  }

  /// Convert PCM16 little-endian bytes to normalized Float32 samples,
  /// identical to Android's `Short / 32768f` conversion.
  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final shortCount = bytes.length ~/ 2;
    final view = ByteData.sublistView(bytes);
    final out = Float32List(shortCount);
    for (var i = 0; i < shortCount; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}
