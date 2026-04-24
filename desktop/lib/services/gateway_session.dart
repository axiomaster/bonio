import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../l10n/app_strings.dart';
import '../models/gateway_models.dart';
import '../models/device_identity.dart';
import 'app_logger.dart';
import 'device_identity_store.dart';
import 'device_auth_store.dart';

const int gatewayProtocolVersion = 3;

String? _decodeWsFrameText(dynamic data) {
  if (data is String) return data;
  if (data is Uint8List) return utf8.decode(data);
  if (data is List<int>) return utf8.decode(data);
  return null;
}

class ErrorShape {
  final String code;
  final String message;
  const ErrorShape({required this.code, required this.message});
}

class InvokeRequest {
  final String id;
  final String nodeId;
  final String command;
  final String? paramsJson;
  final int? timeoutMs;
  const InvokeRequest({
    required this.id,
    required this.nodeId,
    required this.command,
    this.paramsJson,
    this.timeoutMs,
  });
}

class InvokeResult {
  final bool ok;
  final String? payloadJson;
  final ErrorShape? error;
  const InvokeResult({required this.ok, this.payloadJson, this.error});
  factory InvokeResult.success(String? payloadJson) =>
      InvokeResult(ok: true, payloadJson: payloadJson);
  factory InvokeResult.fail(String code, String message) =>
      InvokeResult(ok: false, error: ErrorShape(code: code, message: message));
}

class _RpcResponse {
  final String id;
  final bool ok;
  final String? payloadJson;
  final ErrorShape? error;
  const _RpcResponse({
    required this.id,
    required this.ok,
    this.payloadJson,
    this.error,
  });
}

typedef InvokeHandler = Future<InvokeResult> Function(InvokeRequest request);
typedef EventHandler = void Function(String event, String? payloadJson);
typedef ConnectedCallback = void Function(
    String? serverName, String? remoteAddress, String? mainSessionKey);
typedef DisconnectedCallback = void Function(String message);

class GatewaySession {
  final DeviceIdentityStore identityStore;
  final DeviceAuthStore deviceAuthStore;
  final ConnectedCallback onConnected;
  final DisconnectedCallback onDisconnected;
  final EventHandler onEvent;
  final InvokeHandler? onInvoke;

  static const _connectRpcTimeoutMs = 12000;
  static const _uuid = Uuid();

  final Map<String, Completer<_RpcResponse>> _pending = {};
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isRunning = false;
  Completer<String>? _connectNonceCompleter;
  String? _mainSessionKey;
  bool _disposed = false;

  _DesiredConnection? _desired;
  int _attempt = 0;

  GatewaySession({
    required this.identityStore,
    required this.deviceAuthStore,
    required this.onConnected,
    required this.onDisconnected,
    required this.onEvent,
    this.onInvoke,
  });

  String? get mainSessionKey => _mainSessionKey;
  bool get isConnected => _channel != null && !_disposed;

  void connect({
    required GatewayEndpoint endpoint,
    String? token,
    String? password,
    required GatewayConnectOptions options,
  }) {
    _desired = _DesiredConnection(
      endpoint: endpoint,
      token: token,
      password: password,
      options: options,
    );
    if (!_isRunning) {
      _isRunning = true;
      _runLoop();
    }
  }

  void disconnect() {
    _desired = null;
    _closeQuietly();
    _mainSessionKey = null;
    onDisconnected(S.current.statusOffline);
  }

  void reconnect() {
    _closeQuietly();
  }

  Future<String> request(String method, String? paramsJson,
      {int timeoutMs = 15000}) async {
    if (_channel == null) {
      throw StateError('not connected');
    }
    final params = paramsJson != null && paramsJson.trim().isNotEmpty
        ? jsonDecode(paramsJson)
        : null;
    final res = await _sendRequest(method, params, timeoutMs: timeoutMs);
    if (res.ok) return res.payloadJson ?? '';
    final err = res.error;
    throw StateError(
        '${err?.code ?? "UNAVAILABLE"}: ${err?.message ?? "request failed"}');
  }

