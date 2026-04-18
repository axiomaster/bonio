import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_strings.dart';

// WebView2 is Windows-only; import unconditionally so the package
// resolves at compile time, but guard all usage with Platform.isWindows.
import 'package:webview_windows/webview_windows.dart';

class ReadingCompanionApp extends StatelessWidget {
  final String url;
  final String browserTitle;
  final String mainWindowId;
  const ReadingCompanionApp({
    super.key,
    required this.url,
    this.browserTitle = '',
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
      home: _ReadingCompanionPage(
          url: url, browserTitle: browserTitle, mainWindowId: mainWindowId),
    );
  }
}

class _HeadingInfo {
  final int level;
  final String text;
  final String id;
  const _HeadingInfo(
      {required this.level, required this.text, required this.id});
}

enum _LoadPhase { waitingForUrl, connecting, extracting, summarizing, ready }

class _ReadingCompanionPage extends StatefulWidget {
  final String url;
  final String browserTitle;
  final String mainWindowId;
  const _ReadingCompanionPage({
    required this.url,
    this.browserTitle = '',
    required this.mainWindowId,
  });

  @override
  State<_ReadingCompanionPage> createState() => _ReadingCompanionPageState();
}

class _ReadingCompanionPageState extends State<_ReadingCompanionPage> {
  final WebviewController _extractorController = WebviewController();
  final WebviewController _editorController = WebviewController();
  final TextEditingController _urlInputController = TextEditingController();
  final TextEditingController _macEditorController = TextEditingController();

  List<_HeadingInfo> _headings = [];
  String _summary = '';
  String _activeUrl = '';
  _LoadPhase _phase = _LoadPhase.connecting;
  bool _extractorReady = false;
  bool _editorReady = false;
  bool _tocExpanded = true;
  String? _errorText;

