/// Normalized UI structure extracted from a window for downstream classification.
///
/// Produced by [GuiGrounder] from various sources (UIA, CDP AXTree, OCR).
class UiStructure {
  final String appName;
  final String title;
  final String link;
  final List<UiComponent> components;

  const UiStructure({
    required this.appName,
    required this.title,
    this.link = '',
    this.components = const [],
  });

  Map<String, dynamic> toJson() => {
        'appName': appName,
        'title': title,
        'link': link,
        'components': components.map((c) => c.toJson()).toList(),
      };

  factory UiStructure.fromJson(Map<String, dynamic> m) => UiStructure(
        appName: m['appName'] as String? ?? '',
        title: m['title'] as String? ?? '',
        link: m['link'] as String? ?? '',
        components: (m['components'] as List?)
                ?.map((e) =>
                    UiComponent.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// A single UI element within a window.
class UiComponent {
  /// Element type: text, image, icon, button, input, link, container.
  final String type;

  /// Bounding box relative to the window (physical pixels).
  final double left, top, width, height;

  /// For text / button / input elements: the visible text content.
  final String? text;

  /// For icon elements: a standardised semantic identifier.
  /// Examples: icon_like, icon_share, icon_search, icon_close, icon_menu,
  ///           icon_arrow_left, icon_play, icon_heart, icon_star, icon_more.
  final String? iconId;

  /// For image elements: text recognised *within* the image (OCR).
  final String? ocrText;

  /// For image elements: semantic description of what the image *depicts*.
  /// Requires a vision model; not available from pure OCR.
  final String? caption;

  /// What the user can do with this element.
  /// click, scroll, select, input, toggle, or none.
  final String actionable;

  const UiComponent({
    required this.type,
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
    this.text,
    this.iconId,
    this.ocrText,
    this.caption,
    this.actionable = 'none',
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'type': type,
      'bbox': [left, top, width, height],
    };
    if (text != null) m['text'] = text;
    if (iconId != null) m['iconId'] = iconId;
    if (ocrText != null) m['ocrText'] = ocrText;
    if (caption != null) m['caption'] = caption;
    m['actionable'] = actionable;
    return m;
  }

  factory UiComponent.fromJson(Map<String, dynamic> m) {
    final bbox = (m['bbox'] as List?)?.cast<num>() ?? [0, 0, 0, 0];
    return UiComponent(
      type: m['type'] as String? ?? 'text',
      left: (bbox.isNotEmpty ? bbox[0] : 0).toDouble(),
      top: (bbox.length > 1 ? bbox[1] : 0).toDouble(),
      width: (bbox.length > 2 ? bbox[2] : 0).toDouble(),
      height: (bbox.length > 3 ? bbox[3] : 0).toDouble(),
      text: m['text'] as String?,
      iconId: m['iconId'] as String?,
      ocrText: m['ocrText'] as String?,
      caption: m['caption'] as String?,
      actionable: m['actionable'] as String? ?? 'none',
    );
  }
}
