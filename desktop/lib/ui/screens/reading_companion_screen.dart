import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_strings.dart';

class ReadingCompanionApp extends StatelessWidget {
  final String url;
  final String browserTitle;
  final String mainWindowId;
  final String? cdpText;
  final String? cdpTitle;
  final String? cdpUrl;
  final List<dynamic>? cdpHeadings;
  final double windowWidth;
  final double windowHeight;
  const ReadingCompanionApp({
    super.key,
    required this.url,
    this.browserTitle = '',
    required this.mainWindowId,
    this.cdpText,
    this.cdpTitle,
    this.cdpUrl,
    this.cdpHeadings,
    this.windowWidth = 500,
    this.windowHeight = 800,
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
        url: url,
        browserTitle: browserTitle,
        mainWindowId: mainWindowId,
        cdpText: cdpText,
        cdpTitle: cdpTitle,
        cdpUrl: cdpUrl,
        cdpHeadings: cdpHeadings,
        windowWidth: windowWidth,
        windowHeight: windowHeight,
      ),
    );
  }
}

class _HeadingInfo {
  final int level;
  final String text;
  const _HeadingInfo({required this.level, required this.text});
}

enum _LoadPhase { waitingForUrl, connecting, extracting, summarizing, ready }

class _ReadingCompanionPage extends StatefulWidget {
  final String url;
  final String browserTitle;
  final String mainWindowId;
  final String? cdpText;
  final String? cdpTitle;
  final String? cdpUrl;
  final List<dynamic>? cdpHeadings;
  final double windowWidth;
  final double windowHeight;
  const _ReadingCompanionPage({
    required this.url,
    this.browserTitle = '',
    required this.mainWindowId,
    this.cdpText,
    this.cdpTitle,
    this.cdpUrl,
    this.cdpHeadings,
    this.windowWidth = 500,
    this.windowHeight = 800,
  });

  @override
  State<_ReadingCompanionPage> createState() => _ReadingCompanionPageState();
}

class _ReadingCompanionPageState extends State<_ReadingCompanionPage> {
  final TextEditingController _urlInputController = TextEditingController();
  final TextEditingController _editorController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<_HeadingInfo> _headings = [];
  String _summary = '';
  String _activeUrl = '';
  _LoadPhase _phase = _LoadPhase.connecting;
  bool _tocExpanded = true;
  String? _errorText;
  bool _windowReady = false;

  bool get _hasCdpContent =>
      widget.cdpText != null && widget.cdpText!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _activeUrl =
        widget.cdpUrl?.isNotEmpty == true ? widget.cdpUrl! : widget.url;

