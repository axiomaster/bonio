import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/note_models.dart';
import '../models/chat_models.dart';
import '../platform/screen_capture.dart';
import 'gateway_session.dart';
import 'reading_template_store.dart';

class NoteService extends ChangeNotifier {
  static const _notesDirName = 'boji-notes';
  static const _indexFile = 'index.json';
  static const _attachmentsDir = 'attachments';
  static const _thumbnailsDir = 'thumbnails';
  static const _thumbnailWidth = 200;
  static const _analysisSessionKey = 'boji-notes';

  final GatewaySession _session;
  late Directory _notesDir;
  late Directory _attachDir;
  late Directory _thumbDir;
  late File _indexPath;

  List<BojiNote> _notes = [];
  bool _initialized = false;

  /// Pending analysis: runId → accumulated assistant text.
  final Map<String, StringBuffer> _pendingAnalysis = {};

  /// Completers for pending analysis runs, completed when the server sends
  /// a `chat` event with `state: 'final'` for the corresponding runId.
  final Map<String, Completer<String>> _analysisCompleters = {};

  List<BojiNote> get notes => List.unmodifiable(_notes);

  NoteService({required GatewaySession session}) : _session = session;

  Future<void> init() async {
    if (_initialized) return;
    final appDir = await getApplicationSupportDirectory();
    _notesDir = Directory('${appDir.path}/$_notesDirName');
    _attachDir = Directory('${_notesDir.path}/$_attachmentsDir');
    _thumbDir = Directory('${_notesDir.path}/$_thumbnailsDir');
    _indexPath = File('${_notesDir.path}/$_indexFile');

    await _notesDir.create(recursive: true);
    await _attachDir.create(recursive: true);
    await _thumbDir.create(recursive: true);

    await _loadIndex();
    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<void> _loadIndex() async {
    if (!await _indexPath.exists()) {
      _notes = [];
      return;
    }
    try {
      final raw = await _indexPath.readAsString();
      final list = jsonDecode(raw) as List;
      _notes = list
          .map((e) => BojiNote.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('NoteService: failed to load index: $e');
      _notes = [];
    }
  }

  Future<void> _saveIndex() async {
    final json = jsonEncode(_notes.map((n) => n.toJson()).toList());
    await _indexPath.writeAsString(json);
  }

  Future<BojiNote> saveNote(BojiNote note, {Uint8List? attachment}) async {
    await init();
    if (attachment != null) {
      final attachFile = File('${_attachDir.path}/${note.fileName}');
      await attachFile.writeAsBytes(attachment);
    }
    _notes.insert(0, note);
    await _saveIndex();
    notifyListeners();
    return note;
  }

  Future<void> updateNote(BojiNote updated) async {
    final idx = _notes.indexWhere((n) => n.id == updated.id);
    if (idx < 0) return;
    _notes[idx] = updated;
    await _saveIndex();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    final note = _notes.removeAt(idx);
    await _safeDelete(File('${_attachDir.path}/${note.fileName}'));
    if (note.thumbnail != null) {
      await _safeDelete(File('${_thumbDir.path}/${note.thumbnail}'));
    }
    await _saveIndex();
    notifyListeners();
  }

  Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Full path to an attachment file.
  String attachmentPath(String fileName) => '${_attachDir.path}/$fileName';

  /// Full path to a thumbnail file.
  String thumbnailPath(String fileName) => '${_thumbDir.path}/$fileName';

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  /// Capture the given window, save as a note, and return it.
  Future<BojiNote?> captureWindow(int hwnd) async {
    if (hwnd == 0) return null;
    await init();

    debugPrint('NoteService: capturing window hwnd=$hwnd');
    final capture = ScreenCapture.captureWindow(hwnd);
    if (capture == null) {
      debugPrint('NoteService: capture failed');
      return null;
    }

    final title = ScreenCapture.getWindowTitle(hwnd);
    final browserUrl = ScreenCapture.getBrowserUrl(hwnd);
    final png = await capture.toPng();
    if (png == null) {
      debugPrint('NoteService: PNG encode failed');
      return null;
    }

    final id = const Uuid().v4();
    final now = DateTime.now();
    final ts = '${now.year}${_p2(now.month)}${_p2(now.day)}_'
        '${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
    final fileName = '${ts}_${id.substring(0, 8)}.png';
    final thumbName = '${ts}_${id.substring(0, 8)}_thumb.png';

    final thumb = await _generateThumbnail(png, capture.width, capture.height);
    if (thumb != null) {
      final thumbFile = File('${_thumbDir.path}/$thumbName');
      await thumbFile.writeAsBytes(thumb);
    }

    debugPrint('NoteService: captured "$title", url=$browserUrl');

    final note = BojiNote(
      id: id,
      createdAt: now,
      type: NoteType.screenshot,
      sourceApp: title ?? '',
      sourceUrl: browserUrl,
      fileName: fileName,
      thumbnail: thumb != null ? thumbName : null,
    );

    return saveNote(note, attachment: png);
  }

  /// Save dropped content (text, image bytes, or file) as a note.
  Future<BojiNote?> saveDroppedContent({
    required String dropType,
    String? text,
    Uint8List? imageBytes,
    String? filePath,
  }) async {
    await init();

    final id = const Uuid().v4();
    final now = DateTime.now();
    final ts = '${now.year}${_p2(now.month)}${_p2(now.day)}_'
        '${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';

    if (dropType == 'text' && text != null && text.isNotEmpty) {
      final fileName = '${ts}_${id.substring(0, 8)}.txt';
      final note = BojiNote(
        id: id,
        createdAt: now,
        type: NoteType.text,
        sourceApp: '',
        rawText: text,
        fileName: fileName,
      );
      final bytes = utf8.encode(text);
      return saveNote(note, attachment: Uint8List.fromList(bytes));
    }

    if (dropType == 'image' && imageBytes != null) {
      final fileName = '${ts}_${id.substring(0, 8)}.png';
      final thumbName = '${ts}_${id.substring(0, 8)}_thumb.png';
      final thumb = await _generateThumbnailFromPng(imageBytes);
      if (thumb != null) {
        await File('${_thumbDir.path}/$thumbName').writeAsBytes(thumb);
      }
      final note = BojiNote(
        id: id,
        createdAt: now,
        type: NoteType.image,
        sourceApp: '',
        fileName: fileName,
        thumbnail: thumb != null ? thumbName : null,
      );
      return saveNote(note, attachment: imageBytes);
    }

    if (dropType == 'file' && filePath != null) {
      final srcFile = File(filePath);
      if (!await srcFile.exists()) return null;
      final ext = filePath.contains('.') ? filePath.split('.').last : 'bin';
      final baseName = filePath.contains(Platform.pathSeparator)
          ? filePath.split(Platform.pathSeparator).last
          : filePath;
      final fileName = '${ts}_${id.substring(0, 8)}.$ext';
      final destFile = File('${_attachDir.path}/$fileName');
      await srcFile.copy(destFile.path);

      final note = BojiNote(
        id: id,
        createdAt: now,
        type: NoteType.file,
        sourceApp: baseName,
        fileName: fileName,
      );
      return saveNote(note);
    }

    return null;
  }

  /// Save a reading companion note (Markdown text + URL) with #阅读搭子 tag.
  Future<BojiNote> saveReadingNote(String url, String markdown) async {
    await init();

    // Extract title from first markdown heading (# ...)
    final titleMatch = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(markdown);
    final title = titleMatch?.group(1)?.trim() ?? '';
    final summaryText = title.isNotEmpty
        ? title
        : (markdown.length > 80 ? '${markdown.substring(0, 80)}...' : markdown);

    // Deduplicate by URL: update existing note if one exists
    final existing = findByUrl(url);
    if (existing != null) {
      existing.rawText = markdown;
      existing.summary = summaryText;
      existing.analyzed = true;
      await updateNote(existing);
      // Update the attachment file
      final attachFile = File('${_attachDir.path}/${existing.fileName}');
      await attachFile.writeAsString(markdown);
      return existing;
    }

    final id = const Uuid().v4();
    final now = DateTime.now();
    final ts = '${now.year}${_p2(now.month)}${_p2(now.day)}_'
        '${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
    final fileName = '${ts}_${id.substring(0, 8)}.md';
    final note = BojiNote(
      id: id,
      createdAt: now,
      type: NoteType.text,
      sourceApp: '阅读搭子',
      sourceUrl: url,
      rawText: markdown,
      fileName: fileName,
      tags: ['阅读搭子'],
      summary: summaryText,
      analyzed: true,
    );
    return saveNote(note, attachment: Uint8List.fromList(utf8.encode(markdown)));
  }

  // ---------------------------------------------------------------------------
  // Gateway event handling (for async AI analysis responses)
  // ---------------------------------------------------------------------------

  /// Called by NodeRuntime to forward gateway events. Returns true if this
  /// event was consumed (belongs to the boji-notes session).
  bool handleGatewayEvent(String event, String? payloadJson) {
    if (payloadJson == null || _pendingAnalysis.isEmpty) return false;

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(payloadJson) as Map<String, dynamic>?;
    } catch (_) {
      return false;
    }
    if (payload == null) return false;

    final sessionKey = payload['sessionKey'] as String?;
    if (!_matchesAnalysisSession(sessionKey)) return false;

    if (event == 'agent') {
      final stream = payload['stream'] as String?;
      if (stream == 'assistant') {
        final text = _extractDeltaText(payload);
        if (text.isNotEmpty) {
          for (final buf in _pendingAnalysis.values) {
            buf.write(text);
          }
        }
      }
      return true;
    }

    if (event == 'chat') {
      final state = payload['state'] as String?;
      final runId = payload['runId'] as String?;

      if (state == 'delta') {
        final text = _extractDeltaText(payload);
        if (text.isNotEmpty) {
          for (final buf in _pendingAnalysis.values) {
            buf.write(text);
          }
        }
        return true;
      }

      if (state == 'final' || state == 'aborted' || state == 'error') {
        if (runId != null && _analysisCompleters.containsKey(runId)) {
          final text = _pendingAnalysis.remove(runId)?.toString() ?? '';
          _analysisCompleters.remove(runId)?.complete(text);
        } else if (_analysisCompleters.length == 1) {
          final key = _analysisCompleters.keys.first;
          final text = _pendingAnalysis.remove(key)?.toString() ?? '';
          _analysisCompleters.remove(key)?.complete(text);
        }
      }
      return true;
    }

    return false;
  }

  /// OpenClaw canonicalizes session keys, e.g. `boji-notes` may become
  /// `agent:boji-notes:main`. Match flexibly so streaming events are captured.
  static const _readingSessionKey = 'boji-reading';

  /// Match only the note analysis session (not reading).
  bool _matchesAnalysisSession(String? eventKey) {
    if (eventKey == null || eventKey.trim().isEmpty) return false;
    final k = eventKey.trim();
    if (k == _analysisSessionKey) return true;
    if (k.contains(_analysisSessionKey)) return true;
    return false;
  }

  /// Match either note analysis or reading sessions.
  bool _matchesNoteSession(String? eventKey) {
    if (eventKey == null || eventKey.trim().isEmpty) return false;
    final k = eventKey.trim();
    if (k == _analysisSessionKey || k == _readingSessionKey) return true;
    if (k.contains(_analysisSessionKey) || k.contains(_readingSessionKey)) {
      return true;
    }
    return false;
  }

  /// Extract assistant text from either format the server may use:
  ///  - `payload.data.text` / `payload.data.delta`  (agent event)
  ///  - `payload.message.content[{type:"text", text:"..."}]`  (chat delta)
  static String _extractDeltaText(Map<String, dynamic> payload) {
    // Format 1: message.content[].text (used by chat delta events)
    final message = payload['message'] as Map<String, dynamic>?;
    if (message != null) {
      final content = message['content'] as List<dynamic>?;
      if (content != null) {
        for (final item in content) {
          if (item is Map<String, dynamic> && item['type'] == 'text') {
            final t = item['text'] as String?;
            if (t != null && t.isNotEmpty) return t;
          }
        }
      }
    }
    // Format 2: data.text or data.delta (used by agent events)
    final data = payload['data'] as Map<String, dynamic>?;
    if (data != null) {
      final t = data['delta'] as String? ?? data['text'] as String?;
      if (t != null && t.isNotEmpty) return t;
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // AI Analysis
  // ---------------------------------------------------------------------------

  Future<void> analyzeNote(BojiNote note) async {
    try {
      final attachFile = File('${_attachDir.path}/${note.fileName}');
      if (!await attachFile.exists()) return;

      final bytes = await attachFile.readAsBytes();
      final b64 = base64Encode(bytes);

      final isImage = note.type == NoteType.screenshot ||
          note.type == NoteType.image;

      final prompt = StringBuffer();
      prompt.writeln('[记一记] 请分析以下内容，返回JSON格式的分类结果。');
      prompt.writeln('来源窗口: ${note.sourceApp}');
      if (note.sourceUrl != null && note.sourceUrl!.isNotEmpty) {
        prompt.writeln('页面URL: ${note.sourceUrl}');
      }
      if (note.rawText != null && note.rawText!.isNotEmpty) {
        prompt.writeln('文本内容: ${note.rawText}');
      }
      prompt.writeln();
      prompt.writeln('请从以下预定义标签中选择1~3个最匹配的标签（也可以自定义标签）：');
      prompt.writeln('美食, 出游景点, 出游攻略, 电子数码, 种草, 穿搭, 美妆护肤, '
          '家居家装, 健身运动, 萌宠, 母婴育儿, 影视综艺, 音乐, 游戏, '
          '读书笔记, 学习教育, 职场办公, 摄影, 绘画手工, 汽车, '
          '短视频, 搞笑, 情感, 旅行日记, 生活记录, 美图壁纸, '
          '科技资讯, 编程开发, 理财投资, 购物优惠, 医疗健康');
      prompt.writeln();
      prompt.writeln('规则：');
      prompt.writeln('1. 同一条内容可以打多个标签（1~3个），选择最贴切的');
      prompt.writeln('2. 如果预定义标签都不合适，可以自定义一个简短的标签');
      prompt.writeln('3. 给出一句话中文摘要（不超过30字）');
      prompt.writeln();
      prompt.writeln('严格只返回如下JSON（不要包含其他内容）：');
      prompt.writeln('{"tags": ["美食", "种草"], "summary": "一句话摘要"}');

      // Generate a client-side runId for tracking the streaming response
      final runId = const Uuid().v4();
      _pendingAnalysis[runId] = StringBuffer();
      final completer = Completer<String>();
      _analysisCompleters[runId] = completer;

      final params = <String, dynamic>{
        'sessionKey': _analysisSessionKey,
        'message': prompt.toString(),
        'idempotencyKey': runId,
      };

      if (isImage) {
        params['attachments'] = [
          {
            'type': 'image',
            'mimeType': 'image/png',
            'fileName': note.fileName,
            'content': b64,
          }
        ];
      }

      debugPrint('NoteService: sending analysis for ${note.id}, runId=$runId');

      // Send the RPC (returns {runId} immediately, actual response via events)
      final rpcRes = await _session.request(
        'chat.send',
        jsonEncode(params),
        timeoutMs: 60000,
      );
      debugPrint('NoteService: chat.send RPC returned: ${rpcRes.length > 200 ? rpcRes.substring(0, 200) : rpcRes}');

      // The server may assign a different runId — update our tracking
      try {
        final resObj = jsonDecode(rpcRes) as Map<String, dynamic>?;
        final serverRunId = resObj?['runId'] as String?;
        if (serverRunId != null && serverRunId != runId) {
          debugPrint('NoteService: server assigned runId=$serverRunId (was $runId)');
          final buf = _pendingAnalysis.remove(runId);
          _analysisCompleters.remove(runId);
          if (buf != null) _pendingAnalysis[serverRunId] = buf;
          _analysisCompleters[serverRunId] = completer;
        }
      } catch (_) {}

      // Wait for the streaming response to complete (with timeout)
      final assistantText = await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          debugPrint('NoteService: analysis timed out for ${note.id}');
          _pendingAnalysis.remove(runId);
          _analysisCompleters.remove(runId);
          return '';
        },
      );

      debugPrint('NoteService: analysis response (${assistantText.length} chars): '
          '${assistantText.length > 200 ? assistantText.substring(0, 200) : assistantText}');

      _parseAnalysisResponse(note, assistantText);
    } catch (e) {
      debugPrint('NoteService: analysis failed: $e');
      note.tags = ['#未分类'];
      note.summary = note.sourceApp.isNotEmpty ? note.sourceApp : '内容已保存';
      note.analyzed = true;
      await updateNote(note);
    }
  }

  void _parseAnalysisResponse(BojiNote note, String assistantText) {
    try {
      if (assistantText.isEmpty) {
        _fallbackClassify(note);
        return;
      }

      final jsonMatch =
          RegExp(r'\{[^{}]*"tags"[^{}]*\}').firstMatch(assistantText);
      if (jsonMatch != null) {
        final parsed =
            jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final rawTags = (parsed['tags'] as List?)?.cast<String>() ?? [];
        note.tags = _normalizeTags(rawTags);
        note.summary = parsed['summary'] as String? ?? '';
        note.analyzed = true;
        unawaited(updateNote(note));
        debugPrint('NoteService: parsed tags=${note.tags}, summary=${note.summary}');
        return;
      }

      // Fallback: extract #tags from text
      final tagMatches = RegExp(r'#\S+').allMatches(assistantText);
      if (tagMatches.isNotEmpty) {
        note.tags = _normalizeTags(
            tagMatches.map((m) => m.group(0)!).toList());
      } else {
        note.tags = ['未分类'];
      }
      note.summary = assistantText.length > 80
          ? '${assistantText.substring(0, 80)}...'
          : assistantText;
      note.analyzed = true;
      unawaited(updateNote(note));
    } catch (e) {
      debugPrint('NoteService: parse failed: $e');
      _fallbackClassify(note);
    }
  }

  /// Strip leading # and deduplicate, keeping original order.
  static List<String> _normalizeTags(List<String> raw) {
    final seen = <String>{};
    final result = <String>[];
    for (var t in raw) {
      t = t.trim();
      while (t.startsWith('#')) {
        t = t.substring(1);
      }
      t = t.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) result.add(t);
    }
    return result.isEmpty ? ['未分类'] : result;
  }

