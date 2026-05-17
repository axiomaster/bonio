# 产品需求文档 (PRD)：Bonio 笔记导出与同步 (Note Export & Sync)

**文档版本:** V3.0
**状态:** 已确认
**日期:** 2026-05-17
**审查人:** 产品经理

---

## 1. 背景与目标

Bonio 已经具备了"记一记"（Memory）和"阅读搭子"等核心伴随功能，能够高效地捕捉屏幕截图、文本片段并由 AI 提取结构化摘要。然而，长期的知识管理（PKM, Personal Knowledge Management）和深度编辑通常需要用户依赖自己习惯的专业笔记软件（如 Obsidian）。

Bonio 的定位是"智能伴随与捕捉入口"，而非"重度笔记编辑器"。因此，我们的目标是：**将 Bonio 作为知识收集的"触角"，并将捕获且经过 AI 结构化的知识，无缝、极简地流转到用户的主力笔记应用中。**

### 1.1 核心价值

- **极简流转**：一键完成从 Bonio 到目标笔记应用的导出
- **本地优先**：纯本地文件互操作，无需云端中转，保护隐私
- **格式兼容**：生成的 Markdown 文件天然兼容主流本地笔记应用
- **零学习成本**：无需在目标应用中安装任何插件或配置

### 1.2 本期范围（V1.0）

**核心功能：**
- ✅ Obsidian 本地 Vault 导出（完整支持）
- ✅ ZIP 归档导出（通用备选方案）
- ✅ 单条笔记手动导出
- ✅ **批量选择导出**（多选模式，勾选后批量导出）
- ✅ **自动同步开关**（新笔记自动导出到 Obsidian）
- ✅ **同步状态可视化**（笔记卡片显示已同步标识和时间）

**明确不纳入本期范围：**
- 云端笔记 API（Notion, Evernote 等）
- Logseq 等其他本地笔记应用（后续迭代）

---

## 2. 竞品调研与分析

### 2.1 usememos/memos
*   **产品形态**：开源轻量级备忘录中心
*   **同步机制**：Pull 模式，依赖目标应用主动拉取
*   **优缺点**：
    *   *优点*：API 扩展性强
    *   *缺点*：需要用户在目标应用中折腾安装插件，学习成本高

### 2.2 SimpRead 同步助手 (简悦 SyncHelper)
*   **产品形态**：配合浏览器扩展的本地桌面端程序
*   **同步机制**：Push 模式，直接在本地磁盘生成文件
*   **优缺点**：
    *   *优点*：极客友好，利用文件系统 API，支持所有本地 Markdown 工具
    *   *缺点*：需要本地客户端（Bonio 已满足）

### 2.3 Bonio 的选择

鉴于 Bonio 是本地桌面应用，采用类似简悦的 **本地直接推送 (Push) 模式**，直接读写本地文件系统。用户体验最无感，开发成本最低。

---

## 3. 功能详细设计

### 3.1 核心功能特性

#### 3.1.1 纯本地文件互操作 (File-System Integration)
- 用户在设置中配置目标应用的本地路径（如 Obsidian Vault）
- Bonio 将笔记转化为 Markdown 文件并直接写入目标目录
- 无需任何网络请求或第三方服务

#### 3.1.2 资源本地化兜底
- 截图/图片附件自动复制到目标应用的附件目录
- Markdown 中的图片语法转换为目标应用友好的格式
  - Obsidian: `![[image.png]]` (Wiki Link)
  - ZIP: 标准 Markdown `![](attachments/image.png)`

#### 3.1.3 元数据保留
- AI 生成的标签转换为 YAML Frontmatter
- 来源 URL、创建时间等元数据完整保留
- 示例：
  ```yaml
  ---
  tags:
    - 阅读搭子
    - 技术
  source: https://example.com/article
  date: 2026-05-17T14:30:00.000
  ---
  ```

#### 3.1.4 URL Scheme 深度链接
- 导出成功后，可通过 URL Scheme 直接唤起目标应用
- Obsidian: `obsidian://open?vault=VaultName&file=BoJi-Inbox/note.md`
- 用户无需手动导航到目标文件

