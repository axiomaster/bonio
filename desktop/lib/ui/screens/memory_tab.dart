import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

import '../../l10n/app_strings.dart';
import '../../models/note_models.dart';
import '../../models/note_export_models.dart';
import '../../providers/app_state.dart';
import '../../services/note_service.dart';

class MemoryTab extends StatefulWidget {
  const MemoryTab({super.key});

  @override
  State<MemoryTab> createState() => _MemoryTabState();
}

class _MemoryTabState extends State<MemoryTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTag;
  bool _initialized = false;

  // Batch selection mode
  bool _isSelectionMode = false;
  final Set<String> _selectedNoteIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final noteService = context.read<AppState>().runtime.noteService;
      noteService.init();
      noteService.addListener(_onNotesChanged);
    }
  }

  void _onNotesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final noteService = context.read<AppState>().runtime.noteService;
    noteService.removeListener(_onNotesChanged);
    _searchController.dispose();
    super.dispose();
  }

  // Toggle selection mode
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedNoteIds.clear();
      }
    });
  }

  // Toggle individual note selection
  void _toggleNoteSelection(String noteId) {
    setState(() {
      if (_selectedNoteIds.contains(noteId)) {
        _selectedNoteIds.remove(noteId);
      } else {
        _selectedNoteIds.add(noteId);
      }
    });
  }

  // Toggle select all
  void _toggleSelectAll(NoteService service) {
    final notes = _filteredNotes(service);
    setState(() {
      if (_selectedNoteIds.length == notes.length) {
        _selectedNoteIds.clear();
      } else {
        _selectedNoteIds.addAll(notes.map((n) => n.id));
      }
    });
  }

  // Handle batch export
  void _handleBatchExport(NoteService noteService) async {
    if (_selectedNoteIds.isEmpty) return;

    final appState = context.read<AppState>();
    final exportService = appState.runtime.noteExportService;

    if (exportService.defaultExporterId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置默认的笔记同步目标')),
      );
      return;
    }

    // For Obsidian, check vault path
    if (exportService.defaultExporterId == 'obsidian' &&
        exportService.obsidianVaultPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置 Obsidian Vault 路径')),
      );
      return;
    }

    final selectedNotes = noteService.notes
        .where((n) => _selectedNoteIds.contains(n.id))
        .toList();

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BatchExportDialog(
        total: selectedNotes.length,
        onExport: (onProgress) async {
          return await exportService.exportBatch(
            selectedNotes,
            null,
            onProgress: onProgress,
          );
        },
      ),
    ).then((result) {
      if (result != null && result is BatchExportResult) {
        _showBatchResult(context, result);
        _toggleSelectionMode(); // Exit selection mode
      }
    });
  }

  // Show batch export result
  void _showBatchResult(BuildContext context, BatchExportResult result) {
    final message = result.isFullySuccessful
        ? '成功导出 ${result.succeeded} 条笔记'
        : '导出完成：成功 ${result.succeeded}，失败 ${result.failed}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<BonioNote> _filteredNotes(NoteService service) {
    var notes = service.notes;
    if (_selectedTag != null) {
      notes = notes.where((n) => n.tags.contains(_selectedTag)).toList();
    }
    if (_searchQuery.isNotEmpty) {
      notes = notes.where((n) {
        final text = [
          n.sourceApp,
          n.rawText ?? '',
          n.summary ?? '',
          ...n.tags,
        ].join(' ').toLowerCase();
        return text.contains(_searchQuery);
      }).toList();
    }
    return notes;
  }

  /// Returns tags sorted by frequency (descending), with counts.
  List<MapEntry<String, int>> _tagCounts(NoteService service) {
    final counts = <String, int>{};
    for (final n in service.notes) {
      for (final t in n.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  void _selectTag(String? tag) {
    setState(() => _selectedTag = (_selectedTag == tag) ? null : tag);
  }

  @override
  Widget build(BuildContext context) {
    final noteService = context.read<AppState>().runtime.noteService;
    final notes = _filteredNotes(noteService);
    final tagCounts = _tagCounts(noteService);
    final totalCount = noteService.notes.length;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode
            ? '已选 ${_selectedNoteIds.length} 项'
            : S.current.memoryTitle),
        actions: [
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              tooltip: '批量选择',
              onPressed: _toggleSelectionMode,
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
              onPressed: () => _toggleSelectAll(noteService),
            ),
            IconButton(
              icon: const Icon(Icons.sync_alt),
              tooltip: '批量导出',
              onPressed: () => _handleBatchExport(noteService),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消',
              onPressed: _toggleSelectionMode,
            ),
          ],
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => noteService.init().then((_) {
                if (mounted) setState(() {});
              }),
              tooltip: S.current.chatRefresh,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: S.current.memorySearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),
          if (tagCounts.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FilterChip(
                      label: Text('${S.current.memoryAll} ($totalCount)'),
                      selected: _selectedTag == null,
                      onSelected: (_) => _selectTag(null),
                    ),
                  ),
                  ...tagCounts.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FilterChip(
                          label: Text('${e.key} (${e.value})'),
                          selected: _selectedTag == e.key,
                          onSelected: (_) => _selectTag(e.key),
                        ),
                      )),
                ],
              ),
            ),
          if (_selectedTag != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_outlined,
                      size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    '$_selectedTag (${notes.length})',
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.primary,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _selectTag(null),
                    borderRadius: BorderRadius.circular(10),
                    child: Icon(Icons.close, size: 16, color: cs.primary),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.collections_bookmark_outlined,
                            size: 64, color: cs.onSurface.withOpacity(0.25)),
                        const SizedBox(height: 12),
                        Text(
                          S.current.memoryNoNotes,
                          style: TextStyle(
                              color: cs.onSurface.withOpacity(0.5),
                              fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          S.current.memoryNoNotesHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: cs.onSurface.withOpacity(0.35),
                              fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: notes.length,
                    itemBuilder: (ctx, i) => _NoteCard(
                      note: notes[i],
                      service: noteService,
                      onTagTap: _selectTag,
                      isSelectionMode: _isSelectionMode,
                      isSelected: _selectedNoteIds.contains(notes[i].id),
                      onToggleSelection: _toggleNoteSelection,
                      onLongPress: _isSelectionMode
                          ? null
                          : () {
                              _toggleSelectionMode();
                              _toggleNoteSelection(notes[i].id);
                            },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final BonioNote note;
  final NoteService service;
  final ValueChanged<String> onTagTap;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<String> onToggleSelection;
  final VoidCallback? onLongPress;

  const _NoteCard({
    required this.note,
    required this.service,
    required this.onTagTap,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onToggleSelection,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasThumb = note.thumbnail != null;
    final syncStatus = _getSyncStatusIcon(note, cs);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide.none,
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () {
              if (isSelectionMode) {
                onToggleSelection(note.id);
              } else {
                _showDetail(context);
              }
            },
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: hasThumb
                      ? Image.file(
                          File(service.thumbnailPath(note.thumbnail!)),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackIcon(cs),
                        )
                      : _fallbackIcon(cs),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(note.createdAt),
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(0.5)),
                        ),
                        const SizedBox(height: 2),
                        if (note.tags.isNotEmpty)
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: note.tags.map((tag) => InkWell(
                              onTap: () => onTagTap(tag),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: cs.primary),
                                ),
                              ),
                            )).toList(),
                          ),
                        if (note.summary != null && note.summary!.isNotEmpty)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                note.summary!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withOpacity(0.7)),
                              ),
                            ),
                          ),
                        if (!note.analyzed)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: cs.onSurface.withOpacity(0.4),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                S.current.memoryAnalyzing,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: cs.onSurface.withOpacity(0.4)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sync status icon (top-right)
          if (syncStatus != null)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(0.8),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  syncStatus.icon,
                  size: 16,
                  color: syncStatus.color,
                ),
              ),
            ),
          // Checkbox in selection mode (top-left)
          if (isSelectionMode)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                ),
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggleSelection(note.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  _SyncStatusIcon? _getSyncStatusIcon(BonioNote note, ColorScheme cs) {
    final status = note.syncStatus;
    if (status == null || status.isEmpty) return null;

    // If synced to Obsidian
    if (status.containsKey('obsidian')) {
      return _SyncStatusIcon(Icons.cloud_done, Colors.green);
    }

    // If synced to ZIP
    if (status.containsKey('zip')) {
      return _SyncStatusIcon(Icons.archive, cs.primary);
    }

    return null;
  }

  Widget _fallbackIcon(ColorScheme cs) {
    IconData icon;
    switch (note.type) {
      case NoteType.text:
        icon = Icons.text_snippet_outlined;
        break;
      case NoteType.file:
        icon = Icons.insert_drive_file_outlined;
        break;
      case NoteType.image:
        icon = Icons.image_outlined;
        break;
      case NoteType.screenshot:
        icon = Icons.screenshot_outlined;
        break;
    }
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, size: 40, color: cs.onSurface.withOpacity(0.3)),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final attachPath = service.attachmentPath(note.fileName);
    final isImage = note.type == NoteType.screenshot ||
        note.type == NoteType.image;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.sourceApp.isNotEmpty
                                ? note.sourceApp
                                : note.type.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _formatDate(note.createdAt),
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.5)),
                          ),
                          // Sync status chips
                          if (note.syncStatus != null && note.syncStatus!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 8,
                                children: note.syncStatus!.entries.map((entry) {
                                  final timestamp = DateTime.parse(entry.value);
                                  return Chip(
                                    avatar: const Icon(Icons.sync, size: 14),
                                    label: Text(
                                      '${_exporterName(entry.key)} ${_formatSyncTime(timestamp)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  );
                                }).toList(),
                              ),
                            ),
                          if (note.sourceUrl != null &&
                              note.sourceUrl!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: InkWell(
                                onTap: () => _launchUrl(note.sourceUrl!),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.link,
                                        size: 14,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .primary),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        note.sourceUrl!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .primary,
                                          decoration:
                                              TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (note.tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: note.tags
                            .map((t) => Chip(
                                  label: Text(t, style: const TextStyle(fontSize: 12)),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                    IconButton(
                      icon: Icon(Icons.sync_alt,
                          color: Theme.of(ctx).colorScheme.primary),
                      tooltip: '导出/同步',
                      onPressed: () {
                        _handleExport(context, note);
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Theme.of(ctx).colorScheme.error),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDelete(context);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Content
              if (isImage && File(attachPath).existsSync())
                Expanded(
                  child: InteractiveViewer(
                    child: Image.file(
                      File(attachPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              if (note.type == NoteType.text && note.rawText != null)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(note.rawText!),
                  ),
                ),
              if (note.summary != null && note.summary!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    note.summary!,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    // In selection mode, don't show delete dialog
    if (isSelectionMode) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.current.memoryDeleteTitle),
        content: Text(S.current.memoryDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.current.cancel),
          ),
          TextButton(
            onPressed: () {
              service.deleteNote(note.id);
              Navigator.pop(ctx);
            },
            child: Text(S.current.delete,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _handleExport(BuildContext context, BonioNote note) async {
    final appState = context.read<AppState>();
    final exportService = appState.runtime.noteExportService;
    
    if (exportService.defaultExporterId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置默认的笔记同步目标')),
      );
      return;
    }

    if (exportService.defaultExporterId == 'zip') {
      final path = await FilePicker.saveFile(
        dialogTitle: '保存 ZIP',
        fileName: 'BonioNote_${note.id.substring(0, 8)}.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (path != null) {
        final result = await exportService.exportToZip(note, path);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.success ? result.message! : '导出失败: ${result.error}')),
          );
        }
      }
      return;
    }

    final exporter = exportService.getConfiguredExporter();
    if (exporter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出配置不完整，请检查设置')),
      );
      return;
    }

    final result = await exportService.export(note, exporter);
    if (context.mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message!),
            action: result.externalUrl != null
                ? SnackBarAction(
                    label: '打开',
                    onPressed: () => _launchUrl(result.externalUrl!),
                  )
                : null,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: ${result.error}')),
        );
      }
    }
  }

  void _launchUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${_p2(dt.month)}-${_p2(dt.day)} '
        '${_p2(dt.hour)}:${_p2(dt.minute)}';
  }

  String _exporterName(String exporterId) {
    switch (exporterId) {
      case 'obsidian':
        return 'Obsidian';
      case 'zip':
        return 'ZIP';
      default:
        return exporterId;
    }
  }

  String _formatSyncTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${dt.month}-${dt.day}';
    }
  }

  static String _p2(int n) => n.toString().padLeft(2, '0');
}

// Helper class for sync status icons
class _SyncStatusIcon {
  final IconData icon;
  final Color color;
  const _SyncStatusIcon(this.icon, this.color);
}

// Batch export dialog widget
class _BatchExportDialog extends StatefulWidget {
  final int total;
  final Future<BatchExportResult> Function(
    void Function(int, int, BonioNote) onProgress,
  ) onExport;

  const _BatchExportDialog({
    required this.total,
    required this.onExport,
  });

  @override
  State<_BatchExportDialog> createState() => _BatchExportDialogState();
}

class _BatchExportDialogState extends State<_BatchExportDialog> {
  int _current = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _startExport();
  }

  Future<void> _startExport() async {
    final result = await widget.onExport((current, total, note) {
      if (mounted) {
        setState(() => _current = current);
      }
    });

    if (mounted) {
      setState(() => _completed = true);
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('批量导出'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('正在导出 $_current/${widget.total}'),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _completed ? 1.0 : _current / widget.total,
          ),
        ],
      ),
    );
  }
}