  void _fallbackClassify(BojiNote note) {
    note.tags = ['未分类'];
    note.summary = note.sourceApp.isNotEmpty ? note.sourceApp : '内容已保存';
    note.analyzed = true;
    unawaited(updateNote(note));
  }

  // ---------------------------------------------------------------------------
  // Reading companion AI summarization
  // ---------------------------------------------------------------------------

  /// Pending reading summaries: runId → accumulated text.
  final Map<String, StringBuffer> _pendingReading = {};
  final Map<String, Completer<String>> _readingCompleters = {};

  /// Find an existing note by URL. Returns null if not found.
  BojiNote? findByUrl(String url) {
    if (url.isEmpty) return null;
    try {
      return _notes.firstWhere(
        (n) => n.sourceUrl == url,
      );
    } catch (_) {
      return null;
    }
  }

  /// Send reading content to the LLM for AI-powered structured summarization.
  /// [category] determines which prompt template to use. When [auto], all
  /// templates are included and the AI auto-classifies. Returns the raw JSON
  /// string from the LLM.
  Future<String> summarizeReading(
      String text, String url, String title,
      {ReadingCategory category = ReadingCategory.auto}) async {
    await init();

    final truncated =
        text.length > 20000 ? text.substring(0, 20000) : text;

    final prompt = StringBuffer();

    if (category == ReadingCategory.auto) {
      // Auto mode: include all templates so the AI picks the right one
      prompt.writeln('# Role');
      prompt.writeln('你是一位全能文章分析专家，能根据文章内容自动选择最合适的分析视角进行摘要总结。');
      prompt.writeln();
      prompt.writeln('# Task');
      prompt.writeln('请先判断文章类别，然后使用对应视角进行分析总结。');
      prompt.writeln();
      prompt.writeln('# 分析视角');
      for (final cat in ReadingCategory.values) {
        if (cat == ReadingCategory.auto || cat.assetFile.isEmpty) continue;
        try {
          final raw = await ReadingTemplateStore.loadPromptTemplate(cat);
          prompt.writeln();
          prompt.writeln('## ${cat.label} (${cat.key})');
          prompt.writeln(ReadingTemplateStore.extractPromptPart(raw));
        } catch (_) {}
      }
    } else {
      // Specific category: use only the selected template
      final templateRaw = await ReadingTemplateStore.loadPromptTemplate(category);
      prompt.writeln(ReadingTemplateStore.extractPromptPart(templateRaw));
    }

    prompt.writeln();
    prompt.writeln('# Additional Requirements');
    prompt.writeln('1. 标题与作者姓名：必须准确提取');
    prompt.writeln('2. 忽略原始文章中"一句话一段"的排版');
    prompt.writeln('3. 分析内容的逻辑流，将描述同一主题的段落合并');
    prompt.writeln('4. 【禁止】不要尝试访问任何URL或使用web_fetch等工具获取网络内容，客户端已将完整文章内容附在下方');
    prompt.writeln('5. 【禁止】不要添加任何无关上下文、额外知识或外部信息，仅基于提供的文章内容进行摘要');
    prompt.writeln();
    if (title.isNotEmpty) prompt.writeln('文章标题: $title');
    if (url.isNotEmpty) prompt.writeln('URL: $url');
    prompt.writeln();
    prompt.writeln('文章内容:');
    prompt.writeln(truncated);
    prompt.writeln();
    prompt.writeln('严格只返回如下JSON（不要包含其他内容）：');
    prompt.writeln('{');
    prompt.writeln('  "title": "准确的文章标题",');
    prompt.writeln('  "author": "作者姓名，没有则为空字符串",');
    prompt.writeln('  "summary": "摘要内容",');
    prompt.writeln('  "paragraph_summaries": [');
    prompt.writeln('    {"subtitle": "语义小标题", "content": "深度总结"},');
    prompt.writeln('    {"subtitle": "语义小标题", "content": "深度总结"},');
    prompt.writeln('    ...');
    prompt.writeln('  ]');
    prompt.writeln('}');

    final runId = const Uuid().v4();
    _pendingReading[runId] = StringBuffer();
    final completer = Completer<String>();
    _readingCompleters[runId] = completer;

    final promptStr = prompt.toString();
    debugPrint('NoteService: summarizeReading sending to server, '
        'category=$category, prompt.length=${promptStr.length}, '
        'text.length=${truncated.length}, runId=$runId');

    try {
      final rpcRes = await _session.request(
        'chat.send',
        jsonEncode({
          'sessionKey': _readingSessionKey,
          'message': promptStr,
          'idempotencyKey': runId,
        }),
        timeoutMs: 60000,
      );

      debugPrint('NoteService: summarizeReading rpcRes=$rpcRes');

      // Update runId if server assigned a different one
      try {
        final resObj = jsonDecode(rpcRes) as Map<String, dynamic>?;
        final serverRunId = resObj?['runId'] as String?;
        if (serverRunId != null && serverRunId != runId) {
          debugPrint('NoteService: remapping runId $runId → $serverRunId');
          final buf = _pendingReading.remove(runId);
          _readingCompleters.remove(runId);
          if (buf != null) _pendingReading[serverRunId] = buf;
          _readingCompleters[serverRunId] = completer;
        }
      } catch (_) {}

      final result = await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          debugPrint('NoteService: reading summary timed out');
          _pendingReading.remove(runId);
          _readingCompleters.remove(runId);
          return '';
        },
      );