#### 3.1.5 同步状态跟踪
- 每条笔记记录 `syncStatus` 字段（JSON Map）
- 记录每次成功导出的目标 ID 和时间戳
- **UI 可视化**：笔记卡片上显示同步状态标识

#### 3.1.6 自动同步（新增）
- 设置中提供"自动同步"开关
- 开启后，每条新笔记自动导出到默认目标（仅 Obsidian）
- 静默失败处理：自动同步失败不阻断用户操作，仅记录日志

#### 3.1.7 批量导出（新增）
- Memory 页面提供"批量选择"模式
- 用户可勾选多条笔记后批量导出
- 显示批量进度（如"正在导出 3/10..."）

### 3.2 交互流程设计

#### 3.2.1 全局配置 (Settings)

**入口**：设置 → "笔记同步" 配置卡片

**配置项**：
1. **自动同步**（新增）
   - Switch 开关：开启/关闭
   - 默认值：关闭
   - 说明："开启后，每条新笔记会自动导出到 Obsidian"

2. **默认同步目标**（下拉选择）
   - 无 (仅手动保存)
   - Obsidian (本地)
   - ZIP 归档 (手动)

3. **Obsidian Vault 路径**（仅当选择 Obsidian 时显示）
   - 文件夹选择器（FilePicker）
   - 显示当前路径或"未设置"提示

4. **存放子目录**（仅当选择 Obsidian 时显示）
   - 默认值：`BoJi-Inbox`
   - 可自定义，避免弄乱用户 Vault 根目录

**配置持久化**：
- 使用 SharedPreferences 存储
- Key: `note_export_auto_sync`, `note_export_default_id`, `note_export_obsidian_vault`, `note_export_obsidian_subfolder`

#### 3.2.2 单条笔记导出

**入口**：Memory 页面 → 笔记卡片 → 详情对话框

**触发方式**：
1. 用户点击笔记卡片查看详情
2. 在详情对话框中点击"导出/同步"按钮（图标：`sync_alt`）

**前置校验**：
- 检查是否已配置默认同步目标
- 如未配置，显示 SnackBar 提示："请先在设置中配置默认的笔记同步目标"

**执行与反馈**：
- 显示加载状态
- 导出成功后显示 SnackBar，提供"打开"按钮
- 失败时显示错误信息

#### 3.2.3 批量导出（新增）

**入口**：Memory 页面

**交互流程**：
1. 用户点击"批量选择"按钮（AppBar 右侧）
2. 进入批量选择模式：
   - 笔记卡片右上角显示复选框
   - 底部出现操作栏："已选择 X 条" + "导出" 按钮
3. 用户勾选需要导出的笔记
4. 点击"导出"按钮
5. 显示批量进度对话框：
   ```
   正在导出笔记到 Obsidian...
   ████████░░░░░░░░ 4/10
   ```
6. 完成后显示结果：成功 X 条，失败 X 条

**前置校验**：
- 检查是否已配置默认同步目标
- 如未配置，提示用户先配置

**错误处理**：
- 单条失败不影响其他笔记
- 完成后列出失败的笔记及原因

#### 3.2.4 自动同步流程（新增）

**触发时机**：
- `NoteService.saveNote()` 成功后
- 仅当"自动同步"开关开启且配置了 Obsidian 时

**执行方式**：
- 静默后台执行
- 不显示加载状态，避免打断用户
- 失败时仅在日志中记录，不弹窗提示

**冲突处理**：
- 如果用户正在手动导出同一条笔记，跳过自动同步
- 使用互斥锁避免并发冲突

#### 3.2.5 同步状态可视化（新增）

**笔记卡片上的标识**：
- 已同步到 Obsidian：显示小图标（`cloud_done`），绿色
- 同步时间：卡片底部显示"已同步于 2 小时前"（相对时间）
- 未同步：不显示标识

**笔记详情中的同步历史**：
- 在详情对话框中新增"同步记录"区域
- 显示格式：
  ```
  同步记录
  ━━━━━━━━━━━━━━━
  Obsidian  2026-05-17 14:30  [打开]
  ZIP       2026-05-16 10:00
  ```

#### 3.2.6 ZIP 导出流程

