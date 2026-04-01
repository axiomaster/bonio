class DeviceIdentity {
  final String deviceId;
  final String publicKeyRawBase64;
  final String privateKeyPkcs8Base64;
  final int createdAtMs;

  const DeviceIdentity({
    required this.deviceId,
    required this.publicKeyRawBase64,
    required this.privateKeyPkcs8Base64,
    required this.createdAtMs,
  });

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) => DeviceIdentity(
        deviceId: json['deviceId'] as String,
        publicKeyRawBase64: json['publicKeyRawBase64'] as String,
        privateKeyPkcs8Base64: json['privateKeyPkcs8Base64'] as String,
        createdAtMs: json['createdAtMs'] as int,
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'publicKeyRawBase64': publicKeyRawBase64,
        'privateKeyPkcs8Base64': privateKeyPkcs8Base64,
        'createdAtMs': createdAtMs,
      };
}
