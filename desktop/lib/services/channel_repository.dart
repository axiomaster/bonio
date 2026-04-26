import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/channel_config.dart';
import 'gateway_session.dart';

class ChannelRepository {
  final GatewaySession session;

  ChannelRepository(this.session);

  Future<ChannelConfig> getConfig() async {
    try {
      final raw = await session.request('channel.config', null);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ChannelConfig.fromJson(json);
    } catch (e) {
      debugPrint('ChannelRepository: getConfig failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getQrCode() async {
    try {
      final raw = await session.request('channel.wechat.qrcode', null);
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ChannelRepository: getQrCode failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getStatus(String qrcodeKey) async {
    try {
      final params = jsonEncode({'qrcode_key': qrcodeKey});
      final raw = await session.request('channel.wechat.status', params);
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ChannelRepository: getStatus failed: $e');
      rethrow;
    }
  }

  Future<void> setup(String token, {String? baseUrl, List<String>? allowFrom}) async {
    try {
      final params = <String, dynamic>{'token': token};
      if (baseUrl != null && baseUrl.isNotEmpty) params['base_url'] = baseUrl;
      if (allowFrom != null && allowFrom.isNotEmpty) params['allow_from'] = allowFrom;
      await session.request('channel.wechat.setup', jsonEncode(params));
    } catch (e) {
      debugPrint('ChannelRepository: setup failed: $e');
      rethrow;
    }
  }

  Future<void> disable() async {
    try {
      await session.request('channel.wechat.disable', null);
    } catch (e) {
      debugPrint('ChannelRepository: disable failed: $e');
      rethrow;
    }
  }
}
