import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Lightweight Chrome DevTools Protocol client over WebSocket.
///
/// Sends JSON-RPC style commands and receives responses/events.
/// Each command gets a unique incrementing `id`; the response with
/// the same `id` completes the corresponding [Completer].
class CdpClient {
  WebSocket? _ws;
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _eventController =
      StreamController<CdpEvent>.broadcast();
  StreamSubscription? _wsSub;

  bool get isConnected => _ws != null;
  Stream<CdpEvent> get events => _eventController.stream;

  Future<void> connect(String wsUrl) async {
    await disconnect();
    _ws = await WebSocket.connect(wsUrl);
    _wsSub = _ws!.listen(
      _onMessage,
      onDone: _onDone,
      onError: (e) => debugPrint('CdpClient ws error: $e'),
    );
    debugPrint('CdpClient: connected to $wsUrl');
  }

  Future<void> disconnect() async {
    _wsSub?.cancel();
    _wsSub = null;
    final ws = _ws;
    _ws = null;
    if (ws != null) {
      try {
        await ws.close();
      } catch (_) {}
    }
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('CDP connection closed'));
      }
    }
    _pending.clear();
  }

  /// Send a CDP command and wait for its response.
  Future<Map<String, dynamic>> sendCommand(String method,
      [Map<String, dynamic>? params]) async {
    final ws = _ws;
    if (ws == null) throw StateError('Not connected');

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final msg = jsonEncode({
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });
    ws.add(msg);

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('CDP command $method timed out');
      },
    );
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final id = data['id'] as int?;

      if (id != null && _pending.containsKey(id)) {
        final completer = _pending.remove(id)!;
        if (data.containsKey('error')) {
          completer.completeError(CdpError.fromJson(
              data['error'] as Map<String, dynamic>));
        } else {
          completer.complete(data['result'] as Map<String, dynamic>? ?? {});
        }
      } else if (data.containsKey('method')) {
        _eventController.add(CdpEvent(
          method: data['method'] as String,
          params: data['params'] as Map<String, dynamic>? ?? {},
        ));
      }
    } catch (e) {
      debugPrint('CdpClient: parse error: $e');
    }
  }

  void _onDone() {
    debugPrint('CdpClient: connection closed by remote');
    _ws = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('CDP connection closed'));
      }
    }
    _pending.clear();
  }
}

class CdpEvent {
  final String method;
  final Map<String, dynamic> params;
  const CdpEvent({required this.method, required this.params});
}

class CdpError implements Exception {
  final int code;
  final String message;
  const CdpError({required this.code, required this.message});

  factory CdpError.fromJson(Map<String, dynamic> json) => CdpError(
        code: (json['code'] as num?)?.toInt() ?? -1,
        message: json['message'] as String? ?? 'Unknown CDP error',
      );

  @override
  String toString() => 'CdpError($code): $message';
}
