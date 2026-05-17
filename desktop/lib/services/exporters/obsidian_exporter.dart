import 'dart:io';
import 'package:path/path.dart' as p;

import '../../models/note_models.dart';
import 'note_exporter.dart';

class ObsidianExporter implements NoteExporter {
  final String vaultPath;
  final String subFolder;

  ObsidianExporter({required this.vaultPath, this.subFolder = 'BoJi-Inbox'});

  @override
  String get id => 'obsidian';

  @override
  String get name => 'Obsidian';

  @override
  Future<ExportResult> exportNote(
      BonioNote note, String markdownContent, List<File> attachments) async {
    try {
      final targetDir = Directory(p.join(vaultPath, subFolder));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final attachDir = Directory(p.join(targetDir.path, 'attachments'));
      if (attachments.isNotEmpty && !await attachDir.exists()) {
        await attachDir.create(recursive: true);
      }

      // Copy attachments
      for (final file in attachments) {
        if (!await file.exists()) continue;
        final fileName = p.basename(file.path);
        final destPath = p.join(attachDir.path, fileName);
        await file.copy(destPath);
      }

      // Modify markdown content: replace local file references with Obsidian links
      // Simple implementation: just append the attachments at the bottom if it's an image capture
      // or replace standard markdown images with obsidian wiki links if needed.
      var finalMarkdown = markdownContent;

      if (note.type == NoteType.screenshot || note.type == NoteType.image) {
        // If it's mainly an image capture, ensure the image is displayed
        for (final file in attachments) {
          final fileName = p.basename(file.path);
          if (fileName.endsWith('.png') || fileName.endsWith('.jpg')) {
            final wikiLink = '\n\n![[$fileName]]\n';
            if (!finalMarkdown.contains(fileName)) {
              finalMarkdown += wikiLink;
            } else {
              // Try to replace standard markdown link `![alt](filename)` with `![[filename]]`
              finalMarkdown = finalMarkdown.replaceAll(
                  RegExp(r'!\[.*?\]\(' + RegExp.escape(fileName) + r'\)'),
                  '![[$fileName]]');
            }
          }
        }
      }

      // Prepend metadata/tags if available
      if (note.tags.isNotEmpty || note.sourceUrl != null) {
        final frontmatter = StringBuffer();
        frontmatter.writeln('---');
        if (note.tags.isNotEmpty) {
          frontmatter.writeln('tags:');
          for (final tag in note.tags) {
            frontmatter.writeln('  - $tag');
          }
        }
        if (note.sourceUrl != null && note.sourceUrl!.isNotEmpty) {
          frontmatter.writeln('source: ${note.sourceUrl}');
        }
        frontmatter.writeln('date: ${note.createdAt.toIso8601String()}');
        frontmatter.writeln('---');
        frontmatter.writeln();
        finalMarkdown = frontmatter.toString() + finalMarkdown;
      }

      // Save markdown file
      final safeTitle = _sanitizeFilename(
          note.sourceApp.isNotEmpty ? note.sourceApp : 'Note_${note.id.substring(0, 8)}');
      
      // Ensure unique filename
      var mdFileName = '$safeTitle.md';
      var mdFile = File(p.join(targetDir.path, mdFileName));
      var counter = 1;
      while (await mdFile.exists()) {
        mdFileName = '${safeTitle}_$counter.md';
        mdFile = File(p.join(targetDir.path, mdFileName));
        counter++;
      }

      await mdFile.writeAsString(finalMarkdown);

      // Create obsidian:// URI to open the file
      final vaultName = p.basename(vaultPath);
      final encodedVault = Uri.encodeComponent(vaultName);
      // We encode the file path relative to the vault
      final relativePath = p.join(subFolder, p.basenameWithoutExtension(mdFile.path)).replaceAll('\\', '/');
      final encodedFile = Uri.encodeComponent(relativePath);
      final obsidianUri = 'obsidian://open?vault=$encodedVault&file=$encodedFile';

      return ExportResult.success(
        message: 'Saved to $subFolder/$mdFileName',
        externalUrl: obsidianUri,
      );
    } catch (e) {
      return ExportResult.failure(e.toString());
    }
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }
}