    _initWindow().then((_) {
      if (!mounted) return;
      setState(() => _windowReady = true);
      windowManager.show();

      if (_hasCdpContent) {
        _useCdpContent();
      } else if (_activeUrl.isNotEmpty) {
        _startExtraction();
      } else {
        setState(() => _phase = _LoadPhase.waitingForUrl);
        _tryClipboardUrl();
      }
    });
  }

  @override
  void dispose() {
    _urlInputController.dispose();
    _editorController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(S.current.readingTitle);
    await windowManager.setMinimumSize(const Size(280, 400));
    await windowManager
        .setSize(Size(widget.windowWidth, widget.windowHeight));
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

  void _useCdpContent() {
    final rawHeadings = widget.cdpHeadings ?? [];
    _headings = rawHeadings.map((h) {
      final m = h as Map<String, dynamic>;
      return _HeadingInfo(
        level: (m['level'] as num?)?.toInt() ?? 2,
        text: m['text'] as String? ?? '',
      );
    }).toList();

    setState(() => _phase = _LoadPhase.summarizing);
    _analyzeContent(widget.cdpText!, widget.cdpTitle ?? widget.browserTitle);
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
  // Content extraction via HTTP (cross-platform)
  // ---------------------------------------------------------------------------

  Future<void> _startExtraction() async {
    setState(() {
      _phase = _LoadPhase.connecting;
      _errorText = null;
    });

    try {
      final client = HttpClient();
      final ua = Platform.isMacOS
          ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
          : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.0.0 Safari/537.36';
      client.userAgent = ua;
      client.connectionTimeout = const Duration(seconds: 10);

      final req = await client.getUrl(Uri.parse(_activeUrl));
      final resp = await req.close();
      final html = await resp.transform(utf8.decoder).join();
      client.close();

      if (!mounted) return;
      setState(() => _phase = _LoadPhase.extracting);
      _parseHtmlContent(html);
    } catch (e) {
      debugPrint('Reading HTTP extraction failed: $e');
      if (mounted) {
        setState(() => _errorText = e.toString());
      }
    }
  }

  void _parseHtmlContent(String html) {
    // Extract title
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true)
            .firstMatch(html);
    final title = titleMatch != null
        ? _decodeHtmlEntities(titleMatch.group(1)?.trim() ?? '')
        : '';

    // Strip scripts, styles, and non-content sections
    var text = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<nav[^>]*>.*?</nav>', dotAll: true), '')
        .replaceAll(RegExp(r'<footer[^>]*>.*?</footer>', dotAll: true), '')
        .replaceAll(RegExp(r'<header[^>]*>.*?</header>', dotAll: true), '');

    // Extract headings
    final headingRegex =
        RegExp(r'<h([1-6])[^>]*>(.*?)</h[1-6]>', dotAll: true);
    final headings = <_HeadingInfo>[];
    for (final m in headingRegex.allMatches(text)) {
      final level = int.parse(m.group(1)!);
      final hText = _stripTags(m.group(2) ?? '').trim();
      if (hText.isNotEmpty) {
        headings.add(_HeadingInfo(level: level, text: hText));
      }
    }

    // Try to find main content area
    var mainContent = '';
    final articleMatch =
        RegExp(r'<article[^>]*>(.*?)</article>', dotAll: true).firstMatch(text);
    if (articleMatch != null) {
      mainContent = articleMatch.group(1)!;
    } else {
      final mainMatch =
          RegExp(r'<main[^>]*>(.*?)</main>', dotAll: true).firstMatch(text);
      if (mainMatch != null) {
        mainContent = mainMatch.group(1)!;
      } else {
        final bodyMatch =
            RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true).firstMatch(text);
        mainContent = bodyMatch?.group(1) ?? text;
      }
    }

    // Insert paragraph breaks before block-level tags before stripping
    final blockTags = RegExp(
      r'</(p|div|li|tr|br|blockquote|h[1-6]|section|article|main|dd|dt|figcaption)>',
      caseSensitive: false,
    );
    mainContent = mainContent
        .replaceAll(blockTags, '\n\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n\n');

    final plainText = _stripTags(mainContent)
        .replaceAll(RegExp(r'[ \t]+'), ' ') // collapse horizontal ws only
        .replaceAll(RegExp(r'\n{3,}'), '\n\n') // max 2 consecutive newlines
        .trim();
    final truncated =
        plainText.length > 50000 ? plainText.substring(0, 50000) : plainText;

    if (!mounted) return;
    setState(() {
      _headings = headings;
      _phase = _LoadPhase.summarizing;
    });
    _analyzeContent(truncated, title);
  }

  String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'&#\d+;'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _decodeHtmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  // ---------------------------------------------------------------------------
  // Content analysis and template
  // ---------------------------------------------------------------------------

  void _analyzeContent(String text, String title) {
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

      // Split into paragraphs: double-newline (HTML block boundaries)
      // or single-newline (innerText from CDP). Normalize to double-newline
      // so both sources are handled uniformly.
      final normalized = truncated.replaceAll(RegExp(r'\n{1,}'), '\n\n');
      final paragraphs = normalized
          .split(RegExp(r'\n{2,}'))
          .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((p) => p.length > 15)
          .toList();

      if (paragraphs.isNotEmpty) {
        summaryMd.writeln('## 内容摘要');
        summaryMd.writeln();

        if (_headings.isNotEmpty) {
          var paraIdx = 0;
          for (final h in _headings.take(6)) {
            if (paraIdx >= paragraphs.length) break;
            if (h.text.trim() == title.trim()) continue;

            summaryMd.writeln('### ${h.text}');
            summaryMd.writeln();

            final sectionParas = <String>[];
            for (var j = 0; j < 2 && paraIdx < paragraphs.length; j++) {
              sectionParas.add(paragraphs[paraIdx++]);
            }
            for (final sp in sectionParas) {
              if (sp.length > 200) {
                summaryMd.writeln('> ${sp.substring(0, 200)}...');
              } else {
                summaryMd.writeln('> $sp');
              }
              summaryMd.writeln();
            }
          }
          while (paraIdx < paragraphs.length && paraIdx < 10) {
            final p = paragraphs[paraIdx++];
            if (p.length > 200) {
              summaryMd.writeln('> ${p.substring(0, 200)}...');
            } else {
              summaryMd.writeln('> $p');
            }
            summaryMd.writeln();
          }
        } else {
          for (final p in paragraphs.take(8)) {
            if (p.length > 200) {
              summaryMd.writeln('> ${p.substring(0, 200)}...');
            } else {
              summaryMd.writeln('> $p');
            }
            summaryMd.writeln();
          }
        }
      }

      summaryMd.writeln('## 全文');
      summaryMd.writeln();
      for (final p in paragraphs) {
        summaryMd.writeln(p);
        summaryMd.writeln();
      }

      summaryMd.writeln('## 我的笔记');
      summaryMd.writeln();

      _summary = summaryMd.toString();
      _editorController.text = _summary;

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
    final content = _editorController.text.isNotEmpty
        ? _editorController.text
        : _summary;
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
    if (!_windowReady) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: SizedBox.expand()),
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Column(
        children: [
          // Toolbar (window has native title bar)
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  tooltip: S.current.readingSave,
                  onPressed: _phase == _LoadPhase.ready ? _saveToMemory : null,
                  visualDensity: VisualDensity.compact,
                ),
                if (_isLoading) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.primary),
                  ),
                ],
                if (_statusLabel.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(_statusLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6))),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody(theme, cs)),
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
            padding: const EdgeInsets.all(12),
            child: Text(_errorText!,
                style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        Expanded(
          child: _phase == _LoadPhase.ready
              ? _buildEditor(cs)
              : _buildLoadingIndicator(theme, cs),
        ),
      ],
    );
  }

  Widget _buildEditor(ColorScheme cs) {
    return TextField(
      controller: _editorController,
      scrollController: _scrollController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        filled: true,
        fillColor: cs.surface,
        border: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurface),
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
                ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
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
                        : cs.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: done || active
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: 0.4),
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
                size: 48, color: cs.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(titleHint,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(S.current.readingPasteUrlHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
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
                return Padding(
                  padding: EdgeInsets.only(
                      left: indent, right: 12, top: 3, bottom: 3),
                  child: Text(
                    h.text,
                    style: TextStyle(
                      fontSize: h.level <= 2 ? 13 : 12,
                      fontWeight:
                          h.level <= 2 ? FontWeight.w500 : FontWeight.normal,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
