// Probe OpenClaw gateway handshake (no Flutter UI). Run from desktop/:
//   dart run tool/openclaw_probe.dart
//   dart run tool/openclaw_probe.dart --token=YOUR_TOKEN
//
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

Future<void> main(List<String> args) async {
  String token = 'lism';
  for (final a in args) {
    if (a.startsWith('--token=')) {
      token = a.substring('--token='.length);
    }
  }

  const host = '127.0.0.1';
  const port = 18789;
  final url = 'ws://$host:$port';

  print('=== OpenClaw WS probe ===');
  print('URL: $url');
  print('Token: ${token.isEmpty ? "(empty)" : "***"}');

  late WebSocketChannel channel;
  try {
    channel = WebSocketChannel.connect(Uri.parse(url));
  } catch (e, st) {
    print('FATAL: WebSocket.connect failed: $e\n$st');
    return;
  }

  final challengeCompleter = Completer<String>();
  final connectResCompleter = Completer<Map<String, dynamic>>();
  String? connectReqId;

  final sub = channel.stream.listen(
    (dynamic data) async {
      final text = data is String ? data : utf8.decode(data as List<int>);
      print('<< $text');
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        final type = j['type'] as String?;

        if (type == 'event' &&
            j['event'] == 'connect.challenge' &&
            !challengeCompleter.isCompleted) {
          final p = j['payload'];
          final n = p is Map<String, dynamic> ? p['nonce'] as String? : null;
          if (n != null && n.isNotEmpty) {
            challengeCompleter.complete(n);
          }
          return;
        }

        if (type == 'res' &&
            connectReqId != null &&
            j['id'] == connectReqId &&
            !connectResCompleter.isCompleted) {
          connectResCompleter.complete(j);
        }
      } catch (_) {}
    },
    onError: (e) {
      if (!challengeCompleter.isCompleted) challengeCompleter.completeError(e);
      if (!connectResCompleter.isCompleted) {
        connectResCompleter.completeError(e);
      }
    },
    onDone: () {
      if (!challengeCompleter.isCompleted) {
        challengeCompleter.completeError(StateError('socket closed before challenge'));
      }
      if (!connectResCompleter.isCompleted) {
        connectResCompleter.completeError(StateError('socket closed before connect res'));
      }
    },
  );

  String? nonce;
  try {
    nonce = await challengeCompleter.future.timeout(const Duration(seconds: 15));
  } catch (e, st) {
    print('ERROR waiting for connect.challenge: $e\n$st');
    await sub.cancel();
    await channel.sink.close();
    return;
  }

  final ed = Ed25519();
  final keyPair = await ed.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final rawPub = Uint8List.fromList(publicKey.bytes);
  final deviceId = await _sha256Hex(rawPub);

  const scopes = [
    'operator.admin',
    'operator.read',
    'operator.write',
    'operator.approvals',
    'operator.pairing',
  ];
  final signedAtMs = DateTime.now().millisecondsSinceEpoch;
  final scopeStr = scopes.join(',');
  final payloadStr = [
    'v3',
    deviceId,
    'openclaw-macos',
    'ui',
    'operator',
    scopeStr,
    signedAtMs.toString(),
    token,
    nonce,
    'windows',
    'desktop',
  ].join('|');

  final signature = await ed.sign(utf8.encode(payloadStr), keyPair: keyPair);
  final sigB64 = _base64UrlNoPad(signature.bytes);
  final pubB64 = _base64UrlNoPad(rawPub);

  connectReqId = _uuid.v4();
  final connectFrame = <String, dynamic>{
    'type': 'req',
    'id': connectReqId,
    'method': 'connect',
    'params': <String, dynamic>{
      'minProtocol': 3,
      'maxProtocol': 3,
      'client': <String, dynamic>{
        'id': 'openclaw-macos',
        'displayName': 'BoJi Desktop',
        'version': '1.0.0',
        'platform': 'windows',
        'mode': 'ui',
        'deviceFamily': 'desktop',
      },
      'role': 'operator',
      'scopes': scopes,
      'locale': 'en',
      'auth': <String, dynamic>{'token': token},
      'device': <String, dynamic>{
        'id': deviceId,
        'publicKey': pubB64,
        'signature': sigB64,
        'signedAt': signedAtMs,
        'nonce': nonce,
      },
    },
  };

  print('>> connect (id=$connectReqId, deviceId prefix=${deviceId.substring(0, 8)}...)');
  channel.sink.add(jsonEncode(connectFrame));

  try {
    final res = await connectResCompleter.future.timeout(const Duration(seconds: 25));
    final ok = res['ok'];
    print('--- connect RPC done: ok=$ok ---');
    if (ok != true && res['error'] != null) {
      print('ERROR PAYLOAD: ${jsonEncode(res['error'])}');
    } else if (ok == true) {
      print('SUCCESS: payload keys: ${(res['payload'] as Map?)?.keys.toList()}');
    }
  } catch (e, st) {
    print('ERROR waiting for connect response: $e\n$st');
  }

  await sub.cancel();
  try {
    await channel.sink.close();
  } catch (_) {}
}

Future<String> _sha256Hex(Uint8List data) async {
  final hash = await Sha256().hash(data);
  final sb = StringBuffer();
  for (final b in hash.bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _base64UrlNoPad(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