  Future<bool> sendNodeEvent(String event, String? payloadJson) async {
    if (_channel == null) return false;
    dynamic parsedPayload;
    if (payloadJson != null) {
      try {
        parsedPayload = jsonDecode(payloadJson);
      } catch (_) {
        parsedPayload = null;
      }
    }
    final params = <String, dynamic>{'event': event};
    if (parsedPayload != null) {
      params['payload'] = parsedPayload;
    } else if (payloadJson != null) {
      params['payloadJSON'] = payloadJson;
    } else {
      params['payloadJSON'] = null;
    }
    try {
      await _sendRequest('node.event', params, timeoutMs: 8000);
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _desired = null;
    _closeQuietly();
    _failPending();
  }

  // -- Internal --

  Future<void> _runLoop() async {
    _attempt = 0;
    while (!_disposed) {
      final target = _desired;
      if (target == null) {
        _closeQuietly();
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }
      try {
        onDisconnected(_attempt == 0 ? S.current.statusConnecting : S.current.statusReconnecting);
        await _connectOnce(target);
        _attempt = 0;
      } catch (err) {
        _attempt++;
        onDisconnected('Gateway error: $err');
        final sleepMs =
            min(8000, (350.0 * pow(1.7, _attempt.toDouble())).toInt());
        await Future.delayed(Duration(milliseconds: sleepMs));
      }
    }
    _isRunning = false;
  }

  Future<void> _connectOnce(_DesiredConnection target) async {
    final scheme = target.endpoint.tlsEnabled ? 'wss' : 'ws';
    final url = '$scheme://${target.endpoint.host}:${target.endpoint.port}';

    _connectNonceCompleter = Completer<String>();
    _channel = WebSocketChannel.connect(Uri.parse(url));

    final completer = Completer<void>();

    _subscription = _channel!.stream.listen(
      (data) {
        final text = _decodeWsFrameText(data);
        if (text == null) {
          log.warn('gateway: dropped non-text WebSocket frame (${data.runtimeType})');
          return;
        }
        _handleMessage(text, target, completer);
      },
      onError: (err) {
        if (!completer.isCompleted) {
          completer.completeError(err);
        }
        _failPending();
        _channel = null;
        onDisconnected('Gateway error: $err');
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('connection closed'));
        }
        _failPending();
        _channel = null;
      },
      cancelOnError: false,
    );

