import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// ── Win32 waveIn constants ────────────────────────────────────────────────────
const int _WAVE_FORMAT_PCM = 0x0001;
const int _CALLBACK_NULL = 0x00000000;
const int _WAVE_MAPPER = 0xFFFFFFFF;
const int _WHDR_DONE = 0x00000001;

// ── Win32 waveIn structures ──────────────────────────────────────────────────

/// WAVEFORMATEX
base class _WAVEFORMATEX extends Struct {
  @Uint16()
  external int wFormatTag;
  @Uint16()
  external int nChannels;
  @Uint32()
  external int nSamplesPerSec;
  @Uint32()
  external int nAvgBytesPerSec;
  @Uint16()
  external int nBlockAlign;
  @Uint16()
  external int wBitsPerSample;
  @Uint16()
  external int cbSize;
}

/// WAVEHDR
base class _WAVEHDR extends Struct {
  external Pointer<Uint8> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  @IntPtr()
  external int dwUser;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwLoops;
  external Pointer<_WAVEHDR> lpNext;
  @IntPtr()
  external int reserved;
}

// ── Win32 waveIn function typedefs ───────────────────────────────────────────

typedef _WaveInOpenNative = Uint32 Function(
    Pointer<IntPtr> phwi,
    Uint32 uDeviceID,
    Pointer<_WAVEFORMATEX> pwfx,
    IntPtr dwCallback,
    IntPtr dwInstance,
    Uint32 fdwOpen);
typedef _WaveInOpenDart = int Function(Pointer<IntPtr> phwi, int uDeviceID,
    Pointer<_WAVEFORMATEX> pwfx, int dwCallback, int dwInstance, int fdwOpen);

typedef _WaveInSimpleNative = Uint32 Function(IntPtr hwi);
typedef _WaveInSimpleDart = int Function(int hwi);

typedef _WaveInHdrNative = Uint32 Function(
    IntPtr hwi, Pointer<_WAVEHDR> pwh, Uint32 cbwh);
typedef _WaveInHdrDart = int Function(
    int hwi, Pointer<_WAVEHDR> pwh, int cbwh);

// ── Loaded Win32 functions ──────────────────────────────────────────────────

final _winmm = DynamicLibrary.open('winmm.dll');

final _waveInOpen =
    _winmm.lookupFunction<_WaveInOpenNative, _WaveInOpenDart>('waveInOpen');
final _waveInPrepareHeader =
    _winmm.lookupFunction<_WaveInHdrNative, _WaveInHdrDart>(
        'waveInPrepareHeader');
final _waveInUnprepareHeader =
    _winmm.lookupFunction<_WaveInHdrNative, _WaveInHdrDart>(
        'waveInUnprepareHeader');
final _waveInAddBuffer =
    _winmm.lookupFunction<_WaveInHdrNative, _WaveInHdrDart>('waveInAddBuffer');
final _waveInStart =
    _winmm.lookupFunction<_WaveInSimpleNative, _WaveInSimpleDart>(
        'waveInStart');
final _waveInStop =
    _winmm.lookupFunction<_WaveInSimpleNative, _WaveInSimpleDart>('waveInStop');
final _waveInReset =
    _winmm.lookupFunction<_WaveInSimpleNative, _WaveInSimpleDart>(
        'waveInReset');
final _waveInClose =
    _winmm.lookupFunction<_WaveInSimpleNative, _WaveInSimpleDart>(
        'waveInClose');

// ── Public API ──────────────────────────────────────────────────────────────

/// Streams 16-bit PCM audio from the default microphone at 16 kHz mono.
///
/// Uses Win32 waveIn API via dart:ffi with CALLBACK_NULL (polling mode) —
/// no native-thread callbacks that would crash the Dart VM, and no Flutter
/// platform channels, so it works correctly with multiple Flutter engines.
class Win32Microphone {
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _bitsPerSample = 16;
  static const int _bufferCount = 4;
  static const int _bufferBytes =
      (_sampleRate * _channels * (_bitsPerSample ~/ 8)) ~/ 10; // ~100ms

