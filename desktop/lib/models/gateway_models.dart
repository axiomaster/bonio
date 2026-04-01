class GatewayClientInfo {
  final String id;
  final String? displayName;
  final String version;
  final String platform;
  final String mode;
  final String? instanceId;
  final String? deviceFamily;
  final String? modelIdentifier;

  const GatewayClientInfo({
    required this.id,
    this.displayName,
    required this.version,
    required this.platform,
    required this.mode,
    this.instanceId,
    this.deviceFamily,
    this.modelIdentifier,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'version': version,
      'platform': platform,
      'mode': mode,
    };
    if (displayName != null) m['displayName'] = displayName;
    if (instanceId != null) m['instanceId'] = instanceId;
    if (deviceFamily != null) m['deviceFamily'] = deviceFamily;
    if (modelIdentifier != null) m['modelIdentifier'] = modelIdentifier;
    return m;
  }
}

class GatewayConnectOptions {
  final String role;
  final List<String> scopes;
  final List<String> caps;
  final List<String> commands;
  final Map<String, bool> permissions;
  final GatewayClientInfo client;
  final String? userAgent;

  const GatewayConnectOptions({
    required this.role,
    this.scopes = const [],
    this.caps = const [],
    this.commands = const [],
    this.permissions = const {},
    required this.client,
    this.userAgent,
  });
}

class GatewayEndpoint {
  final String stableId;
  final String name;
  final String host;
  final int port;
  final String? lanHost;
  final String? tailnetDns;
  final int? gatewayPort;
  final int? canvasPort;
  final bool tlsEnabled;
  final String? tlsFingerprintSha256;

  const GatewayEndpoint({
    required this.stableId,
    required this.name,
    required this.host,
    required this.port,
    this.lanHost,
    this.tailnetDns,
    this.gatewayPort,
    this.canvasPort,
    this.tlsEnabled = false,
    this.tlsFingerprintSha256,
  });

  factory GatewayEndpoint.manual(String host, int port) => GatewayEndpoint(
        stableId: 'manual|${host.toLowerCase()}|$port',
        name: '$host:$port',
        host: host,
        port: port,
      );
}
