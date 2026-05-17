# 架构设计文档：Bonio 笔记批量导出与自动同步

**文档版本:** V1.0
**状态:** 设计中
**日期:** 2026-05-17
**架构师:** Claude
**对应 PRD:** `prd/note-export-prd-20260517.md`

---

## 1. 架构概述

本文档描述 Bonio 笔记导出功能的增强架构，主要实现以下功能：
- **批量选择导出**：支持多选笔记并批量导出到配置的目标
- **自动同步**：新笔记创建后自动触发导出（可配置开关）
- **同步状态可视化**：笔记卡片上显示同步状态图标

### 1.1 设计原则

1. **最小侵入原则**：尽量复用现有的 `NoteExporter` 接口和导出器实现
2. **状态驱动 UI**：通过 `syncStatus` 字段驱动 UI 显示，避免重复状态管理
3. **异步非阻塞**：所有导出操作在后台执行，不阻塞 UI 线程
4. **错误容错**：批量导出中单条失败不影响其他笔记，自动同步失败静默处理

### 1.2 核心架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│  MemoryTab                SettingsTab         NoteDetailDialog  │
│  ├─ 批量选择模式           ├─ 自动同步开关      ├─ 导出按钮       │
│  ├─ 批量操作栏             ├─ 导出器配置        ├─ 同步状态       │
│  └─ 同步状态图标           └─ 高级设置          └─ 重新导出       │
└────────────────┬────────────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────────────┐
│                    Service Layer                               │
├─────────────────────────────────────────────────────────────────┤
│  NoteExportService           NoteService                       │
│  ├─ exportBatch()            ├─ saveNote()                     │
│  ├─ exportAndAutoSync()      └─ triggerAutoSync()              │
│  ├─ getSyncStatus()                                           │
│  └─ isAutoSyncEnabled                                          │
└────────────────┬────────────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────────────┐
│                    Exporter Layer                              │
├─────────────────────────────────────────────────────────────────┤
│  NoteExporter (interface)                                      │
│  ├─ ObsidianExporter                                           │
│  └─ ZipExporter                                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 详细架构设计

### 2.1 数据模型变更

#### 2.1.1 `BonioNote` 模型扩展

现有 `syncStatus` 字段已存在，无需新增字段。增强 `syncStatus` 的语义：

```dart
/// syncStatus 结构：
/// {
///   "obsidian": "2026-05-17T14:30:00.000Z",  // ISO8601 时间戳
///   "zip": "2026-05-18T10:00:00.000Z"
/// }
/// 
/// 含义：
/// - 键存在：已同步到该目标
/// - 键不存在：未同步到该目标
/// - 时间戳：最后一次同步时间
```

**无变更**：现有模型已满足需求。

#### 2.1.2 新增 `BatchExportResult` 模型

```dart
/// 批量导出结果
class BatchExportResult {
  final int total;       // 总数
  final int succeeded;   // 成功数
  final int failed;      // 失败数
  final List<String> failedNoteIds;  // 失败的笔记 ID
  final String? exporterId;  // 使用的导出器 ID
  
  const BatchExportResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    this.failedNoteIds = const [],
    this.exporterId,
  });
  
  bool get isFullySuccessful => failed == 0;
}
```

**新增文件**：`desktop/lib/models/note_export_models.dart`

---

### 2.2 服务层设计

#### 2.2.1 `NoteExportService` 增强

**文件**：`desktop/lib/services/note_export_service.dart`

**新增配置字段**：

```dart
class NoteExportService extends ChangeNotifier {
  // ... 现有字段 ...
  
  // 新增：自动同步开关
  bool _autoSyncEnabled = false;
  
  bool get autoSyncEnabled => _autoSyncEnabled;
  
  @override
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _defaultExporterId = _prefs.getString('note_export_default_id') ?? '';
    _obsidianVaultPath = _prefs.getString('note_export_obsidian_vault') ?? '';
    _obsidianSubFolder = _prefs.getString('note_export_obsidian_subfolder') ?? 'BoJi-Inbox';
    _autoSyncEnabled = _prefs.getBool('note_export_auto_sync') ?? false;  // 新增
    _initialized = true;
    notifyListeners();
  }
  
  Future<void> updateConfig({
    String? defaultExporterId,
    String? obsidianVaultPath,
    String? obsidianSubFolder,
    bool? autoSyncEnabled,  // 新增参数
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
    if (autoSyncEnabled != null) {  // 新增
      _autoSyncEnabled = autoSyncEnabled;
      await _prefs.setBool('note_export_auto_sync', autoSyncEnabled);
    }
    notifyListeners();
  }
  
  // ... 现有方法 ...
}
```

**新增方法**：