  int _hwi = 0;
  bool _running = false;
  Timer? _pollTimer;

  final Pointer<IntPtr> _phwi = calloc<IntPtr>();
  final Pointer<_WAVEFORMATEX> _wfx = calloc<_WAVEFORMATEX>();
  final List<Pointer<_WAVEHDR>> _headers = [];
  final List<Pointer<Uint8>> _dataBuffers = [];

  StreamController<Uint8List>? _controller;

  /// Start recording. Returns a stream of raw PCM16 little-endian byte chunks.
  Stream<Uint8List> start() {
    if (_running) {
      throw StateError('Win32Microphone already running');
    }

    _controller = StreamController<Uint8List>();

    _wfx.ref.wFormatTag = _WAVE_FORMAT_PCM;
    _wfx.ref.nChannels = _channels;
    _wfx.ref.nSamplesPerSec = _sampleRate;
    _wfx.ref.wBitsPerSample = _bitsPerSample;
    _wfx.ref.nBlockAlign = _channels * (_bitsPerSample ~/ 8);
    _wfx.ref.nAvgBytesPerSec = _sampleRate * _wfx.ref.nBlockAlign;
    _wfx.ref.cbSize = 0;

    // CALLBACK_NULL: no callback at all — we poll WHDR_DONE flags instead.
    final result = _waveInOpen(
      _phwi,
      _WAVE_MAPPER,
      _wfx,
      0,
      0,
      _CALLBACK_NULL,
    );
    if (result != 0) {
      debugPrint('Win32Microphone: waveInOpen failed ($result)');
      _controller!.addError('waveInOpen failed: $result');
      _controller!.close();
      return _controller!.stream;
    }
    _hwi = _phwi.value;

    for (var i = 0; i < _bufferCount; i++) {
      final data = calloc<Uint8>(_bufferBytes);
      final hdr = calloc<_WAVEHDR>();
      hdr.ref.lpData = data;
      hdr.ref.dwBufferLength = _bufferBytes;
      hdr.ref.dwBytesRecorded = 0;
      hdr.ref.dwUser = 0;
      hdr.ref.dwFlags = 0;
      hdr.ref.dwLoops = 0;

      _waveInPrepareHeader(_hwi, hdr, sizeOf<_WAVEHDR>());
      _waveInAddBuffer(_hwi, hdr, sizeOf<_WAVEHDR>());

      _headers.add(hdr);
      _dataBuffers.add(data);
    }

    _running = true;
    _waveInStart(_hwi);

    // Poll buffer flags every 20ms from the Dart isolate thread — safe.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _pollBuffers();
    });

    return _controller!.stream;
  }

  /// Check each buffer header for WHDR_DONE; copy data and re-queue.
  void _pollBuffers() {
    for (final hdr in _headers) {
      if ((hdr.ref.dwFlags & _WHDR_DONE) != 0) {
        final recorded = hdr.ref.dwBytesRecorded;
        if (recorded > 0 && _running) {
          final bytes = Uint8List(recorded);
          for (var i = 0; i < recorded; i++) {
            bytes[i] = hdr.ref.lpData[i];
          }
          _controller?.add(bytes);
        }

        if (_running) {
          hdr.ref.dwBytesRecorded = 0;
          hdr.ref.dwFlags = 0;
          _waveInPrepareHeader(_hwi, hdr, sizeOf<_WAVEHDR>());
          _waveInAddBuffer(_hwi, hdr, sizeOf<_WAVEHDR>());
        }
      }
    }
  }

  /// Stop recording and free resources.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _pollTimer?.cancel();
    _pollTimer = null;

    _waveInStop(_hwi);
    _waveInReset(_hwi);

    for (final hdr in _headers) {
      _waveInUnprepareHeader(_hwi, hdr, sizeOf<_WAVEHDR>());
    }
    _waveInClose(_hwi);
    _hwi = 0;

    for (final hdr in _headers) {
      calloc.free(hdr);
    }
    for (final data in _dataBuffers) {
      calloc.free(data);
    }
    _headers.clear();
    _dataBuffers.clear();

    await _controller?.close();
    _controller = null;
  }
}
