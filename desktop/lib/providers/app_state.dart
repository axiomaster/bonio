import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_strings.dart';
import '../models/agent_avatar_models.dart';
import '../platform/gui_agent.dart';
import '../platform/macos_screen_capture.dart';
import '../platform/screen_capture.dart';
import '../services/app_logger.dart';
import '../platform/screen_capture_types.dart';
import '../platform/win32_screen_capture.dart';
import '../plugins/plugin_interface.dart';
import '../models/chat_models.dart';
import '../models/gateway_profile.dart';
import '../models/note_models.dart';
import '../services/node_runtime.dart';
import '../services/device_identity_store.dart';
import '../services/device_auth_store.dart';
import '../services/camera_service.dart';
import '../services/speech_to_text_manager.dart';
import '../services/hiclaw_process.dart';
import '../services/reading_template_store.dart';
import '../ui/widgets/ocr_result_dialog.dart';

class AppState extends ChangeNotifier {
  /// Navigator key for showing dialogs from non-widget code (e.g. OCR results).
  static final navigatorKey = GlobalKey<NavigatorState>();

  late final NodeRuntime runtime;
  final DeviceIdentityStore _identityStore = DeviceIdentityStore();
  final DeviceAuthStore _deviceAuthStore = DeviceAuthStore();
  final CameraService cameraService = CameraService();

  String _host = '';
  int _port = 10724;
  String _token = '';
  bool _tls = false;
  GatewayProfile _gatewayProfile = GatewayProfile.hiclaw;
  bool _showAvatarOverlay = true;
  bool _speakAssistantReplies = true;
  AppLocale _locale = AppLocale.zh;

  /// When non-null, the main screen should navigate to the search-similar
  /// screen with this base64 PNG. Consumed (set to null) after navigation.
  

  final SpeechToTextManager _sttManager = SpeechToTextManager();
  final HiclawProcess hiclawProcess = HiclawProcess();

  String get host => _host;
  int get port => _port;
  String get token => _token;
  bool get tls => _tls;
  GatewayProfile get gatewayProfile => _gatewayProfile;
  bool get showAvatarOverlay => _showAvatarOverlay;
  bool get speakAssistantReplies => _speakAssistantReplies;
  AppLocale get locale => _locale;
  S get strings => S.current;