当选择"ZIP 归档"时：
1. 弹出系统文件保存对话框（FilePicker.saveFile）
2. 用户选择保存位置和文件名
3. 生成 ZIP 文件，包含：
   - 主 Markdown 文件
   - 所有附件（保持原始文件名）

**批量导出 ZIP 时**：
- 所有笔记打包到一个 ZIP 中
- 文件结构：
  ```
  archive.zip
  ├── note1.md
  ├── note2.md
  └── attachments/
      ├── image1.png
      └── image2.png
  ```

### 3.3 数据模型设计

#### 3.3.1 BonioNote 扩展字段

```dart
class BonioNote {
  // ... 现有字段 ...

  /// 同步状态记录：目标ID -> ISO8601时间戳
  /// 示例：{"obsidian": "2026-05-17T14:30:00.000Z", "zip": "2026-05-18T10:00:00.000Z"}
  Map<String, String>? syncStatus;
}
```

**实现状态**：✅ 已在 `note_models.dart` 中实现

#### 3.3.2 导出结果模型

```dart
class ExportResult {
  final bool success;
  final String? message;        // 成功时的描述信息
  final String? error;          // 失败时的错误信息
  final String? externalUrl;    // URL Scheme（如 obsidian://...）
}
```

**实现状态**：✅ 已在 `note_exporter.dart` 中实现

#### 3.3.3 导出器接口

```dart
abstract class NoteExporter {
  String get id;        // 唯一标识（如 'obsidian', 'zip'）
  String get name;      // 显示名称（如 'Obsidian', 'ZIP Archive'）

  Future<ExportResult> exportNote(
    BonioNote note,
    String markdownContent,
    List<File> attachments,
  );
}
```

**实现状态**：✅ 已实现
- `ObsidianExporter`：✅ 已实现
- `ZipExporter`：✅ 已实现

#### 3.3.4 导出服务扩展（新增）

**自动同步支持**：
```dart
class NoteExportService extends ChangeNotifier {
  // ... 现有字段 ...

  bool _autoSyncEnabled = false;

  bool get autoSyncEnabled => _autoSyncEnabled;

  Future<void> updateConfig({
    bool? autoSyncEnabled,
    // ... 其他配置 ...
  }) async {
    if (autoSyncEnabled != null) {
      _autoSyncEnabled = autoSyncEnabled;
      await _prefs.setBool('note_export_auto_sync', autoSyncEnabled);
    }
    // ...
  }

  /// 自动同步单条笔记（静默执行）
  Future<void> autoSyncNote(BonioNote note) async {
    if (!_autoSyncEnabled) return;
    final exporter = getConfiguredExporter();
    if (exporter == null) return;

    try {
      await export(note, exporter);
    } catch (e) {
      // 静默失败，仅记录日志
      log.error('Auto sync failed for ${note.id}: $e');
    }
  }

  /// 批量导出笔记列表
  Future<BatchExportResult> exportBatch(List<BonioNote> notes) async {
    final exporter = getConfiguredExporter();
    if (exporter == null) {
      return BatchExportResult(success: 0, failed: notes.length, errors: {});
    }

    int success = 0;
    int failed = 0;
    final errors = <String, String>{};

    for (final note in notes) {
      final result = await export(note, exporter);
      if (result.success) {
        success++;
      } else {
        failed++;
        errors[note.id] = result.error ?? 'Unknown error';
      }
    }

    return BatchExportResult(
      success: success,
      failed: failed,
      errors: errors,
    );
  }
}

class BatchExportResult {
  final int success;
  final int failed;
  final Map<String, String> errors; // noteId -> errorMessage
}
```

**实现状态**：❌ 需要新增

### 3.4 错误处理

#### 3.4.1 配置错误
- **Obsidian 路径未设置**：提示用户先在设置中配置
- **Obsidian 路径不存在**：提示用户检查路径，或自动尝试创建

#### 3.4.2 文件系统错误
- **权限不足**：捕获异常，提示用户检查文件夹权限
- **磁盘空间不足**：捕获异常，提示用户清理磁盘

#### 3.4.3 URL Scheme 失败
- **目标应用未安装**：`url_launcher` 可能返回 false
- 静默处理，不阻断导出流程

