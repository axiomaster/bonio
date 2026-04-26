import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import '../models/device_identity.dart';

class DeviceIdentityStore {
  DeviceIdentity? _cached;
  String? _identityFilePath;

  Future<String> _getIdentityPath() async {
    if (_identityFilePath != null) return _identityFilePath!;
    final dir = await getApplicationSupportDirectory();
    _identityFilePath = '${dir.path}/bonio/identity/device.json';
    return _identityFilePath!;
  }

  Future<DeviceIdentity> loadOrCreate() async {
    if (_cached != null) return _cached!;
    final existing = await _load();
    if (existing != null) {
      _cached = existing;
      return existing;
    }
    final fresh = await _generate();
    await _save(fresh);
    _cached = fresh;
    return fresh;
  }

  Future<String?> signPayload(String payload, DeviceIdentity identity) async {
    try {
      final seed = base64.decode(identity.privateKeyPkcs8Base64);
      final ed = Ed25519();
      final keyPair = await ed.newKeyPairFromSeed(seed);
      final payloadBytes = utf8.encode(payload);
      final signature = await ed.sign(payloadBytes, keyPair: keyPair);
      return _base64UrlEncode(Uint8List.fromList(signature.bytes));
    } catch (_) {
      return null;
    }
  }

  String? publicKeyBase64Url(DeviceIdentity identity) {
    try {
      final raw = base64.decode(identity.publicKeyRawBase64);
      return _base64UrlEncode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<DeviceIdentity?> _load() async {
    try {
      final path = await _getIdentityPath();
      final file = File(path);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final identity = DeviceIdentity.fromJson(json);
      if (identity.deviceId.isEmpty ||
          identity.publicKeyRawBase64.isEmpty ||
          identity.privateKeyPkcs8Base64.isEmpty) {
        return null;
      }
      return identity;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(DeviceIdentity identity) async {
    try {
      final path = await _getIdentityPath();
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(identity.toJson()));
    } catch (_) {}
  }

  Future<DeviceIdentity> _generate() async {
    final ed = Ed25519();
    final keyPair = await ed.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final rawPublic = Uint8List.fromList(publicKey.bytes);
    final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final deviceId = await _sha256Hex(rawPublic);
    return DeviceIdentity(
      deviceId: deviceId,
      publicKeyRawBase64: base64.encode(rawPublic),
      privateKeyPkcs8Base64: base64.encode(seed),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<String> _sha256Hex(List<int> data) async {
    final algorithm = Sha256();
    final hash = await algorithm.hash(data);
    final sb = StringBuffer();
    for (final b in hash.bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  String _base64UrlEncode(List<int> data) {
    return base64Url.encode(data).replaceAll('=', '');
  }
}

class DeviceAuthPayload {
  static String buildV3({
    required String deviceId,
    required String clientId,
    required String clientMode,
    required String role,
    required List<String> scopes,
    required int signedAtMs,
    String? token,
    required String nonce,
    String? platform,
    String? deviceFamily,
  }) {
    final scopeString = scopes.join(',');
    final authToken = token ?? '';
    final platformNorm = _normalizeMetadataField(platform);
    final deviceFamilyNorm = _normalizeMetadataField(deviceFamily);
    return [
      'v3',
      deviceId,
      clientId,
      clientMode,
      role,
      scopeString,
      signedAtMs.toString(),
      authToken,
      nonce,
      platformNorm,
      deviceFamilyNorm,
    ].join('|');
  }

  static String _normalizeMetadataField(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    return trimmed.toLowerCase();
  }
}
