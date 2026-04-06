class WindowConfiguration {
  const WindowConfiguration({
    required this.arguments,
    this.hiddenAtLaunch = true,
    this.borderless = false,
    this.width = 0,
    this.height = 0,
  });

  /// The arguments passed to the new window.
  final String arguments;

  final bool hiddenAtLaunch;

  /// When true, the native window is created without a title bar or buttons
  /// (borderless) and with a transparent background — ideal for floating
  /// overlay windows like the avatar pet.
  final bool borderless;

  /// Initial window width in logical pixels. 0 means use native default.
  final double width;

  /// Initial window height in logical pixels. 0 means use native default.
  final double height;

  factory WindowConfiguration.fromJson(Map<String, dynamic> json) {
    return WindowConfiguration(
      arguments: json['arguments'] as String? ?? '',
      hiddenAtLaunch: json['hiddenAtLaunch'] as bool? ?? false,
      borderless: json['borderless'] as bool? ?? false,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'arguments': arguments,
      'hiddenAtLaunch': hiddenAtLaunch,
      'borderless': borderless,
      'width': width,
      'height': height,
    };
  }

  @override
  String toString() {
    return 'WindowConfiguration(arguments: $arguments, hiddenAtLaunch: $hiddenAtLaunch, borderless: $borderless, width: $width, height: $height)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WindowConfiguration &&
        other.arguments == arguments &&
        other.hiddenAtLaunch == hiddenAtLaunch &&
        other.borderless == borderless &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode {
    return arguments.hashCode ^
        hiddenAtLaunch.hashCode ^
        borderless.hashCode ^
        width.hashCode ^
        height.hashCode;
  }
}