### 3.5 Markdown 生成规则

#### 3.5.1 Frontmatter 格式

优先使用 YAML Frontmatter（Obsidian 标准格式）：

```yaml
---
tags:
  - 阅读搭子
  - 技术
source: https://example.com/article
date: 2026-05-17T14:30:00.000Z
---

# 文章标题（如果有）

AI 生成的摘要内容...

```

#### 3.5.2 图片链接转换规则

- **Obsidian 导出**：
  - 标准 Markdown 图片 `![](image.png)` → Wiki 链接 `![[image.png]]`
  - 附件存储在 `{subfolder}/attachments/` 目录

- **ZIP 导出**：
  - 保持标准 Markdown 语法 `![](attachments/image.png)`
  - 附件与 Markdown 文件打包在同一 ZIP 根目录

#### 3.5.3 文件命名规则

- **格式**：`{sourceApp}_{id前8位}.md`
- **冲突处理**：自动添加后缀 `_1`, `_2`, ... 避免覆盖（永不覆盖已有文件）
- **特殊字符清理**：替换 `< > : " / \ | ? *` 为 `_`

**实现状态**：✅ 已在 `ObsidianExporter` 和 `ZipExporter` 中实现

---

## 4. 用户界面设计

### 4.1 设置页面

**位置**：设置标签页 → 新增卡片"笔记同步 (Note Sync)"

**布局**：
```
┌─────────────────────────────────────────────────────┐
│ 笔记同步 (Note Sync)                        [sync]   │
│                                                     │
│ 将"记一记"和"阅读搭子"的内容快捷同步到你常用的        │
│ 笔记软件中。                                         │
│                                                     │
│ 自动同步          [OFF]                             │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│ 开启后，每条新笔记会自动导出到 Obsidian              │
│                                                     │
│ 默认同步目标:      [无 (仅手动保存) ▼]               │
│                                                     │
│ Vault 路径:        未设置                    [选择]  │
│                                                     │
│ 存放子目录:        [BoJi-Inbox              ]       │
└─────────────────────────────────────────────────────┘
```

**实现状态**：
- ✅ 基础配置界面已实现（`settings_tab.dart`）
- ❌ 需要新增"自动同步"开关

**交互说明**：
- 自动同步开关开启时，下方配置项才可编辑
- 下拉菜单选择目标时，对应配置项动态显示/隐藏
- "选择"按钮打开系统文件夹选择对话框
- 子目录输入框支持实时编辑，失焦时自动保存

### 4.2 Memory 页面（批量导出）

**普通模式**：
- AppBar 右侧显示"批量选择"按钮（图标：`checklist`）
- 笔记卡片正常显示

**批量选择模式**：
- AppBar 显示："已选择 X 条" + "取消"按钮 + "导出"按钮
- 笔记卡片右上角显示复选框
- 底部出现操作栏（或使用 AppBar）
- 点击"导出"后显示进度对话框

**实现状态**：❌ 需要新增

### 4.3 笔记卡片（同步状态）

**卡片布局**：
```
┌─────────────────────────────┐
│  [缩略图]                   │
│                             │
│  2026-05-17 14:30           │
│  #阅读搭子 #技术             │
│  AI 生成的摘要内容...        │
│                             │
│  [已同步] 2小时前            │
└─────────────────────────────┘
```

**实现状态**：❌ 需要新增同步状态显示

### 4.4 笔记详情对话框

**新增"同步记录"区域**：
```
┌─────────────────────────────────────┐
│ Chrome                             │
│ 2026-05-17 14:30                   │
│ #阅读搭子 #技术                     │
│                                     │
│ [内容区域...]                       │
│                                     │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│ 同步记录                            │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│ Obsidian  2026-05-17 14:30  [打开] │
│ ZIP       2026-05-16 10:00         │
│                                     │
│ [导出/同步] [删除] [关闭]           │
└─────────────────────────────────────┘
```

**实现状态**：
- ✅ 基础详情对话框已实现（`memory_tab.dart`）
- ❌ 需要新增"同步记录"区域

### 4.5 批量导出进度对话框