```dart
/// 批量导出笔记列表
/// 
/// 参数：
/// - notes: 要导出的笔记列表
/// - exporter: 使用的导出器（如果为 null，使用默认配置的导出器）
/// - onProgress: 进度回调，(当前索引, 总数, 笔记)
/// 
/// 返回：BatchExportResult
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

/// 检查笔记是否已同步到指定目标
bool isNoteSynced(BonioNote note, String exporterId) {
  return note.syncStatus?.containsKey(exporterId) ?? false;
}

/// 获取笔记的同步状态摘要（用于 UI 显示）
Map<String, DateTime> getNoteSyncSummary(BonioNote note) {
  if (note.syncStatus == null) return {};
  return note.syncStatus!.map(
    (key, value) => MapEntry(key, DateTime.parse(value)),
  );
}

/// 触发自动同步（由 NoteService 调用）
/// 
/// 如果启用了自动同步且配置了默认导出器，则自动导出
/// 失败时静默处理，不抛出异常
Future<void> triggerAutoSync(BonioNote note) async {
  if (!_autoSyncEnabled || _defaultExporterId.isEmpty) {
    return;
  }

  final exporter = getConfiguredExporter();
  if (exporter == null) return;

  try {
    await export(note, exporter);
  } catch (e) {
    // 静默处理自动同步失败
    log.warn('NoteExportService: auto-sync failed for ${note.id}: $e');
  }
}
```

#### 2.2.2 `NoteService` 集成

**文件**：`desktop/lib/services/note_service.dart`

**修改 `saveNote` 方法**：

```dart
Future<BonioNote> saveNote(BonioNote note, {Uint8List? attachment}) async {
  await init();
  if (attachment != null) {
    final attachFile = File('${_attachDir.path}/${note.fileName}');
    await attachFile.writeAsBytes(attachment);
  }
  _notes.insert(0, note);
  await _saveIndex();
  notifyListeners();
  
  // 新增：触发自动同步
  // 注意：这里通过回调而非直接依赖，避免循环依赖
  _onNoteSaved?.call(note);
  
  return note;
}

/// 新增：笔记保存完成回调
void Function(BonioNote note)? _onNoteSaved;

/// 设置自动同步回调
void setAutoSyncCallback(void Function(BonioNote) callback) {
  _onNoteSaved = callback;
}
```

**初始化时建立连接**（在 `AppState` 中）：

```dart
// desktop/lib/providers/app_state.dart

class AppState extends ChangeNotifier {
  // ... 现有代码 ...
  
  @override
  Future<void> init() async {
    // ... 现有初始化 ...
    
    // 新增：建立自动同步连接
    _runtime.noteService.setAutoSyncCallback((note) {
      _runtime.noteExportService.triggerAutoSync(note);
    });
  }
}
```

---

### 2.3 UI 层设计

#### 2.3.1 Memory Tab 批量选择模式

**文件**：`desktop/lib/ui/screens/memory_tab.dart`

**新增状态**：

```dart
class _MemoryTabState extends State<MemoryTab> {
  // ... 现有状态 ...
  
  // 新增：批量选择模式
  bool _isSelectionMode = false;
  final Set<String> _selectedNoteIds = {};
  
  // 切换选择模式
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedNoteIds.clear();
      }
    });
  }
  
  // 选择/取消选择单个笔记
  void _toggleNoteSelection(String noteId) {
    setState(() {
      if (_selectedNoteIds.contains(noteId)) {
        _selectedNoteIds.remove(noteId);
      } else {
        _selectedNoteIds.add(noteId);
      }
    });
  }
  
  // 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedNoteIds.length == notes.length) {
        _selectedNoteIds.clear();
      } else {
        _selectedNoteIds.addAll(notes.map((n) => n.id));
      }
    });
  }
}
```

**AppBar 修改**：

```dart
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
        onPressed: _toggleSelectAll,
      ),
      IconButton(
        icon: const Icon(Icons.sync_alt),
        tooltip: '批量导出',
        onPressed: _handleBatchExport,
      ),
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: '取消',
        onPressed: _toggleSelectionMode,
      ),
    ],
    // 原有的刷新按钮（在选择模式下隐藏）
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
```

**笔记卡片修改**（添加选择框和同步状态图标）：

```dart
Widget _buildNoteCard(BonioNote note, NoteService service) {
  final cs = Theme.of(context).colorScheme;
  final hasThumb = note.thumbnail != null;
  final isSelected = _selectedNoteIds.contains(note.id);
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
            if (_isSelectionMode) {
              _toggleNoteSelection(note.id);
            } else {
              _showDetail(context, note);
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              _toggleSelectionMode();
              _toggleNoteSelection(note.id);
            }
          },
          child: Column(/* 原有内容 */),
        ),
        // 同步状态图标（右上角）
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
        // 选择模式下显示复选框
        if (_isSelectionMode)
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
                onChanged: (_) => _toggleNoteSelection(note.id),
              ),
            ),
          ),
      ],
    ),
  );
}

({IconData icon, Color color})? _getSyncStatusIcon(BonioNote note, ColorScheme cs) {
  final status = note.syncStatus;
  if (status == null || status.isEmpty) return null;
  
  // 如果已同步到 Obsidian
  if (status.containsKey('obsidian')) {
    return (icon: Icons.cloud_done, color: Colors.green);
  }
  
  // 如果已同步到 ZIP
  if (status.containsKey('zip')) {
    return (icon: Icons.archive, color: cs.primary);
  }
  
  return null;
}
```