    // Wait for connect.challenge then send connect
    try {
      // OpenClaw gateway may be slow to emit connect.challenge; official client uses ~6–12s.
      final nonce = await _connectNonceCompleter!.future
          .timeout(const Duration(seconds: 12));
      await _sendConnect(nonce, target);
      // Keep connection alive until closed
      await completer.future;
    } catch (e) {
      _closeQuietly();
      rethrow;
    }
  }

  void _handleMessage(
      String text, _DesiredConnection target, Completer<void> sessionCompleter) {
    try {
      final frame = jsonDecode(text) as Map<String, dynamic>;
      final type = frame['type'] as String?;
      switch (type) {
        case 'res':
          _handleResponse(frame);
          break;
        case 'event':
          _handleEvent(frame);
          break;
        default:
          break;
      }
    } catch (e, st) {
      log.error('gateway: frame decode error: $e');
      log.debug('$st');
      final preview =
          text.length > 200 ? '${text.substring(0, 200)}...' : text;
      log.debug('gateway: frame preview: $preview');
    }
  }

  void _handleResponse(Map<String, dynamic> frame) {
    final id = frame['id'] as String?;
    if (id == null) return;
    final ok = frame['ok'] as bool? ?? false;
    final payloadJson =
        frame['payload'] != null ? jsonEncode(frame['payload']) : null;
    ErrorShape? error;
    if (frame['error'] is Map<String, dynamic>) {
      final errObj = frame['error'] as Map<String, dynamic>;
      error = ErrorShape(
        code: errObj['code'] as String? ?? 'UNAVAILABLE',
        message: errObj['message'] as String? ?? 'request failed',
      );
    }
    final completer = _pending.remove(id);
    completer?.complete(
        _RpcResponse(id: id, ok: ok, payloadJson: payloadJson, error: error));
  }

  void _handleEvent(Map<String, dynamic> frame) {
    final event = frame['event'] as String?;
    if (event == null) return;
    final payloadJson = frame['payload'] != null
        ? jsonEncode(frame['payload'])
        : frame['payloadJSON'] as String?;

    if (event == 'connect.challenge') {
      final nonce = _extractConnectNonce(payloadJson);
      if (nonce != null &&
          nonce.isNotEmpty &&
          _connectNonceCompleter != null &&
          !_connectNonceCompleter!.isCompleted) {
        _connectNonceCompleter!.complete(nonce.trim());
      }
      return;
    }

    if (event == 'node.invoke.request' && payloadJson != null && onInvoke != null) {
      _handleInvokeEvent(payloadJson);
      return;
    }

    onEvent(event, payloadJson);
  }

  String? _extractConnectNonce(String? payloadJson) {
    if (payloadJson == null || payloadJson.isEmpty) return null;
    try {
      final obj = jsonDecode(payloadJson) as Map<String, dynamic>;
      return obj['nonce'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleInvokeEvent(String payloadJson) async {
    try {
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      final id = payload['id'] as String?;
      final nodeId = payload['nodeId'] as String?;
      final command = payload['command'] as String?;
      if (id == null || nodeId == null || command == null) return;

      final params = payload['paramsJSON'] as String? ??
          (payload['params'] != null ? jsonEncode(payload['params']) : null);
      final timeoutMs = payload['timeoutMs'] as int?;

      final request = InvokeRequest(
        id: id,
        nodeId: nodeId,
        command: command,
        paramsJson: params,
        timeoutMs: timeoutMs,
      );

      InvokeResult result;
      try {
        result = await onInvoke!(request);
      } catch (err) {
        result = InvokeResult.fail('INTERNAL', err.toString());
      }
      await _sendInvokeResult(id, nodeId, result, timeoutMs);
    } catch (_) {}
  }

  Future<void> _sendInvokeResult(
      String id, String nodeId, InvokeResult result, int? invokeTimeoutMs) async {
    dynamic parsedPayload;
    if (result.payloadJson != null) {
      try {
        parsedPayload = jsonDecode(result.payloadJson!);
      } catch (_) {}
    }

    final params = <String, dynamic>{
      'id': id,
      'nodeId': nodeId,
      'ok': result.ok,
    };
    if (parsedPayload != null) {
      params['payload'] = parsedPayload;
    } else if (result.payloadJson != null) {
      params['payloadJSON'] = result.payloadJson;
    }
    if (result.error != null) {
      params['error'] = {
        'code': result.error!.code,
        'message': result.error!.message,
      };
    }

    final ackTimeout = _resolveInvokeResultAckTimeout(invokeTimeoutMs);
    try {
      await _sendRequest('node.invoke.result', params,
          timeoutMs: ackTimeout);
    } catch (_) {}
  }

  int _resolveInvokeResultAckTimeout(int? invokeTimeoutMs) {
    final normalized = (invokeTimeoutMs != null && invokeTimeoutMs > 0)
        ? invokeTimeoutMs
        : 15000;
    return normalized.clamp(15000, 120000);
  }

  Future<void> _sendConnect(String nonce, _DesiredConnection target) async {
    final identity = await identityStore.loadOrCreate();
    final storedToken =
        await deviceAuthStore.loadToken(identity.deviceId, target.options.role);
    final trimmedToken = target.token?.trim() ?? '';
    final authToken =
        trimmedToken.isNotEmpty ? trimmedToken : (storedToken ?? '');
    final payload = await _buildConnectParams(
        identity, nonce, authToken, target.password?.trim(), target.options);
    final res =
        await _sendRequest('connect', payload, timeoutMs: _connectRpcTimeoutMs);
    if (!res.ok) {
      throw StateError(res.error?.message ?? 'connect failed');
    }
    _handleConnectSuccess(res, identity.deviceId, target);
  }

  void _handleConnectSuccess(
      _RpcResponse res, String deviceId, _DesiredConnection target) {
    if (res.payloadJson == null) throw StateError('connect failed: missing payload');
    final obj = jsonDecode(res.payloadJson!) as Map<String, dynamic>;
    final serverObj = obj['server'] as Map<String, dynamic>?;
    final serverName = serverObj?['host'] as String?;
    final authObj = obj['auth'] as Map<String, dynamic>?;
    final deviceToken = authObj?['deviceToken'] as String?;
    final authRole =
        authObj?['role'] as String? ?? target.options.role;
    if (deviceToken != null && deviceToken.isNotEmpty) {
      deviceAuthStore.saveToken(deviceId, authRole, deviceToken);
    }
    final snapshot = obj['snapshot'] as Map<String, dynamic>?;
    final sessionDefaults =
        snapshot?['sessionDefaults'] as Map<String, dynamic>?;
    _mainSessionKey = sessionDefaults?['mainSessionKey'] as String?;

    final remoteAddress =
        '${target.endpoint.host}:${target.endpoint.port}';
    onConnected(serverName, remoteAddress, _mainSessionKey);
  }

  Future<Map<String, dynamic>> _buildConnectParams(
    DeviceIdentity identity,
    String connectNonce,
    String authToken,
    String? authPassword,
    GatewayConnectOptions options,
  ) async {
    final clientJson = options.client.toJson();
    final signedAtMs = DateTime.now().millisecondsSinceEpoch;

    Map<String, dynamic>? authJson;
    final password = authPassword?.trim() ?? '';
    if (authToken.isNotEmpty) {
      authJson = {'token': authToken};
    } else if (password.isNotEmpty) {
      authJson = {'password': password};
    }

    final payloadString = DeviceAuthPayload.buildV3(
      deviceId: identity.deviceId,
      clientId: options.client.id,
      clientMode: options.client.mode,
      role: options.role,
      scopes: options.scopes,
      signedAtMs: signedAtMs,
      token: authToken.isNotEmpty ? authToken : null,
      nonce: connectNonce,
      platform: options.client.platform,
      deviceFamily: options.client.deviceFamily,
    );

    final signature =
        await identityStore.signPayload(payloadString, identity);
    final publicKey = identityStore.publicKeyBase64Url(identity);

    Map<String, dynamic>? deviceJson;
    if (signature != null && publicKey != null) {
      deviceJson = {
        'id': identity.deviceId,
        'publicKey': publicKey,
        'signature': signature,
        'signedAt': signedAtMs,
        'nonce': connectNonce,
      };
    }

    final params = <String, dynamic>{
      'minProtocol': gatewayProtocolVersion,
      'maxProtocol': gatewayProtocolVersion,
      'client': clientJson,
      'role': options.role,
      'locale': 'en',
    };
    if (options.caps.isNotEmpty) params['caps'] = options.caps;
    if (options.commands.isNotEmpty) params['commands'] = options.commands;
    if (options.permissions.isNotEmpty) params['permissions'] = options.permissions;
    if (options.scopes.isNotEmpty) params['scopes'] = options.scopes;
    if (authJson != null) params['auth'] = authJson;
    if (deviceJson != null) params['device'] = deviceJson;
    if (options.userAgent != null) params['userAgent'] = options.userAgent;

    return params;
  }

  Future<_RpcResponse> _sendRequest(String method, dynamic params,
      {int timeoutMs = 15000}) async {
    final id = _uuid.v4();
    final completer = Completer<_RpcResponse>();
    _pending[id] = completer;

    final frame = <String, dynamic>{
      'type': 'req',
      'id': id,
      'method': method,
    };
    if (params != null) frame['params'] = params;

    _sendJson(frame);

    try {
      return await completer.future
          .timeout(Duration(milliseconds: timeoutMs));
    } on TimeoutException {
      _pending.remove(id);
      throw StateError('request timeout');
    }
  }

  void _sendJson(Map<String, dynamic> obj) {
    _channel?.sink.add(jsonEncode(obj));
  }

  void _closeQuietly() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close(1000, 'bye');
    } catch (_) {}
    _channel = null;
    _failPending();
  }

  void _failPending() {
    for (final entry in _pending.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(StateError('connection closed'));
      }
    }
    _pending.clear();
  }
}

class _DesiredConnection {
  final GatewayEndpoint endpoint;
  final String? token;
  final String? password;
  final GatewayConnectOptions options;
  const _DesiredConnection({
    required this.endpoint,
    this.token,
    this.password,
    required this.options,
  });
}