```
┌─────────────────────────────────────┐
│         正在导出笔记...             │
│                                     │
│  目标: Obsidian                     │
│                                     │
│  ████████░░░░░░░░ 4/10             │
│                                     │
│  当前: Chrome_abc12345.md           │
└─────────────────────────────────────┘
```

**完成后显示结果**：
```
┌─────────────────────────────────────┐
│         导出完成                    │
│                                     │
│  成功: 8 条                          │
│  失败: 2 条                          │
│                                     │
│  [查看详情] [确定]                   │
└─────────────────────────────────────┘
```

**实现状态**：❌ 需要新增

---

## 5. 技术实现要点

### 5.1 文件操作

- 使用 `dart:io` 的 `File` 和 `Directory` API
- 异步操作避免阻塞 UI 线程
- 错误捕获使用 try-catch，确保不崩溃

**实现状态**：✅ 已在导出器中实现

### 5.2 URL Scheme

- 使用 `url_launcher` 包
- LaunchMode: `LaunchMode.externalApplication`
- 对不同平台做兼容处理（Windows/macOS 路径分隔符）

**实现状态**：✅ 已在 `memory_tab.dart` 中实现

### 5.3 配置持久化

- 使用 `shared_preferences` 包
- Key 命名规范：`note_export_*` 前缀
- 默认值处理：空字符串或 null 时视为"未配置"

**实现状态**：✅ 已在 `NoteExportService` 中实现

### 5.4 图片处理

- 复制文件使用 `File.copy()`
- 生成缩略图使用 `ui.instantiateImageCodec`
- Wiki 链接转换使用正则表达式

**实现状态**：✅ 已在 `ObsidianExporter` 中实现

### 5.5 自动同步互斥锁（新增）

- 使用 `Lock` 或 `Semaphore` 避免并发冲突
- 同一条笔记的自动同步和手动导出不能同时进行
- 实现示例：
  ```dart
  final _syncLocks = <String, Lock>{};

  Future<void> autoSyncNote(BonioNote note) async {
    final lock = _syncLocks.putIfAbsent(note.id, () => Lock());
    if (lock.locked) return; // 正在手动导出，跳过

    await lock.synchronized(() async {
      // 执行导出
    });
  }
  ```

**实现状态**：❌ 需要新增

### 5.6 批量导出进度跟踪（新增）

- 使用 `Stream` 或 `ValueNotifier` 更新进度
- 每完成一条笔记，更新进度
- 实现示例：
  ```dart
  final progressNotifier = ValueNotifier<BatchProgress>(BatchProgress(0, 0));

  Future<BatchExportResult> exportBatch(
    List<BonioNote> notes,
    ValueChanged<BatchProgress>? onProgress,
  ) async {
    for (int i = 0; i < notes.length; i++) {
      await export(notes[i], exporter);
      onProgress?.call(BatchProgress(i + 1, notes.length));
    }
  }
  ```

**实现状态**：❌ 需要新增

---

## 6. 实现状态对照表

| 功能模块 | 子功能 | 实现状态 | 说明 |
|---------|--------|---------|------|
| 数据模型 | BonioNote.syncStatus | ✅ 已实现 | `note_models.dart` |
| | ExportResult | ✅ 已实现 | `note_exporter.dart` |
| | BatchExportResult | ❌ 需要新增 | 批量导出结果 |
| 导出器接口 | NoteExporter | ✅ 已实现 | `note_exporter.dart` |
| | ObsidianExporter | ✅ 已实现 | `obsidian_exporter.dart` |
| | ZipExporter | ✅ 已实现 | `zip_exporter.dart` |
| 导出服务 | NoteExportService | ✅ 已实现 | `note_export_service.dart` |
| | 自动同步支持 | ❌ 需要新增 | autoSyncNote() |
| | 批量导出支持 | ❌ 需要新增 | exportBatch() |
| | 互斥锁机制 | ❌ 需要新增 | 避免并发冲突 |
| 设置界面 | 基础配置卡片 | ✅ 已实现 | `settings_tab.dart` |
| | 自动同步开关 | ❌ 需要新增 | Switch 组件 |
| Memory 界面 | 笔记详情对话框 | ✅ 已实现 | `memory_tab.dart` |
| | 单条导出按钮 | ✅ 已实现 | `sync_alt` 按钮 |
| | 批量选择模式 | ❌ 需要新增 | 多选 UI |
| | 同步状态显示 | ❌ 需要新增 | 卡片上显示 |
| | 同步记录区域 | ❌ 需要新增 | 详情中显示 |
| 进度反馈 | 批量导出进度 | ❌ 需要新增 | 进度对话框 |
| | 单条导出加载 | ✅ 已实现 | SnackBar |