**批量导出处理**：

```dart
void _handleBatchExport() async {
  if (_selectedNoteIds.isEmpty) return;

  final appState = context.read<AppState>();
  final exportService = appState.runtime.noteExportService;
  final noteService = appState.runtime.noteService;

  if (exportService.defaultExporterId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先在设置中配置默认的笔记同步目标')),
    );
    return;
  }

  final selectedNotes = noteService.notes
      .where((n) => _selectedNoteIds.contains(n.id))
      .toList();

  // 显示进度对话框
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
      _toggleSelectionMode();  // 退出选择模式
    }
  });
}

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
```

**批量导出对话框组件**：

```dart
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
```

#### 2.3.2 Settings Tab 自动同步开关

**文件**：`desktop/lib/ui/screens/settings_tab.dart`

**在笔记同步卡片中添加**：

```dart
// 在 "默认同步目标" 下拉菜单之前添加
SwitchListTile.adaptive(
  contentPadding: EdgeInsets.zero,
  title: const Text('自动同步'),
  subtitle: Text(
    '新创建的笔记将自动导出到配置的目标',
    style: TextStyle(fontSize: 12),
  ),
  value: appState.runtime.noteExportService.autoSyncEnabled,
  onChanged: (v) {
    appState.runtime.noteExportService.updateConfig(
      autoSyncEnabled: v,
    );
  },
),
const SizedBox(height: 12),
```

#### 2.3.3 笔记详情对话框增强

**文件**：`desktop/lib/ui/screens/memory_tab.dart`

**在 `_showDetail` 方法中添加同步状态显示**：

```dart
// 在 Header 部分添加同步状态
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
```

---

### 2.4 错误处理与边界情况

#### 2.4.1 批量导出错误处理

**策略**：继续执行，收集失败项，最后汇总报告

```dart
// 在 exportBatch 中
try {
  final result = await export(note, actualExporter);
  if (result.success) {
    succeeded++;
  } else {
    failed++;
    failedIds.add(note.id);
  }
} catch (e) {
  // 单条笔记失败不影响其他笔记
  failed++;
  failedIds.add(note.id);
  log.error('Batch export failed for ${note.id}: $e');
}
```

#### 2.4.2 自动同步错误处理

**策略**：静默失败，不干扰用户操作

```dart
// 在 triggerAutoSync 中
try {
  await export(note, exporter);
} catch (e) {
  // 静默处理，不抛出异常
  log.warn('NoteExportService: auto-sync failed for ${note.id}: $e');
}
```

#### 2.4.3 配置不完整处理

**策略**：在批量导出开始前检查配置

```dart
void _handleBatchExport() async {
  // ... 前置校验 ...
  
  if (exportService.defaultExporterId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先在设置中配置默认的笔记同步目标')),
    );
    return;
  }
  
  // Obsidian 需要额外检查路径
  if (exportService.defaultExporterId == 'obsidian' && 
      exportService.obsidianVaultPath.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先在设置中配置 Obsidian Vault 路径')),
    );
    return;
  }
  
  // ... 继续导出 ...
}
```

#### 2.4.4 网络断开处理

由于是本地文件操作，不存在网络问题。但需处理文件系统异常：

```dart
try {
  await mdFile.writeAsString(finalMarkdown);
} on FileSystemException catch (e) {
  return ExportResult.failure('文件写入失败: ${e.message}');
} catch (e) {
  return ExportResult.failure('导出失败: $e');
}
```

---

### 2.5 性能考虑

#### 2.5.1 批量导出性能

- **问题**：大量笔记导出可能耗时较长
- **方案**：
  1. 显示进度反馈
  2. 使用异步串行处理（避免并发写文件冲突）
  3. 可考虑限制单次批量操作数量（如最多 100 条）

#### 2.5.2 自动同步性能影响

- **问题**：自动同步可能延迟笔记保存
- **方案**：
  1. 使用 `unawaited()` 不等待导出完成
  2. 导出操作完全异步，不阻塞 `saveNote` 返回

```dart
// NoteService.saveNote 中
unawaited(_onNoteSaved?.call(note));  // 不等待完成
```

#### 2.5.3 UI 响应性

- **问题**：同步状态更新可能导致频繁重绘
- **方案**：
  1. 使用 `ValueNotifier` 局部更新
  2. 卡片级优化：仅当 `syncStatus` 变化时重绘

