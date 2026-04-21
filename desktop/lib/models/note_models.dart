enum NoteType { screenshot, text, image, file }

/// A single semantic paragraph summary with subtitle and content.
class ParagraphSummary {
  final String subtitle;
  final String content;

  const ParagraphSummary({required this.subtitle, required this.content});

  factory ParagraphSummary.fromJson(Map<String, dynamic> m) {
    return ParagraphSummary(
      subtitle: m['subtitle'] as String? ?? '',
      content: m['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'subtitle': subtitle, 'content': content};
}

/// Result of AI-powered reading companion summarization.
class ReadingSummary {
  final String title;
  final String author;
  final String summary;
  final List<ParagraphSummary> paragraphSummaries;

  const ReadingSummary({
    required this.title,
    this.author = '',
    required this.summary,
    this.paragraphSummaries = const [],
  });

  factory ReadingSummary.fromJson(Map<String, dynamic> m) {
    return ReadingSummary(
      title: m['title'] as String? ?? '',
      author: m['author'] as String? ?? '',
      summary: m['summary'] as String? ?? '',
      paragraphSummaries: (m['paragraph_summaries'] as List?)
              ?.map((e) => ParagraphSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'author': author,
        'summary': summary,
        'paragraph_summaries':
            paragraphSummaries.map((e) => e.toJson()).toList(),
      };
}

class BojiNote {
  final String id;
  final DateTime createdAt;
  final NoteType type;
  final String sourceApp;
  final String? sourceUrl;
  String? rawText;
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
