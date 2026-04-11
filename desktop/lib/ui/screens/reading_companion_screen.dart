import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_strings.dart';

class ReadingCompanionApp extends StatelessWidget {
  final String url;
  final String mainWindowId;
  const ReadingCompanionApp({
    super.key,
    required this.url,
    required this.mainWindowId,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: S.current.readingTitle,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: _ReadingCompanionPage(url: url, mainWindowId: mainWindowId),
    );
  }
}

class _HeadingInfo {
  final int level;
  final String text;
  final String id;
  const _HeadingInfo({required this.level, required this.text, required this.id});
}

class _ReadingCompanionPage extends StatefulWidget {
  final String url;
  final String mainWindowId;
  const _ReadingCompanionPage({required this.url, required this.mainWindowId});

  @override
  State<_ReadingCompanionPage> createState() => _ReadingCompanionPageState();
}

class _ReadingCompanionPageState extends State<_ReadingCompanionPage> {
  final WebviewController _extractorController = WebviewController();
  final WebviewController _editorController = WebviewController();

  List<_HeadingInfo> _headings = [];
  String _extractedText = '';
  String _summary = '';
  String _statusText = '';
  bool _extractorReady = false;
  bool _editorReady = false;
  bool _contentExtracted = false;
  bool _analyzing = false;
  bool _tocExpanded = true;

  @override
  void initState() {
    super.initState();
    _initWindow();
    _initExtractor();
  }

  @override
  void dispose() {
    _extractorController.dispose();
    _editorController.dispose();
    super.dispose();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(S.current.readingTitle);
    await windowManager.setMinimumSize(const Size(350, 400));
  }

  // ---------------------------------------------------------------------------
  // Content extraction WebView
  // ---------------------------------------------------------------------------

  Future<void> _initExtractor() async {
    setState(() => _statusText = S.current.readingExtracting);
    try {
      await _extractorController.initialize();
      await _extractorController.setBackgroundColor(Colors.white);
      await _extractorController.setPopupWindowPolicy(
          WebviewPopupWindowPolicy.deny);

      _extractorController.url.listen((url) {
        debugPrint('Reading extractor: navigated to $url');
      });

      await _extractorController.loadUrl(widget.url);
      await Future.delayed(const Duration(seconds: 3));
      await _extractContent();
    } catch (e) {
      debugPrint('Reading extractor init failed: $e');
      setState(() => _statusText = 'Error: $e');
    }
  }

