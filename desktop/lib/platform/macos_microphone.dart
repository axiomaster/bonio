import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'microphone.dart';

// ── CoreAudio / AudioToolbox constants ────────────────────────────────────────
const int _kAudioFormatLinearPCM = 0x6C70636D; // 'lpcm'
const int _kLinearPCMFormatFlagIsSignedInteger = 0x4;
const int _kLinearPCMFormatFlagIsPacked = 0x8;

// ── AudioStreamBasicDescription ──────────────────────────────────────────────
base class _AudioStreamBasicDescription extends Struct {
  @Double()
  external double mSampleRate;
  @Uint32()
  external int mFormatID;
  @Uint32()
  external int mFormatFlags;
  @Uint32()
  external int mBytesPerPacket;
  @Uint32()
  external int mFramesPerPacket;
  @Uint32()
  external int mBytesPerFrame;
  @Uint32()
  external int mChannelsPerFrame;
  @Uint32()
  external int mBitsPerChannel;
  @Uint32()
  external int mReserved;
}

// ── AudioQueueBuffer ─────────────────────────────────────────────────────────
base class _AudioQueueBuffer extends Struct {
  @Uint32()
  external int mAudioDataBytesCapacity;
  external Pointer<Uint8> mAudioData;
  @Uint32()
  external int mAudioDataByteSize;
  external Pointer<Void> mUserData;
  @Uint32()
  external int mPacketDescriptionCapacity;
  external Pointer<Void> mPacketDescriptions;
  @Uint32()
  external int mPacketDescriptionCount;
}

// ── Native callback signature ────────────────────────────────────────────────
typedef _AudioQueueInputCallbackNative = Void Function(
  Pointer<Void> inUserData,
  Pointer<Void> inAQ,
  Pointer<_AudioQueueBuffer> inBuffer,
  Pointer<Void> inStartTime,
  Uint32 inNumberPacketDescriptions,
  Pointer<Void> inPacketDescs,
);

// ── Native function typedefs ─────────────────────────────────────────────────
typedef _AudioQueueNewInputNative = Int32 Function(
  Pointer<_AudioStreamBasicDescription> inFormat,
  Pointer<NativeFunction<_AudioQueueInputCallbackNative>> inCallbackProc,
  Pointer<Void> inUserData,
  Pointer<Void> inCallbackRunLoop,
  Pointer<Void> inCallbackRunLoopMode,
  Uint32 inFlags,
  Pointer<Pointer<Void>> outAQ,
);
typedef _AudioQueueNewInputDart = int Function(
  Pointer<_AudioStreamBasicDescription> inFormat,
  Pointer<NativeFunction<_AudioQueueInputCallbackNative>> inCallbackProc,
  Pointer<Void> inUserData,
  Pointer<Void> inCallbackRunLoop,
  Pointer<Void> inCallbackRunLoopMode,
  int inFlags,
  Pointer<Pointer<Void>> outAQ,
);

typedef _AudioQueueAllocateBufferNative = Int32 Function(
  Pointer<Void> inAQ, Uint32 inBufferByteSize, Pointer<Pointer<_AudioQueueBuffer>> outBuffer);
typedef _AudioQueueAllocateBufferDart = int Function(
  Pointer<Void> inAQ, int inBufferByteSize, Pointer<Pointer<_AudioQueueBuffer>> outBuffer);

typedef _AudioQueueEnqueueBufferNative = Int32 Function(
  Pointer<Void> inAQ, Pointer<_AudioQueueBuffer> inBuffer, Uint32 inNumPacketDescs, Pointer<Void> inPacketDescs);
typedef _AudioQueueEnqueueBufferDart = int Function(
  Pointer<Void> inAQ, Pointer<_AudioQueueBuffer> inBuffer, int inNumPacketDescs, Pointer<Void> inPacketDescs);

typedef _AudioQueueStartNative = Int32 Function(Pointer<Void> inAQ, Pointer<Void> inStartTime);
typedef _AudioQueueStartDart = int Function(Pointer<Void> inAQ, Pointer<Void> inStartTime);

typedef _AudioQueueStopNative = Int32 Function(Pointer<Void> inAQ, Uint8 inImmediate);
typedef _AudioQueueStopDart = int Function(Pointer<Void> inAQ, int inImmediate);

typedef _AudioQueueDisposeNative = Int32 Function(Pointer<Void> inAQ, Uint8 inImmediate);
typedef _AudioQueueDisposeDart = int Function(Pointer<Void> inAQ, int inImmediate);

// ── Load AudioToolbox (lazy) ─────────────────────────────────────────────────
late final DynamicLibrary _audioToolbox = DynamicLibrary.open(
  '/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox',
);

late final _audioQueueNewInput = _audioToolbox
    .lookupFunction<_AudioQueueNewInputNative, _AudioQueueNewInputDart>('AudioQueueNewInput');
late final _audioQueueAllocateBuffer = _audioToolbox
    .lookupFunction<_AudioQueueAllocateBufferNative, _AudioQueueAllocateBufferDart>('AudioQueueAllocateBuffer');
