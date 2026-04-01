class ServerConfig {
  final String defaultModel;
  final List<ModelConfig> models;
  final List<ProviderInfo> providers;
  final GatewayConfig? gateway;

  const ServerConfig({
    this.defaultModel = '',
    this.models = const [],
    this.providers = const [],
    this.gateway,
  });

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        defaultModel: json['default_model'] as String? ?? '',
        models: (json['models'] as List<dynamic>?)
                ?.map((e) => ModelConfig.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        providers: (json['providers'] as List<dynamic>?)
                ?.map((e) => ProviderInfo.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        gateway: json['gateway'] != null
            ? GatewayConfig.fromJson(json['gateway'] as Map<String, dynamic>)
            : null,
      );
}

class GatewayConfig {
  final int port;
  final String host;
  final bool enabled;

  const GatewayConfig({
    this.port = 8765,
    this.host = '0.0.0.0',
    this.enabled = true,
  });

  factory GatewayConfig.fromJson(Map<String, dynamic> json) => GatewayConfig(
        port: json['port'] as int? ?? 8765,
        host: json['host'] as String? ?? '0.0.0.0',
        enabled: json['enabled'] as bool? ?? true,
      );
}

class ModelConfig {
  final String id;
  final String provider;
  final String? baseUrl;
  final String? modelId;
  final String? apiKey;

  const ModelConfig({
    required this.id,
    required this.provider,
    this.baseUrl,
    this.modelId,
    this.apiKey,
  });

  factory ModelConfig.fromJson(Map<String, dynamic> json) => ModelConfig(
        id: json['id'] as String,
        provider: json['provider'] as String,
        baseUrl: json['base_url'] as String?,
        modelId: json['model_id'] as String?,
        apiKey: json['api_key'] as String?,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'provider': provider,
    };
    if (baseUrl != null) m['base_url'] = baseUrl;
    if (modelId != null) m['model_id'] = modelId;
    if (apiKey != null) m['api_key'] = apiKey;
    return m;
  }

  ModelConfig copyWith({
    String? id,
    String? provider,
    String? baseUrl,
    String? modelId,
    String? apiKey,
  }) =>
      ModelConfig(
        id: id ?? this.id,
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        modelId: modelId ?? this.modelId,
        apiKey: apiKey ?? this.apiKey,
      );
}

class ProviderInfo {
  final String id;
  final String displayName;
  final bool requiresApiKey;
  final String defaultBaseUrl;

  const ProviderInfo({
    required this.id,
    required this.displayName,
    this.requiresApiKey = true,
    this.defaultBaseUrl = '',
  });

  factory ProviderInfo.fromJson(Map<String, dynamic> json) => ProviderInfo(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        requiresApiKey: json['requires_api_key'] as bool? ?? true,
        defaultBaseUrl: json['default_base_url'] as String? ?? '',
      );
}