---

## 3. 文件变更清单

### 3.1 新增文件

| 文件路径 | 说明 |
|---------|------|
| `desktop/lib/models/note_export_models.dart` | 批量导出结果模型 |
| `desktop/lib/ui/widgets/batch_export_dialog.dart` | 批量导出进度对话框 |

### 3.2 修改文件

| 文件路径 | 修改内容 |
|---------|----------|
| `desktop/lib/services/note_export_service.dart` | 添加自动同步配置、批量导出方法、状态查询方法 |
| `desktop/lib/services/note_service.dart` | 添加自动同步回调机制 |
| `desktop/lib/providers/app_state.dart` | 建立自动同步连接 |
| `desktop/lib/ui/screens/memory_tab.dart` | 添加批量选择模式、同步状态图标、批量导出处理 |
| `desktop/lib/ui/screens/settings_tab.dart` | 添加自动同步开关 |

### 3.3 无需修改的文件

| 文件路径 | 说明 |
|---------|------|
| `desktop/lib/services/exporters/note_exporter.dart` | 接口无需变更 |
| `desktop/lib/services/exporters/obsidian_exporter.dart` | 实现无需变更 |
| `desktop/lib/services/exporters/zip_exporter.dart` | 实现无需变更 |
| `desktop/lib/models/note_models.dart` | `syncStatus` 已存在 |

---

## 4. 实施顺序建议

### Phase 1: 基础架构（2-3 天）
1. 创建 `note_export_models.dart`
2. 扩展 `NoteExportService`（批量导出、状态查询）
3. 添加自动同步配置和触发逻辑
4. `NoteService` 集成自动同步回调

### Phase 2: UI 实现（3-4 天）
1. Memory Tab 批量选择模式
2. 批量导出进度对话框
3. 笔记卡片同步状态图标
4. Settings Tab 自动同步开关
5. 笔记详情同步状态显示

### Phase 3: 测试与优化（2-3 天）
1. 功能测试
2. 边界情况测试
3. 性能优化
4. 错误处理完善

---

## 5. 测试要点

### 5.1 功能测试

| 测试场景 | 预期结果 |
|---------|----------|
| 单条笔记手动导出 | 成功导出，更新 `syncStatus` |
| 批量导出已同步笔记 | 覆盖而非新建 |
| 批量导出混合笔记 | 全部导出，状态正确更新 |
| 自动同步开关开启 | 新笔记自动导出 |
| 自动同步开关关闭 | 新笔记不自动导出 |
| 配置不完整时批量导出 | 提示先配置，不执行导出 |

### 5.2 边界测试

| 测试场景 | 预期结果 |
|---------|----------|
| 批量导出 0 条笔记 | 无操作或提示 |
| 批量导出大量笔记（100+） | 显示进度，正常完成 |
| 导出过程中文件系统错误 | 单条失败，其他继续 |
| Obsidian Vault 路径不存在 | 提示错误，不崩溃 |
| 自动同步失败 | 静默失败，不影响笔记保存 |

### 5.3 UI 测试

| 测试场景 | 预期结果 |
|---------|----------|
| 笔记卡片显示同步状态图标 | 正确显示已同步状态 |
| 长按卡片进入选择模式 | 显示复选框，高亮选中项 |
| 批量操作栏显示选中计数 | 实时更新 |
| 进度对话框显示当前进度 | 正确反映导出进度 |

---

## 6. 未来扩展预留

### 6.1 更多导出器支持

架构已支持通过实现 `NoteExporter` 接口添加新导出器：
- `LogseqExporter`
- `NotionExporter`
- `EvernoteExporter`

### 6.2 同步冲突处理

预留 `syncStatus` 扩展为更复杂结构：

```dart
// 未来可能的扩展
class SyncStatusEntry {
  final DateTime timestamp;
  final String? externalId;
  final String? externalUrl;
  final SyncState state;  // synced, pending, failed
}
```

### 6.3 增量同步

可通过监听文件系统变化实现增量同步，但本期不实现。

---

## 7. 附录

### 7.1 术语表

| 术语 | 说明 |
|------|------|
| 批量导出 | 一次性导出多条笔记 |
| 自动同步 | 新笔记创建后自动导出 |
| 同步状态 | 笔记已导出到哪些目标的记录 |
| 导出器 | 实现 `NoteExporter` 接口的类 |

### 7.2 关键决策记录

| 决策 | 理由 |
|------|------|
| 自动同步静默失败 | 不干扰用户主流程，保证笔记保存优先 |
| 批量导出串行处理 | 避免文件系统并发冲突，简化错误处理 |
| 状态驱动 UI | 单一数据源，避免状态不一致 |
| 最小侵入原则 | 复用现有代码，降低风险 |

---

**文档结束**
