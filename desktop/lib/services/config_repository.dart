import 'dart:convert';
import '../models/server_config.dart';
import 'gateway_session.dart';

class ConfigRepository {
  final GatewaySession session;

  ConfigRepository({required this.session});

  Future<ServerConfig> getConfig() async {
    final payloadJson = await session.request('config.get', null);
    final json = jsonDecode(payloadJson) as Map<String, dynamic>;
    return ServerConfig.fromJson(json);
  }

  Future<void> setConfig({
    String? defaultModel,
    List<ModelConfig>? models,
  }) async {
    final params = <String, dynamic>{};
    if (defaultModel != null) {
      params['default_model'] = defaultModel;
    }
    if (models != null) {
      params['models'] = models.map((m) => m.toJson()).toList();
    }
    await session.request('config.set', jsonEncode(params));
  }
}