late final _audioQueueEnqueueBuffer = _audioToolbox
    .lookupFunction<_AudioQueueEnqueueBufferNative, _AudioQueueEnqueueBufferDart>('AudioQueueEnqueueBuffer');
late final _audioQueueStart = _audioToolbox
    .lookupFunction<_AudioQueueStartNative, _AudioQueueStartDart>('AudioQueueStart');
late final _audioQueueStop = _audioToolbox
    .lookupFunction<_AudioQueueStopNative, _AudioQueueStopDart>('AudioQueueStop');
late final _audioQueueDispose = _audioToolbox
    .lookupFunction<_AudioQueueDisposeNative, _AudioQueueDisposeDart>('AudioQueueDispose');

/// Streams 16-bit PCM audio from the default microphone at 16 kHz mono on macOS.
///
/// Uses AudioQueue (AudioToolbox) via dart:ffi.  The input callback is created
/// with [NativeCallable.listener] so it is safely invoked from AudioQueue's
/// internal thread and dispatched back to the Dart isolate event loop.
class MacOsMicrophone implements PlatformMicrophone {
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _bitsPerSample = 16;
  static const int _bufferCount = 4;
  static const int _bufferBytes =
      (_sampleRate * _channels * (_bitsPerSample ~/ 8)) ~/ 10; // ~100ms

  Pointer<Void>? _queue;
  bool _running = false;
  StreamController<Uint8List>? _controller;

  NativeCallable<_AudioQueueInputCallbackNative>? _nativeCallback;

  /// Called on the Dart isolate thread (posted by NativeCallable.listener).
  /// The buffer is still owned by us until we re-enqueue it, so reading is safe.
  void _onAudioData(
    Pointer<Void> inUserData,
    Pointer<Void> inAQ,
    Pointer<_AudioQueueBuffer> inBuffer,
    Pointer<Void> inStartTime,
    int inNumberPacketDescriptions,
    Pointer<Void> inPacketDescs,
  ) {
    if (!_running) return;

    final size = inBuffer.ref.mAudioDataByteSize;
    if (size > 0) {
      final copy = Uint8List(size);
      final src = inBuffer.ref.mAudioData;
      for (var i = 0; i < size; i++) {
        copy[i] = src[i];
      }
      _controller?.add(copy);
    }

    // Re-enqueue the buffer for continuous recording.
    if (_running && _queue != null) {
      _audioQueueEnqueueBuffer(_queue!, inBuffer, 0, nullptr);
    }
  }

  @override
  Stream<Uint8List> start() {
    if (_running) throw StateError('MacOsMicrophone already running');

    _controller = StreamController<Uint8List>();

    // NativeCallable.listener: the native AudioQueue thread invokes the
    // function pointer; Dart posts the call to our isolate's event loop.
    _nativeCallback = NativeCallable<_AudioQueueInputCallbackNative>.listener(
      _onAudioData,
    );

    final format = calloc<_AudioStreamBasicDescription>();
    format.ref.mSampleRate = _sampleRate.toDouble();
    format.ref.mFormatID = _kAudioFormatLinearPCM;
    format.ref.mFormatFlags =
        _kLinearPCMFormatFlagIsSignedInteger | _kLinearPCMFormatFlagIsPacked;
    format.ref.mBytesPerPacket = _channels * (_bitsPerSample ~/ 8);
    format.ref.mFramesPerPacket = 1;
    format.ref.mBytesPerFrame = _channels * (_bitsPerSample ~/ 8);
    format.ref.mChannelsPerFrame = _channels;
    format.ref.mBitsPerChannel = _bitsPerSample;
    format.ref.mReserved = 0;

    final queuePtr = calloc<Pointer<Void>>();

    final status = _audioQueueNewInput(
      format,
      _nativeCallback!.nativeFunction,
      nullptr,
      nullptr,
      nullptr,
      0,
      queuePtr,
    );
    if (status != 0) {
      calloc.free(format);
      calloc.free(queuePtr);
      _nativeCallback!.close();
      _nativeCallback = null;
      debugPrint('MacOsMicrophone: AudioQueueNewInput failed ($status)');
      _controller!.addError('AudioQueueNewInput failed: $status');
      _controller!.close();
      return _controller!.stream;
    }

    _queue = queuePtr.value;
    calloc.free(format);
    calloc.free(queuePtr);

    final bufPtr = calloc<Pointer<_AudioQueueBuffer>>();
    for (var i = 0; i < _bufferCount; i++) {
      _audioQueueAllocateBuffer(_queue!, _bufferBytes, bufPtr);
      _audioQueueEnqueueBuffer(_queue!, bufPtr.value, 0, nullptr);
    }
    calloc.free(bufPtr);

    _running = true;
    _audioQueueStart(_queue!, nullptr);

    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    if (_queue != null) {
      _audioQueueStop(_queue!, 1);
      _audioQueueDispose(_queue!, 1);
      _queue = null;
    }

    _nativeCallback?.close();
    _nativeCallback = null;

    await _controller?.close();
    _controller = null;
  }
}
