enum NoteType { screenshot, text, image, file }

class BojiNote {
  final String id;
  final DateTime createdAt;
  final NoteType type;
  final String sourceApp;
  final String? sourceUrl;
  final String? rawText;
  final String fileName;
  final String? thumbnail;
  List<String> tags;
  String? summary;
  bool analyzed;

  BojiNote({
    required this.id,
    required this.createdAt,
    required this.type,
    required this.sourceApp,
    this.sourceUrl,
    this.rawText,
    required this.fileName,
    this.thumbnail,
    this.tags = const [],
    this.summary,
    this.analyzed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': type.name,
        'sourceApp': sourceApp,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'rawText': rawText,
        'fileName': fileName,
        'thumbnail': thumbnail,
        'tags': tags,
        'summary': summary,
        'analyzed': analyzed,
      };

  factory BojiNote.fromJson(Map<String, dynamic> m) {
    return BojiNote(
      id: m['id'] as String,
      createdAt: DateTime.parse(m['createdAt'] as String),
      type: NoteType.values.firstWhere(
        (t) => t.name == m['type'],
        orElse: () => NoteType.screenshot,
      ),
      sourceApp: m['sourceApp'] as String? ?? '',
      sourceUrl: m['sourceUrl'] as String?,
      rawText: m['rawText'] as String?,
      fileName: m['fileName'] as String,
      thumbnail: m['thumbnail'] as String?,
      tags: (m['tags'] as List?)?.cast<String>() ?? [],
      summary: m['summary'] as String?,
      analyzed: m['analyzed'] as bool? ?? false,
    );
  }
}
