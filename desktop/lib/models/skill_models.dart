class SkillInfo {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final bool builtin;

  const SkillInfo({
    required this.id,
    this.name = '',
    this.description = '',
    this.enabled = true,
    this.builtin = false,
  });

  factory SkillInfo.fromJson(Map<String, dynamic> json) => SkillInfo(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        builtin: json['builtin'] as bool? ?? false,
      );
}