---

## 7. 验收标准

### 7.1 功能验收

**基础功能：**
- [x] 设置页面可以配置 Obsidian Vault 路径
- [x] 可以配置存放子目录名称
- [x] 笔记详情对话框中有"导出/同步"按钮
- [x] 点击按钮可以成功导出到 Obsidian
- [x] 导出成功后显示"打开"按钮，可跳转到 Obsidian
- [x] 未配置时显示提示信息
- [x] ZIP 导出可以选择保存位置并成功生成文件

**新增功能：**
- [ ] 设置中可以开启/关闭自动同步
- [ ] 开启自动同步后，新笔记自动导出到 Obsidian
- [ ] 自动同步失败不阻断用户操作
- [ ] Memory 页面可以进入批量选择模式
- [ ] 可以勾选多条笔记后批量导出
- [ ] 批量导出显示进度和结果
- [ ] 笔记卡片上显示同步状态标识
- [ ] 笔记详情中显示同步历史记录

### 7.2 数据验收

- [x] Markdown 文件包含正确的 YAML Frontmatter
- [x] 图片附件被正确复制到 attachments 目录
- [x] 图片链接被转换为 Wiki 链接格式（Obsidian）
- [x] 笔记的 `syncStatus` 字段被正确更新

### 7.3 用户体验验收

- [x] 导出过程有加载反馈
- [x] 错误信息清晰易懂
- [x] URL Scheme 可以正确唤起 Obsidian
- [x] 同一条笔记重复导出时生成新文件（不覆盖）
- [ ] 批量导出进度流畅，无卡顿
- [ ] 同步状态显示简洁，不干扰浏览
- [ ] 自动同步静默执行，不打断用户

### 7.4 边界情况验收

- [ ] 批量导出时单条失败不影响其他笔记
- [ ] 自动同步和手动导出不会同时执行
- [ ] 未配置时自动同步静默跳过
- [ ] 批量导出空列表时给出提示
- [ ] 文件名冲突时自动添加后缀

---

## 8. 附录

### 8.1 术语表

| 术语 | 说明 |
|------|------|
| Bonio | 本产品名称 |
| Obsidian | 一款本地优先的双链笔记软件 |
| Vault | Obsidian 的笔记库文件夹 |
| Wiki Link | Obsidian 的内部链接语法 `[[...]]` |
| URL Scheme | 应用间跳转协议，如 `obsidian://` |
| YAML Frontmatter | Markdown 文件顶部的元数据块 |

### 8.2 参考链接

- Obsidian 官方文档: https://help.obsidian.md/
- Markdown 规范: https://commonmark.org/
- YAML Frontmatter 规范: https://jekyllrb.com/docs/front-matter/

### 8.3 变更历史

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| V1.0 | 2026-05-17 | 初始版本 |
| V2.0 | 2026-05-17 | 移除云端功能，聚焦本地 |
| V2.1 | 2026-05-17 | 产品经理审查优化，补充细节 |
| V3.0 | 2026-05-17 | **用户确认需求**，新增批量导出、自动同步、同步状态可视化 |

### 8.4 待实现清单（开发优先级）

**P0（高优先级）：**
1. 设置页面新增"自动同步"开关
2. `NoteExportService` 新增 `autoSyncNote()` 方法
3. `NoteService.saveNote()` 调用自动同步
4. 笔记卡片显示同步状态标识

**P1（中优先级）：**
5. Memory 页面批量选择模式 UI
6. `NoteExportService` 新增 `exportBatch()` 方法
7. 批量导出进度对话框
8. 笔记详情新增"同步记录"区域

**P2（低优先级）：**
9. 自动同步互斥锁机制
10. 批量导出错误详情展示
11. 同步时间相对时间显示优化

---

**文档结束**
