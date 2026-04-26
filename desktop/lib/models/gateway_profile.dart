/// Gateway product line: OpenClaw-compatible vs HiClaw server.
/// Protocol frames follow OpenClaw v3; defaults differ by profile.
enum GatewayProfile {
  hiclaw,
  openclaw,
}

extension GatewayProfileX on GatewayProfile {
  static GatewayProfile fromStorage(String? value) {
    switch (value) {
      case 'openclaw':
        return GatewayProfile.openclaw;
      case 'hiclaw':
      default:
        return GatewayProfile.hiclaw;
    }
  }

  String get storageValue => switch (this) {
        GatewayProfile.openclaw => 'openclaw',
        GatewayProfile.hiclaw => 'hiclaw',
      };

  String get displayLabel => switch (this) {
        GatewayProfile.openclaw => 'OpenClaw',
        GatewayProfile.hiclaw => 'HiClaw',
      };

  /// Default WebSocket port (OpenClaw gateway default is 18789 per upstream docs).
  int get defaultPort => switch (this) {
        GatewayProfile.openclaw => 18789,
        GatewayProfile.hiclaw => 10724,
      };

  /// Suggested loopback host for local gateways.
  String get defaultHost => switch (this) {
        GatewayProfile.openclaw => '127.0.0.1',
        GatewayProfile.hiclaw => '',
      };

  /// OpenClaw macOS UI client scopes, plus HiClaw-specific secret scope when needed.
  List<String> get operatorScopes => switch (this) {
        GatewayProfile.openclaw => const [
            'operator.admin',
            'operator.read',
            'operator.write',
            'operator.approvals',
            'operator.pairing',
          ],
        GatewayProfile.hiclaw => const [
            'operator.admin',
            'operator.read',
            'operator.write',
            'operator.approvals',
            'operator.pairing',
            'operator.talk.secrets',
          ],
      };

  /// OpenClaw validates `client.id` against an allowlist (see `gateway/protocol/client-info.ts`).
  /// Use the same id as the official macOS app so `connect` passes schema validation.
  String get clientId => switch (this) {
        GatewayProfile.openclaw => 'openclaw-macos',
        GatewayProfile.hiclaw => 'bonio-desktop',
      };

  /// Operator UI uses `ui`; node session must use `node` (matches OpenClaw MacNodeModeCoordinator).
  String clientModeForRole(String role) {
    if (role == 'node') return 'node';
    return 'ui';
  }
}