  Future<void> _extractContent() async {
    try {
      final jsResult = await _extractorController.executeScript('''
        (() => {
          const headings = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].map(h => ({
            level: parseInt(h.tagName[1]),
            text: h.innerText.trim(),
            id: h.id || (h.closest('[id]') ? h.closest('[id]').id : '')
          })).filter(h => h.text.length > 0);

          const article = document.querySelector('article') ||
                          document.querySelector('[role="main"]') ||
                          document.querySelector('main') ||
                          document.querySelector('.post-content') ||
                          document.querySelector('.article-content') ||
                          document.querySelector('.entry-content') ||
                          document.body;
          const text = article ? article.innerText.substring(0, 50000) : '';
          const title = document.title || '';
          return JSON.stringify({ headings, text, title });
        })()
      ''');

      if (jsResult == null || jsResult == 'null') {
        setState(() => _statusText = 'Content extraction returned empty');
        return;
      }

      String jsonStr = jsResult;
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonDecode(jsonStr) as String;
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final headingsList = data['headings'] as List<dynamic>? ?? [];
      final text = data['text'] as String? ?? '';

      final headings = headingsList.map((h) {
        final m = h as Map<String, dynamic>;
        return _HeadingInfo(
          level: (m['level'] as num?)?.toInt() ?? 2,
          text: m['text'] as String? ?? '',
          id: m['id'] as String? ?? '',
        );
      }).toList();

      setState(() {
        _headings = headings;
        _extractedText = text;
        _contentExtracted = true;
        _statusText = S.current.readingAnalyzing;
      });

      await _initEditor();
      await _analyzeContent(text, data['title'] as String? ?? '');
    } catch (e) {
      debugPrint('Content extraction failed: $e');
      setState(() => _statusText = 'Extraction error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Markdown editor WebView
  // ---------------------------------------------------------------------------

  Future<void> _initEditor() async {
    try {
      await _editorController.initialize();
      await _editorController.setBackgroundColor(Colors.white);
      await _editorController.setPopupWindowPolicy(
          WebviewPopupWindowPolicy.deny);

      final htmlContent = await rootBundle.loadString('assets/reading/editor.html');

      final tempDir = await getTemporaryDirectory();
      final htmlFile = File(
          '${tempDir.path}${Platform.pathSeparator}boji_reading_editor.html');
      await htmlFile.writeAsString(htmlContent);

      await _editorController.loadUrl(htmlFile.uri.toString());
      await Future.delayed(const Duration(seconds: 2));

      setState(() => _editorReady = true);
    } catch (e) {
      debugPrint('Editor init failed: $e');
    }
  }

  Future<void> _setEditorContent(String markdown) async {
    if (!_editorReady) return;
    final escaped = markdown
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '');
    await _editorController.executeScript("setContent('$escaped')");
  }

  Future<String> _getEditorContent() async {
    if (!_editorReady) return _summary;
    final result = await _editorController.executeScript('getContent()');
    if (result == null || result == 'null') return _summary;
    String content = result;
    if (content.startsWith('"') && content.endsWith('"')) {
      content = jsonDecode(content) as String;
    }
    return content;
  }

  // ---------------------------------------------------------------------------
  // LLM analysis
  // ---------------------------------------------------------------------------

  Future<void> _analyzeContent(String text, String title) async {
    setState(() => _analyzing = true);

    final truncated = text.length > 15000 ? text.substring(0, 15000) : text;

    final prompt = StringBuffer();
    prompt.writeln('请阅读以下网页内容，生成结构化的伴读笔记（Markdown格式）。');
    if (title.isNotEmpty) prompt.writeln('标题: $title');
    prompt.writeln('URL: ${widget.url}');
    prompt.writeln();
    prompt.writeln('请按以下格式输出：');
    prompt.writeln('1. 一句话总结（不超过50字）');
    prompt.writeln('2. 核心要点（3-5个要点，每个1-2句话）');
    prompt.writeln('3. 分段摘要（按文章主要段落/章节组织）');
    prompt.writeln('4. 留空的"我的笔记"区域供用户填写');
    prompt.writeln();
    prompt.writeln('直接输出Markdown，不要包含```代码块。');
    prompt.writeln();
    prompt.writeln('--- 网页内容 ---');
    prompt.writeln(truncated);

    try {
      // Build summary locally via simple HTTP-style prompt
      // The companion window runs in a separate engine without direct gateway access,
      // so we generate a template and the user can edit it.
      final summaryMd = StringBuffer();
      summaryMd.writeln('# ${title.isNotEmpty ? title : "阅读笔记"}');
      summaryMd.writeln();
      summaryMd.writeln('> 来源: [${widget.url}](${widget.url})');
      summaryMd.writeln();

      if (_headings.isNotEmpty) {
        summaryMd.writeln('## ${S.current.readingTocTitle}');
        summaryMd.writeln();
        for (final h in _headings) {
          final indent = '  ' * (h.level - 1);
          summaryMd.writeln('$indent- ${h.text}');
        }
        summaryMd.writeln();
      }

      summaryMd.writeln('## 内容摘要');
      summaryMd.writeln();

      // Extract first meaningful paragraphs as summary
      final paragraphs = truncated
          .split(RegExp(r'\n{2,}'))
          .where((p) => p.trim().length > 20)
          .take(5);
      for (final p in paragraphs) {
        final trimmed = p.trim();
        if (trimmed.length > 200) {
          summaryMd.writeln('> ${trimmed.substring(0, 200)}...');
        } else {
          summaryMd.writeln('> $trimmed');
        }
        summaryMd.writeln();
      }

      summaryMd.writeln('## 我的笔记');
      summaryMd.writeln();
      summaryMd.writeln('<!-- 在此处添加你的阅读笔记 -->');
      summaryMd.writeln();

      _summary = summaryMd.toString();
      await _setEditorContent(_summary);

      setState(() {
        _analyzing = false;
        _statusText = '';
      });
    } catch (e) {
      debugPrint('Analysis failed: $e');
      setState(() {
        _analyzing = false;
        _statusText = 'Analysis error: $e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Save to memory
  // ---------------------------------------------------------------------------

  Future<void> _saveToMemory() async {
    final content = await _getEditorContent();
    try {
      if (widget.mainWindowId.isNotEmpty) {
        final main = WindowController.fromWindowId(widget.mainWindowId);
        await main.invokeMethod('readingSave', {
          'url': widget.url,
          'markdown': content,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.current.readingSaveSuccess),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      debugPrint('Save to memory failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  Future<void> _closeWindow() async {
    try {
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  // ---------------------------------------------------------------------------
  // TOC navigation
  // ---------------------------------------------------------------------------

  void _scrollToHeading(_HeadingInfo heading) {
    if (heading.id.isNotEmpty) {
      final uri = Uri.parse('${widget.url}#${heading.id}');
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.current.readingTitle),
        titleSpacing: 12,
        toolbarHeight: 42,
        actions: [
          if (_analyzing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cs.primary),
              ),
            ),
          if (_statusText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(_statusText,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurface.withOpacity(0.6))),
            ),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 20),
            tooltip: S.current.readingSave,
            onPressed: _contentExtracted ? _saveToMemory : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: S.current.readingClose,
            onPressed: _closeWindow,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // TOC panel
          if (_headings.isNotEmpty) _buildTocPanel(cs),
          // Editor
          Expanded(
            child: _editorReady
                ? Webview(_editorController)
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          _contentExtracted
                              ? S.current.readingEditorLoading
                              : S.current.readingExtracting,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTocPanel(ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _tocExpanded = !_tocExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  _tocExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${S.current.readingTocTitle} (${_headings.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_tocExpanded)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: _headings.length,
              itemBuilder: (context, i) {
                final h = _headings[i];
                final indent = 12.0 + (h.level - 1) * 16.0;
                return InkWell(
                  onTap: h.id.isNotEmpty ? () => _scrollToHeading(h) : null,
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: indent, right: 12, top: 3, bottom: 3),
                    child: Text(
                      h.text,
                      style: TextStyle(
                        fontSize: h.level <= 2 ? 13 : 12,
                        fontWeight:
                            h.level <= 2 ? FontWeight.w500 : FontWeight.normal,
                        color: h.id.isNotEmpty
                            ? cs.primary
                            : cs.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        Divider(height: 1, color: cs.outlineVariant),
      ],
    );
  }
}
