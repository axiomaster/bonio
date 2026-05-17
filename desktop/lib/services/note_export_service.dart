import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note_models.dart';
import '../models/note_export_models.dart';
import 'app_logger.dart';
import 'note_service.dart';
import 'exporters/note_exporter.dart';
import 'exporters/obsidian_exporter.dart';
import 'exporters/zip_exporter.dart';

class NoteExportService extends ChangeNotifier {
  final NoteService _noteService;
  late SharedPreferences _prefs;

  bool _initialized = false;
  String _defaultExporterId = '';
  String _obsidianVaultPath = '';
  String _obsidianSubFolder = 'Bonio-Inbox';
  bool _autoSyncEnabled = false;

  String get defaultExporterId => _defaultExporterId;
  String get obsidianVaultPath => _obsidianVaultPath;
  String get obsidianSubFolder => _obsidianSubFolder;
  bool get autoSyncEnabled => _autoSyncEnabled;

  NoteExportService({required NoteService noteService}) : _noteService = noteService;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _defaultExporterId = _prefs.getString('note_export_default_id') ?? '';
    _obsidianVaultPath = _prefs.getString('note_export_obsidian_vault') ?? '';
    _obsidianSubFolder = _prefs.getString('note_export_obsidian_subfolder') ?? 'Bonio-Inbox';
    _autoSyncEnabled = _prefs.getBool('note_export_auto_sync') ?? false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> updateConfig({
    String? defaultExporterId,
    String? obsidianVaultPath,
    String? obsidianSubFolder,
    bool? autoSyncEnabled,
  }) async {
    if (defaultExporterId != null) {
      _defaultExporterId = defaultExporterId;
      await _prefs.setString('note_export_default_id', defaultExporterId);
    }
    if (obsidianVaultPath != null) {
      _obsidianVaultPath = obsidianVaultPath;
      await _prefs.setString('note_export_obsidian_vault', obsidianVaultPath);
    }
    if (obsidianSubFolder != null) {
      _obsidianSubFolder = obsidianSubFolder;
      await _prefs.setString('note_export_obsidian_subfolder', obsidianSubFolder);
    }
    if (autoSyncEnabled != null) {
      _autoSyncEnabled = autoSyncEnabled;
      await _prefs.setBool('note_export_auto_sync', autoSyncEnabled);
    }
    notifyListeners();
  }

  /// Helper to get the currently configured exporter, if any.
  NoteExporter? getConfiguredExporter() {
    if (_defaultExporterId == 'obsidian' && _obsidianVaultPath.isNotEmpty) {
      return ObsidianExporter(
        vaultPath: _obsidianVaultPath,
        subFolder: _obsidianSubFolder,
      );
    }
    return null;
  }

  /// Export using a specific exporter.
  Future<ExportResult> export(BonioNote note, NoteExporter exporter) async {
    // Read raw markdown or reconstruct basic markdown
    var markdown = note.rawText ?? '';
    if (markdown.isEmpty && note.summary != null && note.summary!.isNotEmpty) {
      markdown = note.summary!;
    }

    // Collect attachments
    final List<File> attachments = [];
    if (note.type == NoteType.screenshot || note.type == NoteType.image || note.type == NoteType.file) {
      final attachPath = _noteService.attachmentPath(note.fileName);
      final file = File(attachPath);
      if (await file.exists()) {
        attachments.add(file);
      }
    }

    final result = await exporter.exportNote(note, markdown, attachments);

    if (result.success) {
      // Update note status
      note.syncStatus ??= {};
      note.syncStatus![exporter.id] = DateTime.now().toIso8601String();
      await _noteService.updateNote(note);
    }

    return result;
  }

  /// Run manual zip export using FilePicker for path selection.
  Future<ExportResult> exportToZip(BonioNote note, String zipOutputPath) async {
    final zipExporter = ZipExporter(outputPath: zipOutputPath);
    return export(note, zipExporter);
  }

  /// Batch export notes list.
  ///
  /// Parameters:
  /// - notes: List of notes to export
  /// - exporter: Exporter to use (if null, uses configured default)
  /// - onProgress: Progress callback, (current index, total, current note)
  ///
  /// Returns: BatchExportResult
  Future<BatchExportResult> exportBatch(
    List<BonioNote> notes,
    NoteExporter? exporter, {
    void Function(int current, int total, BonioNote note)? onProgress,
  }) async {
    final actualExporter = exporter ?? getConfiguredExporter();
    if (actualExporter == null) {
      return BatchExportResult(
        total: notes.length,
        succeeded: 0,
        failed: notes.length,
        failedNoteIds: notes.map((n) => n.id).toList(),
      );
    }

    int succeeded = 0;
    int failed = 0;
    final failedIds = <String>[];

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      onProgress?.call(i + 1, notes.length, note);

      try {
        final result = await export(note, actualExporter);
        if (result.success) {
          succeeded++;
        } else {
          failed++;
          failedIds.add(note.id);
        }
      } catch (e) {
        failed++;
        failedIds.add(note.id);
        log.error('Batch export failed for ${note.id}: $e');
      }
    }

    return BatchExportResult(
      total: notes.length,
      succeeded: succeeded,
      failed: failed,
      failedNoteIds: failedIds,
      exporterId: actualExporter.id,
    );
  }

  /// Check if a note has been synced to a specific target.
  bool isNoteSynced(BonioNote note, String exporterId) {
    return note.syncStatus?.containsKey(exporterId) ?? false;
  }

  /// Get sync status summary for a note (for UI display).
  Map<String, DateTime> getNoteSyncSummary(BonioNote note) {
    if (note.syncStatus == null) return {};
    return note.syncStatus!.map(
      (key, value) => MapEntry(key, DateTime.parse(value)),
    );
  }

  /// Trigger auto-sync (called by NoteService).
  ///
  /// If auto-sync is enabled and a default exporter is configured,
  /// automatically export the note. Failures are handled silently.
  Future<void> triggerAutoSync(BonioNote note) async {
    if (!_autoSyncEnabled || _defaultExporterId.isEmpty) {
      return;
    }

    final exporter = getConfiguredExporter();
    if (exporter == null) return;

    try {
      await export(note, exporter);
    } catch (e) {
      // Silent failure for auto-sync
      log.warn('NoteExportService: auto-sync failed for ${note.id}: $e');
    }
  }
}