  bool get _isMacOS => Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.url;
    _initWindow();
    if (_activeUrl.isNotEmpty) {
      _startExtraction();
    } else {
      _phase = _LoadPhase.waitingForUrl;
      _tryClipboardUrl();
    }
  }

  @override
  void dispose() {
    _urlInputController.dispose();
    _extractorController.dispose();
    _editorController.dispose();
    _macEditorController.dispose();
    super.dispose();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(S.current.readingTitle);
    await windowManager.setMinimumSize(const Size(350, 400));
  }

  // ---------------------------------------------------------------------------
  // Clipboard URL auto-read
  // ---------------------------------------------------------------------------

  Future<void> _tryClipboardUrl() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.startsWith('http://') || text.startsWith('https://')) {
        _urlInputController.text = text;
      }
    } catch (_) {}
  }

  void _onUrlSubmitted() {
    final input = _urlInputController.text.trim();
    if (input.isEmpty) return;
    final url = input.startsWith('http') ? input : 'https://$input';
    setState(() {
      _activeUrl = url;
      _phase = _LoadPhase.connecting;
      _errorText = null;
    });
    _startExtraction();
  }

  // ---------------------------------------------------------------------------
  // Content extraction – platform dispatch
  // ---------------------------------------------------------------------------

  Future<void> _startExtraction() async {
    setState(() {
      _phase = _LoadPhase.connecting;
      _errorText = null;
    });

    if (_isMacOS) {
      await _startExtractionMacOS();
      return;
    }

    // Windows: use WebView2
    try {
      await _extractorController.initialize();
      await _extractorController.setBackgroundColor(Colors.white);
      await _extractorController.setPopupWindowPolicy(
          WebviewPopupWindowPolicy.deny);

      setState(() => _extractorReady = true);

      // Wait for navigation to complete via loadingState stream
      final loadComplete = Completer<void>();
      late StreamSubscription<LoadingState> sub;
      sub = _extractorController.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted &&
            !loadComplete.isCompleted) {
          loadComplete.complete();
          sub.cancel();
        }
      });

      setState(() => _phase = _LoadPhase.extracting);
      await _extractorController.loadUrl(_activeUrl);

      // Wait for page load with timeout
      await loadComplete.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (!loadComplete.isCompleted) sub.cancel();
        },
      );

      // Small grace period for JS frameworks to render
      await Future.delayed(const Duration(milliseconds: 800));
      await _extractContent();
    } catch (e) {
      debugPrint('Reading extractor init failed: $e');
      if (mounted) {
        setState(() => _errorText = e.toString());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Content extraction – macOS (HTTP fetch + HTML parsing)
  // ---------------------------------------------------------------------------

  Future<void> _startExtractionMacOS() async {
    try {
      setState(() => _phase = _LoadPhase.extracting);

      // Fetch page HTML via HttpClient
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(_activeUrl));
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36');
      final response = await request.close();
      final html = await response.transform(utf8.decoder).join();
      client.close();

      // Parse headings with regex
      final headingRegex =
          RegExp(r'<h([1-6])[^>]*>(.*?)</h\1>', dotAll: true);
      final headings = <_HeadingInfo>[];
      for (final match in headingRegex.allMatches(html)) {
        final level = int.parse(match.group(1)!);
        final text = _stripHtmlTags(match.group(2)!).trim();
        if (text.isNotEmpty) {
          headings.add(_HeadingInfo(level: level, text: text, id: ''));
        }
      }

      // Extract text from body
      String bodyHtml = html;
      final bodyMatch =
          RegExp(r'<body[^>]*>(.*)', dotAll: true).firstMatch(html);
      if (bodyMatch != null) {
        bodyHtml = bodyMatch.group(1)!;
      }
      // Remove script/style/nav/footer tags, then strip remaining tags
      final cleaned = bodyHtml
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
          .replaceAll(RegExp(r'<nav[^>]*>.*?</nav>', dotAll: true), '')
          .replaceAll(RegExp(r'<footer[^>]*>.*?</footer>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ')
          .replaceAll(RegExp(r'&#\d+;'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final text = cleaned.substring(
          0, cleaned.length > 50000 ? 50000 : cleaned.length);

      // Extract title
      final titleMatch =
          RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true).firstMatch(html);
      final title = _stripHtmlTags(titleMatch?.group(1) ?? '').trim();

      setState(() {
        _headings = headings;
        _phase = _LoadPhase.summarizing;
      });
      // Mark editor ready immediately on macOS (uses plain TextField)
      _initEditor();
      await _analyzeContent(text, title);
    } catch (e) {
      debugPrint('Reading extraction (macOS) failed: $e');
      if (mounted) setState(() => _errorText = 'Extraction error: $e');
    }
  }

  String _stripHtmlTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  // ---------------------------------------------------------------------------
  // Content extraction – Windows (WebView2 JS)
  // ---------------------------------------------------------------------------

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
        setState(() => _errorText = 'Content extraction returned empty');
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
        _phase = _LoadPhase.summarizing;
      });

      // Start editor init in parallel with analysis
      unawaited(_initEditor());
      await _analyzeContent(text, data['title'] as String? ?? '');
    } catch (e) {
      debugPrint('Content extraction failed: $e');
      if (mounted) setState(() => _errorText = 'Extraction error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Markdown editor – platform dispatch
  // ---------------------------------------------------------------------------

  Future<void> _initEditor() async {
    if (_isMacOS) {
      if (mounted) setState(() => _editorReady = true);
      return;
    }

    // Windows: WebView2-based editor
    try {
      await _editorController.initialize();
      await _editorController.setBackgroundColor(Colors.white);
      await _editorController.setPopupWindowPolicy(
          WebviewPopupWindowPolicy.deny);

      final htmlContent =
          await rootBundle.loadString('assets/reading/editor.html');

      final tempDir = await getTemporaryDirectory();
      final htmlFile = File(
          '${tempDir.path}${Platform.pathSeparator}boji_reading_editor.html');
      await htmlFile.writeAsString(htmlContent);

      final editorLoaded = Completer<void>();
      late StreamSubscription<LoadingState> sub;
      sub = _editorController.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted &&
            !editorLoaded.isCompleted) {
          editorLoaded.complete();
          sub.cancel();
        }
      });

      await _editorController.loadUrl(htmlFile.uri.toString());
      await editorLoaded.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (!editorLoaded.isCompleted) sub.cancel();
        },
      );
      // Small delay for Vditor JS initialization
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) setState(() => _editorReady = true);
    } catch (e) {
      debugPrint('Editor init failed: $e');
    }
  }

  Future<void> _setEditorContent(String markdown) async {
    if (_isMacOS) {
      _macEditorController.text = markdown;
      return;
    }
    if (!_editorReady) return;
    final escaped = markdown
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '');
    await _editorController.executeScript("setContent('$escaped')");
  }

  Future<String> _getEditorContent() async {
    if (_isMacOS) return _macEditorController.text;
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
  // LLM analysis (local template for now)
  // ---------------------------------------------------------------------------

  Future<void> _analyzeContent(String text, String title) async {
    final truncated = text.length > 15000 ? text.substring(0, 15000) : text;

    try {
      final summaryMd = StringBuffer();
      summaryMd.writeln('# ${title.isNotEmpty ? title : "阅读笔记"}');
      summaryMd.writeln();
      summaryMd.writeln('> 来源: [$_activeUrl]($_activeUrl)');
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

      // Wait for editor to be ready before setting content
      while (!_editorReady && mounted) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await _setEditorContent(_summary);

      if (mounted) {
        setState(() {
          _phase = _LoadPhase.ready;
          _errorText = null;
        });
      }
    } catch (e) {
      debugPrint('Analysis failed: $e');
      if (mounted) setState(() => _errorText = 'Analysis error: $e');
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
          'url': _activeUrl,
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
      final uri = Uri.parse('$_activeUrl#${heading.id}');
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  String get _statusLabel {
    switch (_phase) {
      case _LoadPhase.waitingForUrl:
        return '';
      case _LoadPhase.connecting:
        return S.current.readingConnecting;
      case _LoadPhase.extracting:
        return S.current.readingExtracting;
      case _LoadPhase.summarizing:
        return S.current.readingAnalyzing;
      case _LoadPhase.ready:
        return '';
    }
  }

  bool get _isLoading =>
      _phase == _LoadPhase.connecting ||
      _phase == _LoadPhase.extracting ||
      _phase == _LoadPhase.summarizing;

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
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cs.primary),
              ),
            ),
          if (_statusLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(_statusLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurface.withOpacity(0.6))),
            ),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 20),
            tooltip: S.current.readingSave,
            onPressed: _phase == _LoadPhase.ready ? _saveToMemory : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: S.current.readingClose,
            onPressed: _closeWindow,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          // Hidden extractor WebView -- must be in tree for JS execution (Windows only)
          if (!_isMacOS && _extractorReady)
            SizedBox(
              width: 0,
              height: 0,
              child: Webview(_extractorController),
            ),
          // Main content
          _buildBody(theme, cs),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs) {
    if (_phase == _LoadPhase.waitingForUrl) {
      return _buildUrlInputBody(theme, cs);
    }

    return Column(
      children: [
        if (_headings.isNotEmpty) _buildTocPanel(cs),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_errorText!,
                style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        Expanded(
          child: _editorReady
              ? _buildEditor(theme, cs)
              : _buildLoadingIndicator(theme, cs),
        ),
      ],
    );
  }

  Widget _buildEditor(ThemeData theme, ColorScheme cs) {
    if (_isMacOS) return _buildMacOSEditor(theme, cs);
    return Webview(_editorController);
  }

  Widget _buildMacOSEditor(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _macEditorController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          height: 1.5,
        ),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: S.current.readingEditorHint,
          filled: true,
          fillColor: cs.surface,
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _statusLabel.isNotEmpty
                ? _statusLabel
                : S.current.readingEditorLoading,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 8),
          _buildProgressSteps(theme, cs),
        ],
      ),
    );
  }

  Widget _buildProgressSteps(ThemeData theme, ColorScheme cs) {
    final steps = [
      (S.current.readingConnecting, _LoadPhase.connecting),
      (S.current.readingExtracting, _LoadPhase.extracting),
      (S.current.readingAnalyzing, _LoadPhase.summarizing),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: steps.map((entry) {
        final label = entry.$1;
        final step = entry.$2;
        final done = _phase.index > step.index;
        final active = _phase == step;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                done
                    ? Icons.check_circle
                    : active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                size: 14,
                color: done
                    ? Colors.green
                    : active
                        ? cs.primary
                        : cs.onSurface.withOpacity(0.3),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: done || active
                      ? cs.onSurface
                      : cs.onSurface.withOpacity(0.4),
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUrlInputBody(ThemeData theme, ColorScheme cs) {
    final titleHint = widget.browserTitle.isNotEmpty
        ? widget.browserTitle
        : S.current.readingNoBrowserUrl;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 48, color: cs.primary.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(titleHint,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(S.current.readingPasteUrlHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlInputController,
                    decoration: const InputDecoration(
                      hintText: 'https://',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _onUrlSubmitted(),
                    autofocus: true,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _onUrlSubmitted,
                  child: Text(S.current.readingStartButton),
                ),
              ],
            ),
          ],
        ),
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
                  _tocExpanded ? Icons.expand_less : Icons.expand_more,
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
