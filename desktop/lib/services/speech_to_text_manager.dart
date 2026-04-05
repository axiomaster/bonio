import 'package:flutter/foundation.dart';

import 'sherpa_speech_manager.dart';

/// Callback interface matching Android's `SpeechToTextManager.Listener`.
///
/// Desktop uses Sherpa-ONNX only (no system STT fallback), but the contract
/// is identical so higher-level code (AppState, avatar, chat composer) can be
/// written once for both platforms.
abstract class SpeechToTextListener {
  void onPartialResult(String text);
  void onFinalResult(String text);
  void onError(int errorCode);
  void onReadyForSpeech();
  void onEndOfSpeech();
}

/// Convenience implementation that delegates to individual callbacks.
class SpeechToTextCallbacks implements SpeechToTextListener {
  final void Function(String text)? partial;
  final void Function(String text)? final_;
  final void Function(int code)? error;
  final VoidCallback? ready;
  final VoidCallback? end;

  const SpeechToTextCallbacks({
    this.partial,
    this.final_,
    this.error,
    this.ready,
    this.end,
  });

  @override
  void onPartialResult(String text) => partial?.call(text);
  @override
  void onFinalResult(String text) => final_?.call(text);
  @override
  void onError(int errorCode) => error?.call(errorCode);
  @override
  void onReadyForSpeech() => ready?.call();
  @override
  void onEndOfSpeech() => end?.call();
}

/// Android-compatible error codes (mirrors `SpeechRecognizer.ERROR_*`).
abstract final class SttErrorCodes {
  static const int audio = 3;
  static const int client = 5;
  static const int noMatch = 7;
}

/// Desktop STT orchestrator mirroring Android's `SpeechToTextManager`.
///
/// On desktop there is no system `SpeechRecognizer` — we go directly to
/// Sherpa-ONNX streaming paraformer.  The public API is identical so that
/// `AppState` / avatar / chat code can be shared across platforms.
class SpeechToTextManager {
  SpeechToTextManager();

  SherpaOnnxSpeechManager? _sherpa;
  bool _listening = false;

  bool get isListening => _listening;

  /// Pre-load the ONNX model in the background so the first
  /// `startListening` call is fast.  Safe to call multiple times.
  Future<void> warmUp() async {
    _sherpa ??= SherpaOnnxSpeechManager();
    await _sherpa!.prepareModel();
  }

  /// Begin streaming recognition.  Only one session at a time.
  void startListening(SpeechToTextListener listener) {
    if (_listening) {
      debugPrint('SpeechToTextManager: already listening, ignoring');
      return;
    }
    _listening = true;
    _sherpa ??= SherpaOnnxSpeechManager();

    final wrapped = SpeechToTextCallbacks(
      partial: listener.onPartialResult,
      final_: (text) {
        _listening = false;
        listener.onFinalResult(text);
      },
      error: (code) {
        _listening = false;
        listener.onError(code);
      },
      ready: listener.onReadyForSpeech,
      end: () {
        _listening = false;
        listener.onEndOfSpeech();
      },
    );

    _sherpa!.startListening(wrapped);
  }

  /// Stop recognition gracefully (delivers final result if available).
  void stopListening() {
    if (!_listening) return;
    _sherpa?.stopListening();
  }

  /// Cancel recognition without delivering a result.
  void cancelListening() {
    _listening = false;
    _sherpa?.cancelListening();
  }

  /// Release all native resources.
  void destroy() {
    cancelListening();
    _sherpa?.destroy();
    _sherpa = null;
  }
}
