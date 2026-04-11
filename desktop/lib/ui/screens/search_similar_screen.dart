import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_strings.dart';

/// Standalone MaterialApp for the search-similar floating window.
/// Launched as a secondary Flutter engine via [WindowController.create].
class SearchSimilarApp extends StatelessWidget {
  final String imagePath;
  const SearchSimilarApp({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: S.current.searchTitle,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B35)),
      ),
      home: _SearchSimilarPage(imagePath: imagePath),
    );
  }
}

class _SearchSimilarPage extends StatefulWidget {
  final String imagePath;
  const _SearchSimilarPage({required this.imagePath});

  @override
  State<_SearchSimilarPage> createState() => _SearchSimilarPageState();
}

class _SearchSimilarPageState extends State<_SearchSimilarPage> {
  final _controller = WebviewController();
  bool _initialized = false;
  String _statusText = S.current.searchInitializing;
  bool _uploaded = false;
  String? _base64Cache;

  @override
  void initState() {
    super.initState();
    _initWindow();
    _init();
  }

  @override
  void dispose() {
    _controller.dispose();
    _cleanupTempFile();
    super.dispose();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(S.current.searchTitle);
    await windowManager.setMinimumSize(const Size(360, 400));
  }

  void _cleanupTempFile() {
    try {
      final f = File(widget.imagePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<String> _loadBase64() async {
    if (_base64Cache != null) return _base64Cache!;
    final bytes = await File(widget.imagePath).readAsBytes();
    _base64Cache = base64Encode(bytes);
    return _base64Cache!;
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();

      _controller.url.listen((url) {
        debugPrint('SearchSimilar: navigated to $url');
        if (url.contains('search') && _uploaded) {
          if (mounted) {
            setState(() => _statusText = S.current.searchResultsLoaded);
          }
        }
      });

      _controller.onLoadError.listen((error) {
        debugPrint('SearchSimilar: load error: $error');
      });

      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      if (mounted) {
        setState(() {
          _initialized = true;
          _statusText = S.current.searchOpening;
        });
      }

      await _navigateAndUpload();
    } catch (e) {
      debugPrint('SearchSimilar: init error: $e');
      if (mounted) {
        setState(() => _statusText = S.current.searchInitFailed(e.toString()));
      }
    }
  }

  Future<void> _navigateAndUpload() async {
    if (!mounted) return;
    setState(() => _statusText = S.current.searchOpening);

    final b64 = await _loadBase64();

    await _controller.loadUrl('https://s.taobao.com');
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;
    setState(() => _statusText = S.current.searchUploading);

    try {
      final result = await _controller.executeScript(_buildUploadScript(b64));
      debugPrint('SearchSimilar: upload result: $result');

      final resultStr = result?.toString() ?? '';
      if (resultStr.startsWith('"error') || resultStr.contains('no_trigger')) {
        debugPrint('SearchSimilar: auto-upload inconclusive, showing manual hint');
        if (mounted) {
          setState(() => _statusText =
              '${S.current.searchManualHint}\n${widget.imagePath}');
        }
      } else {
        _uploaded = true;
        if (mounted) {
          setState(() => _statusText = S.current.searchUploaded);
        }
      }
    } catch (e) {
      debugPrint('SearchSimilar: upload script error: $e');
      if (mounted) {
        setState(() => _statusText =
            '${S.current.searchManualHint}\n${widget.imagePath}');
      }
    }
  }

  String _buildUploadScript(String base64) {
    return '''
(async function() {
  try {
    var resp = await fetch('data:image/png;base64,$base64');
    var blob = await resp.blob();
    var file = new File([blob], 'boji_search.png', {type: 'image/png'});

    // Strategy 1: find any visible file input
    var inputs = document.querySelectorAll('input[type="file"]');
    for (var inp of inputs) {
      var dt = new DataTransfer();
      dt.items.add(file);
      inp.files = dt.files;
      inp.dispatchEvent(new Event('change', {bubbles: true}));
      return 'uploaded_via_input';
    }

    // Strategy 2: find and click the camera/image-search trigger
    var triggers = [
      ...document.querySelectorAll('[class*="camera"]'),
      ...document.querySelectorAll('[class*="img-search"]'),
      ...document.querySelectorAll('[class*="imgSearch"]'),
      ...document.querySelectorAll('[class*="search-img"]'),
      ...document.querySelectorAll('[class*="searchImg"]'),
      ...document.querySelectorAll('[data-action*="image"]'),
      ...document.querySelectorAll('[aria-label*="图片"]'),
      ...document.querySelectorAll('[aria-label*="image"]'),
      ...document.querySelectorAll('[aria-label*="拍照"]'),
      ...document.querySelectorAll('.search-combobox-input-arrow'),
    ];
    // Filter to visible elements
    triggers = triggers.filter(el => {
      var r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    });

    if (triggers.length > 0) {
      triggers[0].click();
      // Wait for modal/panel to appear, observe DOM for file input
      var found = await new Promise(resolve => {
        var observer = new MutationObserver(function(mutations) {
          var newInputs = document.querySelectorAll('input[type="file"]');
          if (newInputs.length > 0) {
            observer.disconnect();
            resolve(newInputs[0]);
          }
        });
        observer.observe(document.body, {childList: true, subtree: true});
        setTimeout(() => { observer.disconnect(); resolve(null); }, 3000);
      });

      if (found) {
        var dt2 = new DataTransfer();
        dt2.items.add(file);
        found.files = dt2.files;
        found.dispatchEvent(new Event('change', {bubbles: true}));
        return 'uploaded_via_modal';
      }
    }

    return 'no_trigger_found';
  } catch(e) {
    return 'error: ' + e.message;
  }
})();
''';
  }

  Future<void> _closeWindow() async {
    try {
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSpinner = !_statusText.contains(S.current.searchResultsLoaded) &&
        !_statusText.toLowerCase().contains('failed') &&
        !_statusText.contains('失败') &&
        !_statusText.contains(S.current.searchManualHint);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: _closeWindow,
          tooltip: S.current.cancel,
        ),
        title: Row(
          children: [
            Icon(Icons.search, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(S.current.searchTitle,
                style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          if (_statusText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSpinner)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        _statusText.split('\n').first,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: S.current.searchRetry,
            onPressed: _initialized ? _navigateAndUpload : null,
          ),
        ],
      ),
      body: _initialized
          ? Webview(
              _controller,
              permissionRequested: (url, kind, isUserInitiated) =>
                  WebviewPermissionDecision.allow,
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusText, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
    );
  }
}