  AppState() {
    _initCamera();
    runtime = NodeRuntime(
      identityStore: _identityStore,
      deviceAuthStore: _deviceAuthStore,
      cameraService: cameraService,
    );
    runtime.addListener(_onRuntimeChanged);
    cameraService.addListener(_onCameraChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_registerMainWindowHandler());
    });
    _loadPrefs();
    unawaited(_sttManager.warmUp());
  }

  Future<void> _initCamera() async {
    await cameraService.initialize();
  }

  void _onRuntimeChanged() => notifyListeners();

  void _onCameraChanged() => notifyListeners();

  /// Long-press start → begin STT listening.
  void _handleAvatarVoiceStart() {
    if (_sttManager.isListening) return;
    _sttManager.startListening(SpeechToTextCallbacks(
      ready: () {
        runtime.avatarController.setActivity(AgentAvatarActivity.listening);
        runtime.avatarController.setBubble(text: '...');
      },
      partial: (text) {
        runtime.avatarController.setBubble(text: text);
      },
      final_: (text) {
        runtime.avatarController.clearBubble();
        runtime.avatarController.setActivity(AgentAvatarActivity.idle);
        if (text.trim().isNotEmpty) {
          runtime.chatController.sendMessage(text.trim());
        }
      },
      error: (code) {
        log.error('STT error: $code');
        runtime.avatarController.clearBubble();
        runtime.avatarController.setActivity(AgentAvatarActivity.idle);
      },
      end: () {
        runtime.avatarController.clearBubble();
        runtime.avatarController.setActivity(AgentAvatarActivity.idle);
      },
    ));
  }

  /// Long-press end → stop STT, finalize and send accumulated text.
  void _handleAvatarVoiceStop() {
    if (!_sttManager.isListening) return;
    _sttManager.stopListening();
  }

  void _handleAvatarClick() {
    runtime.avatarController.triggerClickReaction();
    // Trigger context recognition asynchronously (do not block animation)
    unawaited(runtime.recognizeContext());
  }

  void _handleAvatarDoubleClick() {
    runtime.avatarController.toggleInput();
  }

  Future<void> _handleAvatarMenuAction(String action) async {
    switch (action) {
      case 'show_main':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'switch_window':
        break;
    }
  }

  Future<void> _handlePluginMenuAction(Map<String, dynamic> data) async {
    final pluginId = data['pluginId'] as String? ?? '';
    if (pluginId.isEmpty) return;
    final hwnd = (data['hwnd'] as num?)?.toInt() ?? 0;
    final isBrowser = data['isBrowser'] as bool? ?? false;
    final context = PluginMenuContext(
      hwnd: hwnd,
      windowTitle: hwnd != 0
          ? runtime.guiAgent.window.getWindowTitle(hwnd)
          : '',
      windowClass: hwnd != 0
          ? runtime.guiAgent.window.getWindowClassName(hwnd)
          : '',
      isBrowser: isBrowser,
      screenDpi: hwnd != 0 ? runtime.guiAgent.screen.getDpiScale(hwnd) : 1.0,
    );
    await runtime.pluginManager.executeMenuAction(pluginId, context);
  }

  Future<void> _handleSearchSimilar(Map<String, dynamic> data) async {
    final pngBase64 = data['pngBase64'] as String? ?? '';
    if (pngBase64.isEmpty) {
      log.warn('AppState: search_similar has no image data');
      return;
    }
    final avatarX = (data['avatarX'] as num?)?.toDouble() ?? 200;
    final avatarY = (data['avatarY'] as num?)?.toDouble() ?? 200;

    log.info('AppState: search_similar received, '
        'base64Len=${pngBase64.length}, avatar=($avatarX,$avatarY)');

    final ctrl = runtime.avatarController;
    ctrl.setBubble(text: S.current.bubbleSearching);
    ctrl.showTemporaryState(AgentAvatarActivity.thinking);

    try {
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}${Platform.pathSeparator}'
          'bonio_search_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(base64Decode(pngBase64));
      log.info('AppState: search image saved to $path');
      await runtime.createSearchWindow(path, avatarX, avatarY);
    } catch (e) {
      log.error('AppState: search_similar error: $e');
    }
  }

  Future<void> _handleOcrText(Map<String, dynamic> data) async {
    final pngBase64 = data['pngBase64'] as String? ?? '';
    if (pngBase64.isEmpty) {
      log.warn('AppState: ocr_text has no image data');
      return;
    }
    log.info('AppState: ocr_text received, base64Len=${pngBase64.length}');

    final ctrl = runtime.avatarController;
    ctrl.setBubble(text: S.current.ocrProcessing);

    String? text;
    try {
      final ready = await runtime.ensurePaddleOcrReady();
      if (!ready) {
        log.warn('AppState: PaddleOCR unavailable, OCR stays client-side');
      } else {
        // Decode PNG to BGRA pixels for PaddleOCR
        final pngBytes = base64Decode(pngBase64);
        final bgra = await _pngToBgra(pngBytes);
        if (bgra != null) {
          log.info('AppState: local OCR image ${bgra.width}x${bgra.height}');
          text = runtime.paddleOcr.recognize(bgra.pixels, bgra.width, bgra.height);
          log.info('AppState: local OCR result length=${text?.length ?? 0}');
        }
      }
    } catch (e) {
      log.warn('AppState: local OCR failed: $e');
    }

    ctrl.clearBubble();
    await runtime.createOcrResultWindow(
      (text != null && text.trim().isNotEmpty) ? text : S.current.ocrNoText,
      imageBase64: pngBase64,
    );
  }

  /// Convert PNG bytes to BGRA pixel data for PaddleOCR.
  Future<_BgraImage?> _pngToBgra(Uint8List pngBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (byteData == null) return null;
      final rgba = byteData.buffer.asUint8List();
      // Convert RGBA to BGRA
      final bgra = Uint8List(rgba.length);
      for (var i = 0; i < rgba.length; i += 4) {
        bgra[i] = rgba[i + 2];     // B
        bgra[i + 1] = rgba[i + 1]; // G
        bgra[i + 2] = rgba[i];     // R
        bgra[i + 3] = rgba[i + 3]; // A
      }
      return _BgraImage(bgra, image.width, image.height);
    } catch (e) {
      log.warn('_pngToBgra failed: $e');
      return null;
    }
  }

  /// Fallback: use AI backend for OCR.
  Future<String> _ocrViaAi(String pngBase64) async {
    const sessionKey = 'bonio-ocr';
    final completer = Completer<String>();
    final accumulated = StringBuffer();
    final runId = const Uuid().v4();

    runtime.tempEventListener = (String event, String? payloadJson) {
      if (payloadJson == null) return;
      try {
        final obj = jsonDecode(payloadJson) as Map<String, dynamic>?;
        if (obj == null) return;
        if (obj['runId'] != runId) return;
        if (event == 'agent' && obj['stream'] == 'assistant') {
          accumulated.write(obj['text'] as String? ?? '');
        } else if (event == 'chat' && obj['state'] == 'final') {
          if (!completer.isCompleted) {
            runtime.tempEventListener = null;
            completer.complete(accumulated.toString());
          }
        }
      } catch (_) {}
    };

    try {
      await runtime.operatorSession.request('chat.send', jsonEncode({
        'sessionKey': sessionKey,
        'message': 'Extract all text from this image via OCR. '
            'Return ONLY the plain text, no explanations.',
        'idempotencyKey': runId,
        'attachments': [{
          'type': 'image', 'mimeType': 'image/png',
          'fileName': 'ocr.png', 'content': pngBase64,
        }],
      }), timeoutMs: 60000);
      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => accumulated.toString(),
      );
      // Delete the temporary session so it doesn't appear in chat UI
      try {
        await runtime.operatorSession.request('sessions.delete',
            jsonEncode({'sessionKey': sessionKey}), timeoutMs: 5000);
      } catch (_) {}
      return result;
    } catch (_) {
      return '';
    } finally {
      runtime.tempEventListener = null;
    }
  }

  Future<void> _handleReadingSave(Map<String, dynamic> data) async {
    final url = data['url'] as String? ?? '';
    final markdown = data['markdown'] as String? ?? '';
    if (markdown.isEmpty) return;
    final title = data['title'] as String? ?? '';
    final categories = (data['categories'] as List?)?.cast<String>() ?? [];
    try {
      await runtime.noteService.saveReadingNote(
        url, markdown,
        title: title,
        categories: categories,
      );
      log.info('AppState: reading note saved');
    } catch (e) {
      log.error('AppState: reading save error: $e');
    }
  }

  Future<void> _handleReadingSummarize(Map<String, dynamic> data) async {
    final text = data['text'] as String? ?? '';
    final url = data['url'] as String? ?? '';
    final title = data['title'] as String? ?? '';
    final windowId = data['windowId']?.toString() ?? '';
    final categoryKey = data['category'] as String? ?? 'auto';
    final browserHwnd = data['browserHwnd'] as int? ?? 0;
    if (text.isEmpty || windowId.isEmpty) return;

    final category = ReadingCategory.fromKey(categoryKey);
    log.info('AppState: _handleReadingSummarize, '
        'text.length=${text.length}, category=$category, windowId=$windowId');

    try {
      var resultJson =
          await runtime.noteService.summarizeReading(text, url, title, category: category);

      log.info('AppState: summarizeReading returned, resultJson.length=${resultJson.length}');

      // Extract JSON block in case LLM wraps it in markdown (e.g., ```json ... ```)
      final start = resultJson.indexOf('{');
      final end = resultJson.lastIndexOf('}');
      if (start >= 0 && end > start) {
        resultJson = resultJson.substring(start, end + 1);
      }
      final json = jsonDecode(resultJson) as Map<String, dynamic>;
      final summary = ReadingSummary.fromJson(json);

      final markdown = await _renderSummaryMarkdown(summary, url, text, category: category);
      final wc = WindowController.fromWindowId(windowId);
      await wc.invokeMethod('readingSummaryResult', jsonEncode({
        'markdown': markdown,
        'title': summary.title,
        'author': summary.author,
        'categories': summary.categories,
      }));

      // Capture browser window as cover thumbnail
      Uint8List? coverPng;
      if (browserHwnd != 0) {
        coverPng = await runtime.noteService.captureWindowThumbnail(browserHwnd);
      }

      // Auto-save the AI-generated summary to memory.
      try {
        await runtime.noteService.saveReadingNote(
          url, markdown,
          title: summary.title,
          summaryText: summary.summary,
          categories: summary.categories,
          coverPng: coverPng,
        );
        log.info('AppState: reading note auto-saved');
      } catch (e) {
      log.error('AppState: reading auto-save error: $e');
      }
    } catch (e) {
      log.error('AppState: reading summarize error: $e');
      try {
        final wc = WindowController.fromWindowId(windowId);
        await wc.invokeMethod('readingSummaryResult', '');
      } catch (_) {}
    }
  }

  Future<String> _renderSummaryMarkdown(
      ReadingSummary summary, String url, String fullText,
      {ReadingCategory category = ReadingCategory.scienceTech}) async {
    final tmpl = ReadingTemplateStore.getOutputTemplate(category);

    final authorLine = summary.author.isNotEmpty
        ? '作者：${summary.author}'
        : '';

    final paragraphMd = summary.paragraphSummaries
        .map((p) => '- **${p.subtitle}**：${p.content}')
        .join('\n');

    return tmpl
        .replaceAll('{{title}}', summary.title)
        .replaceAll('{{url}}', url)
        .replaceAll('{{author_line}}', authorLine)
        .replaceAll('{{summary}}', summary.summary)
        .replaceAll('{{paragraph_summaries}}', paragraphMd);
  }

  Future<void> _handleStartReading(Map<String, dynamic> data) async {
    final hwnd = (data['hwnd'] as num?)?.toInt() ?? 0;
    var url = data['url'] as String? ?? '';
    final title = data['title'] as String? ?? '';
    debugPrint('AppState: _handleStartReading hwnd=$hwnd url=$url title=$title');

    final ctrl = runtime.avatarController;
    ctrl.setBubble(text: S.current.readingConnecting);
    ctrl.showTemporaryState(AgentAvatarActivity.thinking);

    // Try to get the real URL and page content via CDP
    PageContent? cdpContent;
    try {
      final agent = runtime.guiAgent.browser;
      final connected = await agent.tryConnectToExisting(urlHint: url);
      if (connected) {
        ctrl.setBubble(text: S.current.readingExtracting);

        cdpContent = await agent.extractPageContent();
        if (cdpContent.url.isNotEmpty) url = cdpContent.url;
        log.info('AppState: CDP extracted ${cdpContent.headings.length} '
            'headings, ${cdpContent.text.length} chars from $url');
      } else {
        log.warn('AppState: CDP not connected');
      }
    } catch (e) {
      log.error('AppState: CDP extraction failed: $e');
    }

    // If CDP failed, try UI Automation extraction (non-intrusive, Windows only)
    if (cdpContent == null && hwnd != 0 && Platform.isWindows) {
      try {
        ctrl.setBubble(text: S.current.readingExtracting);
        final pageText =
            await Win32ScreenCapture.getBrowserPageTextViaUIA(hwnd);
        if (pageText != null && pageText.length > 50) {
          log.info('AppState: UIA extracted ${pageText.length} chars');
          cdpContent = PageContent(
            title: title,
            url: url,
            text: pageText,
            headings: [],
          );
        } else {
          log.warn('AppState: UIA text too short or empty '
              '(${pageText?.length ?? 0} chars)');
        }
      } catch (e) {
        log.error('AppState: UIA extraction failed: $e');
      }
    }

    // If CDP and UIA failed, try clipboard-based extraction (Ctrl+A, Ctrl+C on browser)
    if (cdpContent == null && hwnd != 0 && Platform.isWindows) {
      try {
        ctrl.setBubble(text: S.current.readingExtracting);
        final pageText =
            await Win32ScreenCapture.getBrowserPageText(hwnd);
        if (pageText != null && pageText.length > 50) {
          log.info('AppState: clipboard extracted ${pageText.length} chars');
          cdpContent = PageContent(
            title: title,
            url: url,
            text: pageText,
            headings: [],
          );
        } else {
          log.warn('AppState: clipboard text too short or empty '
              '(${pageText?.length ?? 0} chars)');
        }
      } catch (e) {
        log.error('AppState: clipboard extraction failed: $e');
      }
    }

    // macOS: extract page text via AppleScript JavaScript execution
    if (cdpContent == null && hwnd != 0 && Platform.isMacOS) {
      try {
        ctrl.setBubble(text: S.current.readingExtracting);
        final pageText = MacosScreenCapture.getBrowserPageText(hwnd);
        if (pageText != null && pageText.length > 50) {
          debugPrint('AppState: macOS AppleScript extracted ${pageText.length} chars');
          cdpContent = PageContent(
            title: title,
            url: url,
            text: pageText,
            headings: [],
          );
        } else {
          debugPrint('AppState: macOS AppleScript text too short or empty '
              '(${pageText?.length ?? 0} chars)');
        }
      } catch (e) {
        debugPrint('AppState: macOS AppleScript extraction failed: $e');
      }
    }

    final ga = runtime.guiAgent;
    if (hwnd != 0) {
      final browserRect = ga.window.getWindowRect(hwnd);
      debugPrint('AppState: browserRect=$browserRect, dpi=${ga.screen.getDpiScale(hwnd)}, '
          'url=$url, cdpContent=${cdpContent != null ? "${cdpContent.text.length}chars" : "null"}');
      if (browserRect != Rect.zero) {
        final dpi = ga.screen.getDpiScale(hwnd);
        await runtime.createReadingWindow(
          url, title,
          browserRect.right,
          browserRect.top,
          500.0 / dpi,
          browserRect.height / dpi,
          cdpContent: cdpContent,
          browserHwnd: hwnd,
        );
      } else {
        await runtime.createReadingWindow(url, title, 0, 0, 500, 800,
            cdpContent: cdpContent, browserHwnd: hwnd);
      }
    } else {
      await runtime.createReadingWindow(url, title, 0, 0, 500, 800,
          cdpContent: cdpContent);
    }
  }

  Future<void> _handleNoteCaptureWithData(Map<String, dynamic> data) async {
    final hwnd = (data['hwnd'] as num?)?.toInt() ?? 0;
    if (hwnd == 0) return;

    final ctrl = runtime.avatarController;
    ctrl.showTemporaryState(AgentAvatarActivity.happy);
    ctrl.setBubble(text: S.current.bubbleCapturing);

    final note = await runtime.noteService.captureWindow(hwnd);
    if (note != null) {
      ctrl.setBubble(text: S.current.bubbleCaptured);
      unawaited(runtime.noteService.analyzeNote(note).then((_) {
        final updated =
            runtime.noteService.notes.where((n) => n.id == note.id).firstOrNull;
        if (updated != null && updated.tags.isNotEmpty) {
          ctrl.setBubble(text: S.current.bubbleSaved(updated.tags.join(' ')));
        }
      }));
    } else {
      ctrl.setBubble(text: S.current.bubbleCaptureFailed);
    }
  }

  void _handleAvatarTextSubmit(String text) {
    if (text.trim().isEmpty) return;
    runtime.avatarController.hideInput();
    runtime.chatController.sendMessage(text.trim());
  }

  void _handleAvatarTextSubmitWithAttachments(Map<String, dynamic> data) {
    final text = (data['text'] as String? ?? '').trim();
    final rawAtts = data['attachments'] as List? ?? [];
    final attachments = rawAtts
        .map((a) {
          final m = Map<String, dynamic>.from(a as Map);
          return OutgoingAttachment(
            type: m['type'] as String? ?? 'image',
            mimeType: m['mimeType'] as String? ?? 'application/octet-stream',
            fileName: m['fileName'] as String? ?? 'file',
            base64: m['base64'] as String? ?? '',
          );
        })
        .where((a) => a.base64.isNotEmpty)
        .toList();
    if (text.isEmpty && attachments.isEmpty) return;
    runtime.avatarController.hideInput();
    runtime.chatController.sendMessage(
      text.isNotEmpty ? text : S.current.bubbleImageAttachment,
      attachments: attachments,
    );
  }

  void _handleAvatarLensResult(Map<String, dynamic> data) {
    log.info('AppState: received avatarLensResult, keys=${data.keys.toList()}');
    final windowTitle = data['windowTitle'] as String? ?? '';
    final rects = (data['rects'] as List?)
            ?.map((r) => Map<String, dynamic>.from(r as Map))
            .toList() ??
        [];
    final pngBase64 = data['pngBase64'] as String? ?? '';

    log.info('AppState: lens title="$windowTitle", rects=${rects.length}, '
        'base64Len=${pngBase64.length}');

    if (pngBase64.isEmpty) {
      log.warn('AppState: lens result has no screenshot');
      return;
    }

    // Build structured prompt
    final buf = StringBuffer();
    buf.writeln('[Bonio Lens] 用户在应用窗口 "$windowTitle" 上进行了圈选标注。');
    buf.writeln();
    if (rects.isNotEmpty) {
      buf.writeln('标注区域（像素坐标，相对于窗口左上角）：');
      for (var i = 0; i < rects.length; i++) {
        final r = rects[i];
        buf.writeln('${i + 1}. (x=${r['x']}, y=${r['y']}, w=${r['w']}, h=${r['h']})');
      }
      buf.writeln();
      buf.writeln('以上标注框是用户手动标注的重点关注区域，请特别关注这些区域的内容，分析并回答用户可能的疑问。');
    } else {
      buf.writeln('用户未标注任何区域，请分析整个窗口截图的内容。');
    }

    log.info('AppState: sending lens result via chat.send...');
    runtime.chatController.sendMessage(
      buf.toString(),
      attachments: [
        OutgoingAttachment(
          type: 'image',
          mimeType: 'image/png',
          fileName: 'bonio_lens_capture.png',
          base64: pngBase64,
        ),
      ],
    );
    log.info('AppState: lens chat.send dispatched');
  }

  Future<void> _handleAvatarDrop(Map<String, dynamic> data) async {
    final dropType = data['type'] as String? ?? '';
    if (dropType.isEmpty) return;

    final ctrl = runtime.avatarController;
    ctrl.setBubble(text: S.current.bubbleReceived);

    try {
      BonioNote? note;
      if (dropType == 'file') {
        final paths = (data['paths'] as List?)?.cast<String>() ?? [];
        for (final path in paths) {
          note = await runtime.noteService.saveDroppedContent(
            dropType: 'file',
            filePath: path,
          );
        }
      } else if (dropType == 'text') {
        note = await runtime.noteService.saveDroppedContent(
          dropType: 'text',
          text: data['text'] as String? ?? '',
        );
      } else if (dropType == 'image') {
        final b64 = data['base64'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          final bytes = Uint8List.fromList(base64Decode(b64));
          note = await runtime.noteService.saveDroppedContent(
            dropType: 'image',
            imageBytes: bytes,
          );
        }
      }

      if (note != null) {
        ctrl.setBubble(text: S.current.bubbleAnalyzing);
        unawaited(runtime.noteService.analyzeNote(note).then((_) {
          final updated = runtime.noteService.notes
              .where((n) => n.id == note!.id)
              .firstOrNull;
          if (updated != null && updated.tags.isNotEmpty) {
            ctrl.setBubble(text: S.current.bubbleDigested(updated.tags.join(' ')));
          }
        }));
      } else {
        ctrl.setBubble(text: S.current.bubbleCantEat);
      }
    } catch (e) {
      log.error('AppState: drop handling error: $e');
      ctrl.setBubble(text: S.current.bubbleCantDigest);
    }
  }

  Future<void> _registerMainWindowHandler() async {
    try {
      final wc = await WindowController.fromCurrentEngine();
      await wc.setWindowMethodHandler((call) async {
        switch (call.method) {
          case 'avatarVoiceStart':
            _handleAvatarVoiceStart();
          case 'avatarVoiceStop':
            _handleAvatarVoiceStop();
          case 'avatarClick':
            _handleAvatarClick();
          case 'avatarDoubleClick':
            _handleAvatarDoubleClick();
          case 'avatarMenuAction':
            final action = call.arguments as String? ?? '';
            _handleAvatarMenuAction(action);
          case 'avatarTextSubmit':
            final text = call.arguments as String? ?? '';
            _handleAvatarTextSubmit(text);
          case 'avatarTextSubmitWithAttachments':
            final data = call.arguments;
            if (data is Map) {
              _handleAvatarTextSubmitWithAttachments(
                  Map<String, dynamic>.from(data));
            }
          case 'avatarMenuActionWithData':
            final data = call.arguments;
            if (data is Map) {
              final m = Map<String, dynamic>.from(data);
              final action = m.remove('action') as String? ?? '';
              if (action == 'note_capture') {
                _handleNoteCaptureWithData(m);
              } else if (action == 'search_similar') {
                _handleSearchSimilar(m);
              } else if (action == 'start_reading') {
                _handleStartReading(m);
              } else if (action == 'ocr_text') {
                _handleOcrText(m);
              }
            }
          case 'avatarDrop':
            final data = call.arguments;
            if (data is Map) {
              _handleAvatarDrop(Map<String, dynamic>.from(data));
            }
          case 'readingSave':
            final data = call.arguments;
            if (data is Map) {
              _handleReadingSave(Map<String, dynamic>.from(data));
            }
          case 'readingSummarize':
            final data = call.arguments;
            if (data is Map) {
              _handleReadingSummarize(Map<String, dynamic>.from(data));
            }
          case 'avatarInputDismiss':
            runtime.avatarController.hideInput();
          case 'avatarLensResult':
            final data = call.arguments;
            if (data is Map) {
              _handleAvatarLensResult(Map<String, dynamic>.from(data));
            }
          case 'pluginMenuAction':
            final data = call.arguments;
            if (data is Map) {
              _handlePluginMenuAction(Map<String, dynamic>.from(data));
            }
        }
        return null;
      });
    } catch (_) {}
  }

  /// Creates or closes the separate OS-level avatar window (overlay pref only;
  /// not tied to gateway connection, same idea as Android `show_overlay`).
  Future<void> syncAvatarFloatingWindow() async {
    await runtime.syncAvatarFloatingWindow(show: _showAvatarOverlay);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _gatewayProfile =
        GatewayProfileX.fromStorage(prefs.getString('gateway.profile'));
    _host = prefs.getString('gateway.host') ?? '';
    _port = prefs.getInt('gateway.port') ?? _gatewayProfile.defaultPort;
    _token = prefs.getString('gateway.token') ?? '';
    _tls = prefs.getBool('gateway.tls') ?? false;
    if (_host.isEmpty && _gatewayProfile.defaultHost.isNotEmpty) {
      _host = _gatewayProfile.defaultHost;
    }
    _showAvatarOverlay =
        prefs.getBool('desktop.show_avatar_overlay') ?? true;
    _speakAssistantReplies =
        prefs.getBool('desktop.speak_assistant_replies') ?? true;
    runtime.speakAssistantReplies = _speakAssistantReplies;
    _locale = AppLocale.fromCode(prefs.getString('app.locale'));
    S.setLocale(_locale);
    notifyListeners();
    unawaited(syncAvatarFloatingWindow());
    // Auto-start local hiclaw and connect when profile is hiclaw.
    if (_gatewayProfile == GatewayProfile.hiclaw) {
      unawaited(_autoStartAndConnect());
    }
  }

  Future<void> setShowAvatarOverlay(bool value) async {
    _showAvatarOverlay = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('desktop.show_avatar_overlay', value);
    unawaited(syncAvatarFloatingWindow());
  }

  Future<void> setSpeakAssistantReplies(bool value) async {
    _speakAssistantReplies = value;
    runtime.speakAssistantReplies = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('desktop.speak_assistant_replies', value);
  }

  Future<void> setLocale(AppLocale locale) async {
    _locale = locale;
    S.setLocale(locale);
    notifyListeners();
    await S.saveLocale(locale);
  }

  Future<void> updateConnectionSettings({
    String? host,
    int? port,
    String? token,
    bool? tls,
    GatewayProfile? gatewayProfile,
  }) async {
    if (gatewayProfile != null && gatewayProfile != _gatewayProfile) {
      _gatewayProfile = gatewayProfile;
      _port = _gatewayProfile.defaultPort;
      if (_host.trim().isEmpty && _gatewayProfile.defaultHost.isNotEmpty) {
        _host = _gatewayProfile.defaultHost;
      }
      // Stop local hiclaw when switching to openclaw.
      if (gatewayProfile == GatewayProfile.openclaw && hiclawProcess.isRunning) {
        await hiclawProcess.stop();
      }
    }
    if (host != null) _host = host;
    if (port != null) _port = port;
    if (token != null) _token = token;
    if (tls != null) _tls = tls;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gateway.profile', _gatewayProfile.storageValue);
    await prefs.setString('gateway.host', _host);
    await prefs.setInt('gateway.port', _port);
    await prefs.setString('gateway.token', _token);
    await prefs.setBool('gateway.tls', _tls);
  }

  Future<void> connectToGateway() async {
    if (_host.trim().isEmpty) {
      if (!hiclawProcess.isRunning) {
        await hiclawProcess.start(port: _port);
      }
      _host = '127.0.0.1';
    }
    runtime.connect(
      profile: _gatewayProfile,
      host: _host.trim(),
      port: _port,
      token: _token.trim().isEmpty ? null : _token.trim(),
      tls: _tls,
    );
  }

  Future<void> disconnectFromGateway() async {
    runtime.disconnect();
    await hiclawProcess.stop();
  }

  Future<void> _autoStartAndConnect() async {
    if (!hiclawProcess.isRunning) {
      await hiclawProcess.start(port: _port);
    }
    if (hiclawProcess.error != null || !hiclawProcess.isRunning) {
      log.error('AppState: hiclaw auto-start failed (${hiclawProcess.error}), skipping connect');
      return;
    }
    await Future.delayed(const Duration(milliseconds: 500));
    _host = '127.0.0.1';
    connectToGateway();
  }

  @override
  void dispose() {
    hiclawProcess.dispose();
    _sttManager.destroy();
    runtime.removeListener(_onRuntimeChanged);
    cameraService.removeListener(_onCameraChanged);
    runtime.dispose();
    cameraService.dispose();
    super.dispose();
  }
}

/// Helper: BGRA pixel buffer with dimensions for PaddleOCR.
class _BgraImage {
  final Uint8List pixels;
  final int width;
  final int height;
  _BgraImage(this.pixels, this.width, this.height);
}