      debugPrint('NoteService: summarizeReading result.length=${result.length}, '
          'first 500 chars: ${result.length > 500 ? result.substring(0, 500) : result}');

      // Strip ALL control characters (0x00-0x1F). LLM streaming may inject
      // literal newlines/tabs inside JSON string values, which is invalid JSON.
      final sanitized = result.replaceAll(RegExp(r'[\x00-\x1f]'), '');

      return sanitized;
    } catch (e) {
      debugPrint('NoteService: summarizeReading failed: $e');
      _pendingReading.remove(runId);
      _readingCompleters.remove(runId);
      return '';
    }
  }

  /// Handle gateway events for reading summarization. Returns true if consumed.
  bool handleReadingEvent(String event, String? payloadJson) {
    if (payloadJson == null || _pendingReading.isEmpty) return false;

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(payloadJson) as Map<String, dynamic>?;
    } catch (_) {
      return false;
    }
    if (payload == null) return false;

    final sessionKey = payload['sessionKey'] as String?;
    if (!sessionKey.toString().contains(_readingSessionKey)) return false;

    final serverRunId = payload['runId'] as String?;

    if (event == 'agent') {
      final text = _extractDeltaText(payload);
      if (text.isNotEmpty && serverRunId != null) {
        _pendingReading[serverRunId]?.write(text);
      }
      return true;
    }

    if (event == 'chat') {
      final state = payload['state'] as String?;
      // Only use chat events for completion detection — content comes from
      // agent events above.  Accumulating chat.delta too would duplicate
      // content when the server sends both event types (e.g. OpenClaw).
      if (state == 'final' || state == 'aborted' || state == 'error') {
        if (serverRunId != null) {
          final text = _pendingReading.remove(serverRunId)?.toString() ?? '';
          debugPrint('NoteService: handleReadingEvent chat.$state, '
              'runId=$serverRunId, result.length=${text.length}');
          _readingCompleters.remove(serverRunId)?.complete(text);
        }
      }
      return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Thumbnail generation
  // ---------------------------------------------------------------------------

  Future<Uint8List?> _generateThumbnail(
      Uint8List pngBytes, int srcWidth, int srcHeight) async {
    if (srcWidth <= 0 || srcHeight <= 0) return null;
    try {
      final targetW = _thumbnailWidth;
      final targetH = (srcHeight * targetW / srcWidth).round();
      if (targetH <= 0) return null;

      final codec = await ui.instantiateImageCodec(
        pngBytes,
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      codec.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('NoteService: thumbnail generation failed: $e');
      return null;
    }
  }

  Future<Uint8List?> _generateThumbnailFromPng(Uint8List pngBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final srcWidth = frame.image.width;
      final srcHeight = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return _generateThumbnail(pngBytes, srcWidth, srcHeight);
    } catch (e) {
      debugPrint('NoteService: thumbnail from PNG failed: $e');
      return null;
    }
  }

  static String _p2(int n) => n.toString().padLeft(2, '0');
}
