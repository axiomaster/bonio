import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../models/note_models.dart';
import 'note_exporter.dart';

class ZipExporter implements NoteExporter {
  final String outputPath;

  ZipExporter({required this.outputPath});

  @override
  String get id => 'zip';

  @override
  String get name => 'ZIP Archive';

  @override
  Future<ExportResult> exportNote(
      BonioNote note, String markdownContent, List<File> attachments,
      {String? previousPath}) async {
    try {
      final archive = Archive();

      // Add markdown file
      final mdFileName = '${_sanitizeFilename(note.sourceApp.isNotEmpty ? note.sourceApp : 'Note')}_${note.id.substring(0, 8)}.md';
      final mdBytes = markdownContent.codeUnits;
      archive.addFile(ArchiveFile(mdFileName, mdBytes.length, mdBytes));

      // Add attachments
      for (final file in attachments) {
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final fileName = p.basename(file.path);
        archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
      }

      // Encode and save
      final encoder = ZipFileEncoder();
      encoder.create(outputPath);
      for (final file in archive) {
        if (file.isFile) {
          encoder.addArchiveFile(file);
        }
      }
      encoder.close();

      return ExportResult.success(message: 'Exported to $outputPath');
    } catch (e) {
      return ExportResult.failure(e.toString());
    }
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }
}
