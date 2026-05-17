/// Batch export result model for note export operations.
class BatchExportResult {
  /// Total number of notes in the batch.
  final int total;

  /// Number of successfully exported notes.
  final int succeeded;

  /// Number of failed exports.
  final int failed;

  /// List of note IDs that failed to export.
  final List<String> failedNoteIds;

  /// The exporter ID used for this batch operation.
  final String? exporterId;

  const BatchExportResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    this.failedNoteIds = const [],
    this.exporterId,
  });

  /// Returns true if all notes were exported successfully.
  bool get isFullySuccessful => failed == 0;

  @override
  String toString() =>
      'BatchExportResult(total: $total, succeeded: $succeeded, failed: $failed, '
      'exporterId: $exporterId)';
}
