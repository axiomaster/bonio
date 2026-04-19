import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Callback for handling capability requests from a sidecar plugin.
///
/// The host implements this to dispatch `screen.capture`, `chat.send`, etc.
/// Returns a result map that will be sent back to the plugin.
typedef PluginCapabilityHandler = Future<Map<String, dynamic>> Function(
    String method, Map<String, dynamic> params);

/// Bidirectional JSON-RPC 2.0 bridge over stdin/stdout for sidecar plugins.
///
/// The host writes requests to the plugin's stdin and reads responses from
/// its stdout. Simultaneously, the plugin can send capability requests on
/// stdout which the host fulfills via [onRequest].
class PluginBridge {
  final IOSink stdin;
  final Stream<List<int>> stdout;
  final PluginCapabilityHandler onRequest;

  int _nextId = 1;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  StreamSubscription? _sub;

  PluginBridge({
    required this.stdin,
    required this.stdout,
    required this.onRequest,
  });

  /// Begin listening on the plugin's stdout for responses and requests.
  void listen() {
    _sub = stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (e) {
      debugPrint('PluginBridge: stdout error: $e');
    });
  }

  /// Send a JSON-RPC request to the plugin and wait for the response.
  Future<Map<String, dynamic>> sendRequest(String method,
      Map<String, dynamic> params) {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    _write({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('Plugin request $method timed out');
      },
    );
  }

  /// Send a JSON-RPC notification (no response expected).
  void sendNotification(String method, Map<String, dynamic> params) {
    _write({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  void _write(Map<String, dynamic> message) {
    try {
      stdin.writeln(jsonEncode(message));
    } catch (e) {
      debugPrint('PluginBridge: write error: $e');
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final data = jsonDecode(line) as Map<String, dynamic>;
      final id = data['id'];

      if (id is int && _pending.containsKey(id)) {
        // This is a response to our request
        final completer = _pending.remove(id)!;
        if (data.containsKey('error')) {
          completer.completeError(
              PluginRpcError.fromJson(data['error'] as Map<String, dynamic>));
        } else {
          completer
              .complete(data['result'] as Map<String, dynamic>? ?? {});
        }
      } else if (data.containsKey('method')) {
        // This is a capability request from the plugin
        _handlePluginRequest(data);
      }
    } catch (e) {
      debugPrint('PluginBridge: parse error: $e');
    }
  }

  Future<void> _handlePluginRequest(Map<String, dynamic> data) async {
    final method = data['method'] as String;
    final params = data['params'] as Map<String, dynamic>? ?? {};
    final id = data['id'];

    try {
      final result = await onRequest(method, params);
      if (id != null) {
        _write({
          'jsonrpc': '2.0',
          'id': id,
          'result': result,
        });
      }
    } catch (e) {
      if (id != null) {
        _write({
          'jsonrpc': '2.0',
          'id': id,
          'error': {
            'code': -32603,
            'message': e.toString(),
          },
        });
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('Bridge disposed'));
      }
    }
    _pending.clear();
  }
}

class PluginRpcError implements Exception {
  final int code;
  final String message;
  const PluginRpcError({required this.code, required this.message});

  factory PluginRpcError.fromJson(Map<String, dynamic> json) =>
      PluginRpcError(
        code: (json['code'] as num?)?.toInt() ?? -1,
        message: json['message'] as String? ?? 'Unknown error',
      );

  @override
  String toString() => 'PluginRpcError($code): $message';
}
