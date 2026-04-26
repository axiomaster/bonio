class ChannelConfig {
  final bool enabled;
  final String? mode;
  final String? wecomBotId;

  const ChannelConfig({
    this.enabled = false,
    this.mode,
    this.wecomBotId,
  });

  factory ChannelConfig.fromJson(Map<String, dynamic> json) {
    return ChannelConfig(
      enabled: json['enabled'] as bool? ?? false,
      mode: json['mode'] as String?,
      wecomBotId: json['wecom_bot_id'] as String?,
    );
  }

  bool get isWeixin => mode == 'weixin';
  bool get isWecom => mode == 'wecom';
}
