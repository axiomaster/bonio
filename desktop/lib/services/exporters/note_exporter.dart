import 'dart:io';

import '../../models/note_models.dart';

class ExportResult {
  final bool success;
  final String? error;
  final String? message;
  final String? externalUrl;

  const ExportResult.success({this.message, this.externalUrl})
      : success = true,
        error = null;

  const ExportResult.failure(this.error)
      : success = false,
        message = null,
        externalUrl = null;
}

abstract class NoteExporter {
  /// Unique identifier for this exporter (e.g. 'obsidian', 'notion')
  String get id;

  /// Display name (e.g. 'Obsidian', 'Notion')
  String get name;

  /// Execute the export operation.
  /// [note] The original note metadata.
  /// [markdownContent] The text content of the note (Markdown formatted).
  /// [attachments] A list of local files (images, etc.) associated with the note.
  Future<ExportResult> exportNote(
    BonioNote note,
    String markdownContent,
    List<File> attachments,
  );
}
