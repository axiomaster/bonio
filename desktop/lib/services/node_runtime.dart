import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/agent_avatar_models.dart';
import '../models/avatar_snapshot.dart';
import '../models/gateway_models.dart';
import '../models/gateway_profile.dart';
import '../models/server_config.dart';
import '../models/channel_config.dart';
import '../models/skill_models.dart';
import 'gateway_session.dart';
import 'device_identity_store.dart';
import 'device_auth_store.dart';
import 'config_repository.dart';
import 'channel_repository.dart';
import 'skill_repository.dart';
import 'avatar_command_executor.dart';
import 'avatar_controller.dart';
import 'chat_controller.dart';
import 'camera_service.dart';
import 'desktop_tts.dart';
import 'note_service.dart';
import '../l10n/app_strings.dart';
import '../platform/gui_agent.dart';
import '../platform/gui_grounder.dart';
import '../platform/cdp/cdp_browser_agent.dart';
import '../plugins/builtin_plugins.dart';
import '../plugins/plugin_manifest.dart';
import '../platform/ocr/paddle_ocr_bridge.dart';
import 'app_logger.dart';
import '../plugins/plugin_manager.dart';

/// On macOS, `localhost` often resolves to IPv6 (`::1`) while a local OpenClaw
/// gateway may listen on IPv4 only (`127.0.0.1`), causing connection failures
/// that do not reproduce on Windows. Prefer explicit IPv4 loopback for WS.
String _normalizeGatewayHost(String host) {
  final t = host.trim();
  if (t.isEmpty) return t;
  switch (t.toLowerCase()) {
    case 'localhost':
    case '::1':
      return '127.0.0.1';
    default:
      return t;
  }
}

class NodeRuntime extends ChangeNotifier {
  final DeviceIdentityStore identityStore;
  final DeviceAuthStore deviceAuthStore;
  final CameraService cameraService;

  late final GatewaySession operatorSession;
  late final GatewaySession nodeSession;
  late final ConfigRepository configRepository;
  late final ChannelRepository channelRepository;
  late final SkillRepository skillRepository;
  late final ChatController chatController;
  late final AvatarController avatarController;
  late final AvatarCommandExecutor avatarCommandExecutor;
  late final DesktopTts desktopTts;
  late final NoteService noteService;
  late final GuiAgent guiAgent;
  late final PluginManager pluginManager;
  late final PaddleOcr paddleOcr;
  Future<bool>? _paddleOcrInitFuture;

  WindowController? _avatarWindowController;
  WindowController? _readingWindowController;
  int _readingCompanionHwnd = 0;

  /// When true, read assistant replies aloud after each completed turn.
  bool speakAssistantReplies = true;

  /// Avoid racing [AvatarController] with chat-driven activity while TTS runs.
  bool _avatarTtsSpeaking = false;

  bool _isConnected = false;
  bool _nodeConnected = false;
  String _connectionStatus = S.current.statusOffline;
  String? _serverName;
  String? _remoteAddress;
  ServerConfig? _serverConfig;

  List<SkillInfo> _skills = [];
  bool _skillsLoading = false;
  String? _skillsError;

  ChannelConfig? _channelConfig;

  List<SkillInfo> get skills => _skills;
  bool get skillsLoading => _skillsLoading;
  String? get skillsError => _skillsError;
  ChannelConfig? get channelConfig => _channelConfig;

  /// Stagger second WebSocket so OpenClaw completes operator handshake first.
  Timer? _nodeConnectTimer;

  bool get isConnected => _isConnected;
  bool get nodeConnected => _nodeConnected;
  String get connectionStatus => _connectionStatus;
  String? get serverName => _serverName;
  String? get remoteAddress => _remoteAddress;
  ServerConfig? get serverConfig => _serverConfig;

  NodeRuntime({
    required this.identityStore,
    required this.deviceAuthStore,
    required this.cameraService,
  }) {
    operatorSession = GatewaySession(
      identityStore: identityStore,
      deviceAuthStore: deviceAuthStore,
      onConnected: _onOperatorConnected,
      onDisconnected: _onOperatorDisconnected,
      onEvent: _onOperatorEvent,
    );

    nodeSession = GatewaySession(
      identityStore: identityStore,
      deviceAuthStore: deviceAuthStore,
      onConnected: _onNodeConnected,
      onDisconnected: _onNodeDisconnected,
      onEvent: (_, __) {},
      onInvoke: _onNodeInvoke,
    );

    configRepository = ConfigRepository(session: operatorSession);
    channelRepository = ChannelRepository(operatorSession);
    skillRepository = SkillRepository(operatorSession);
    desktopTts = DesktopTts();
    chatController = ChatController(
      session: operatorSession,
      onAssistantReplyForTts: _onAssistantReplyForTts,
    );
    avatarController = AvatarController();
    avatarCommandExecutor = AvatarCommandExecutor(
      controller: avatarController,
      tts: desktopTts,
    );
    noteService = NoteService(session: operatorSession);
    guiAgent = GuiAgent.create();
    pluginManager = PluginManager();
    paddleOcr = PaddleOcr();
    pluginManager.registerBuiltin(NoteCapturePlugin());
    pluginManager.registerBuiltin(AiLensPlugin());
    pluginManager.registerBuiltin(SearchSimilarPlugin());
    pluginManager.registerBuiltin(ReadingCompanionPlugin());
    pluginManager.addListener(pushPluginMenuToAvatar);
    unawaited(pluginManager.initialize());
    // Initialize PaddleOCR (local OCR engine)
    _paddleOcrInitFuture = _initPaddleOcr();
    // ChatController / AvatarController updates must bubble to AppState.
    chatController.addListener(_onChatControllerChanged);
    avatarController.addListener(_onAvatarControllerChanged);
  }

  Future<bool> ensurePaddleOcrReady() async {
    if (paddleOcr.isInitialized) return true;
    final future = _paddleOcrInitFuture ??= _initPaddleOcr();
    return future;
  }

  Future<bool> _initPaddleOcr() async {
    if (!Platform.isWindows) return false; // macOS/Linux not yet supported
    try {
      final exeDir = Directory(Platform.resolvedExecutable).parent;
      final modelDir =
          '${exeDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}ocr';
      final ortPath = '${exeDir.path}${Platform.pathSeparator}onnxruntime.dll';
      AppLogger.instance.info(
          'PaddleOCR: initializing, exe_dir=${exeDir.path}, model_dir=$modelDir, ort=$ortPath');
      final ok = await paddleOcr.init(modelDir: modelDir);
      if (ok) {
        AppLogger.instance.info('PaddleOCR: initialized successfully');
      } else {
        AppLogger.instance.warn(
            'PaddleOCR: init failed, OCR will stay on client and report unavailable');
      }
      return ok;
    } catch (e) {
      AppLogger.instance.warn('PaddleOCR: init error: $e');
      return false;
    }
  }

  void _onAssistantReplyForTts(String text) {
    if (!speakAssistantReplies) {
      debugPrint('NodeRuntime: TTS disabled by user setting');
      return;
    }
    debugPrint('NodeRuntime: TTS speaking (${text.length} chars)');
    _avatarTtsSpeaking = true;
    avatarController.setActivity(AgentAvatarActivity.speaking);
    avatarController.setBubble(text: text);
    unawaited(() async {
      try {
        await desktopTts.speak(text);
        debugPrint('NodeRuntime: TTS finished');
      } catch (e) {
        debugPrint('NodeRuntime: TTS error: $e');
      } finally {
        _avatarTtsSpeaking = false;
        avatarController.clearBubble();
        _syncAvatarActivityFromChat();
      }
    }());
  }

  void _onChatControllerChanged() {
    _syncAvatarActivityFromChat();
    notifyListeners();
  }

  /// Mirrors Android [AgentStateManager] + [MainViewModel] coarse transitions,
  /// plus Android [FloatingWindowService] streaming-text → bubble sync.
  void _syncAvatarActivityFromChat() {
    if (_avatarTtsSpeaking) return;
    final chat = chatController;

    // Activity
    if (chat.pendingRunCount > 0) {
      if (chat.pendingToolCalls.isNotEmpty) {
        avatarController.setActivity(AgentAvatarActivity.working);
      } else {
        avatarController.setActivity(AgentAvatarActivity.thinking);
      }
    } else {
      avatarController.setActivity(AgentAvatarActivity.idle);
    }

    // Bubble: show streaming text (matches Android FloatingWindowService).
    final streaming = chat.streamingAssistantText;
    if (streaming != null && streaming.isNotEmpty) {
      avatarController.setBubble(text: streaming);
    } else if (avatarController.activity != AgentAvatarActivity.listening) {
      avatarController.clearBubble();
    }
  }
  void _onAvatarControllerChanged() {
    notifyListeners();
    _pushAvatarSync();
  }

  /// Show or hide the OS-level floating avatar window (independent of main UI).
  Future<void> syncAvatarFloatingWindow({required bool show}) async {
    if (show) {
      await _ensureAvatarWindow();
    } else {
      await _closeAvatarWindow();
    }
  }

  Future<void> _ensureAvatarWindow() async {
    if (_avatarWindowController != null) return;
    try {
      final main = await WindowController.fromCurrentEngine();
      avatarController.setBounds(AvatarSnapshot.kFloatingWindowSize);
      _avatarWindowController = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          borderless: true,
          width: AvatarSnapshot.kFloatingWindowSize.width,
          height: AvatarSnapshot.kFloatingWindowSize.height,
          arguments: jsonEncode({
            'bonioWindow': 'avatar',
            'mainWindowId': main.windowId,
          }),
        ),
      );
      await _avatarWindowController!.show();
      _pushAvatarSync();
      pushPluginMenuToAvatar();
    } catch (e, st) {
      debugPrint('avatar floating window: $e\n$st');
    }
  }

  Future<void> createReadingWindow(
      String url, String title,
      double physX, double physY,
      double logicalW, double logicalH,
      {PageContent? cdpContent, int browserHwnd = 0}) async {
    await _closeReadingWindow();
    try {
      final main = await WindowController.fromCurrentEngine();
      final args = <String, dynamic>{
        'bonioWindow': 'reading_companion',
        'url': url,
        'title': title,
        'mainWindowId': main.windowId,
        'windowWidth': logicalW,
        'windowHeight': logicalH,
        'browserHwnd': browserHwnd,
      };
      if (cdpContent != null) {
        args['cdpText'] = cdpContent.text;
        args['cdpTitle'] = cdpContent.title;
        args['cdpUrl'] = cdpContent.url;
        args['cdpHeadings'] =
            cdpContent.headings.map((h) => h.toJson()).toList();
      }
      final wc = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          borderless: false,
          width: logicalW,
          height: logicalH,
          arguments: jsonEncode(args),
        ),
      );
      _readingWindowController = wc;
      await wc.setPositionPhysical(physX, physY);
      // Store the reading companion's native HWND so the avatar can skip it.
      try {
        _readingCompanionHwnd = await wc.getHwnd();
      } catch (_) {}
      try {
        if (_avatarWindowController != null && _readingCompanionHwnd != 0) {
          await _avatarWindowController!.invokeMethod(
              'syncReadingHwnd', _readingCompanionHwnd);
        }
      } catch (_) {}
    } catch (e, st) {
      debugPrint('createReadingWindow: $e\n$st');
    }
  }

  Future<void> _closeReadingWindow() async {
    final ctrl = _readingWindowController;
    _readingWindowController = null;
    _readingCompanionHwnd = 0;
    if (ctrl == null) return;
    try {
      await ctrl.invokeMethod('window_close');
    } catch (_) {}
  }

  /// Run the UI grounding → classify → menu boost pipeline for the current
  /// foreground window. Called on avatar single-click.
  ///
  /// Only executes if at least 5 min have passed since the last recognition
  /// for the same window (to avoid repeated server calls on rapid clicks).
  Future<void> recognizeContext() async {
    if (_contextRecognitionInProgress) return;
    final hwnd = guiAgent.window.getForegroundWindow();
    if (hwnd == 0) return;

    final title = guiAgent.window.getWindowTitle(hwnd);
    final cacheKey = '$hwnd:$title';
    final now = DateTime.now();
    if (_lastContextRecognition == cacheKey) {
      final elapsed = now.difference(_lastRecognitionTime);
      if (elapsed < const Duration(minutes: 5)) return;
    }

    _contextRecognitionInProgress = true;
    _lastContextRecognition = cacheKey;
    _lastRecognitionTime = now;

    try {
      // Step 1: UI Grounding
      final grounder = GuiGrounder(
        agent: guiAgent,
        cdpAgent: guiAgent.browser as CdpBrowserAgent?,
      );
      final result = await grounder.ground(hwnd);
      if (result == null) return;

      // Step 2: Classify via server
      final availableTags = pluginManager.getAvailableTags();
      if (availableTags.isEmpty) return;

      final res = await operatorSession.request(
        'context.classify',
        jsonEncode({
          'uiStructure': result.structure.toJson(),
          'availableTags': availableTags,
        }),
        timeoutMs: 15000,
      );
      final obj = jsonDecode(res) as Map<String, dynamic>?;
      if (obj == null || obj['ok'] != true) return;
      final tags = (obj['payload']?['tags'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (tags.isEmpty) return;

      // Step 3: Boost menu
      pluginManager.applyClassificationBoost(tags);

      // Step 4: Suggest high-confidence plugins via avatar bubble
      final highConf = <Map<String, dynamic>>[];
      for (final t in tags) {
        final conf = (t['confidence'] as num?)?.toDouble() ?? 0;
        if (conf >= 0.7) highConf.add(t);
      }
      if (highConf.isNotEmpty) {
        final tag = highConf.first['tag'] as String;
        PluginManifest? matched;
        for (final m in pluginManager.registry.enabledMenuPlugins) {
          if (m.supportedContexts.any((c) => c.tag == tag)) {
            matched = m;
            break;
          }
        }
        if (matched != null) {
          final suggestion = '检测到${matched.name.current}相关内容，'
              '要试试${matched.name.current}吗？';
          avatarController.setBubble(text: suggestion);
        }
      }
    } catch (e) {
      AppLogger.instance.warn('recognizeContext failed: $e');
    } finally {
      _contextRecognitionInProgress = false;
    }
  }

  bool _contextRecognitionInProgress = false;
  String? _lastContextRecognition;
  DateTime _lastRecognitionTime = DateTime(2000);

  /// Create an independent OS window showing OCR recognition results.
  Future<void> createOcrResultWindow(String text, {String? imageBase64}) async {
    try {
      final main = await WindowController.fromCurrentEngine();
      const w = 480.0;
      const h = 420.0;
      final wc = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          borderless: false,
          width: w,
          height: h,
          arguments: jsonEncode({
            'bonioWindow': 'ocr_result',
            'text': text,
            'imageBase64': imageBase64 ?? '',
            'mainWindowId': main.windowId,
          }),
        ),
      );
      // Position near the center of the primary screen
      await wc.setPosition(Offset(200, 120));
      await wc.show();
    } catch (e) {
      AppLogger.instance.warn('createOcrResultWindow failed: $e');
    }
  }

  Future<void> createSearchWindow(String imagePath, double x, double y) async {
    try {
      final main = await WindowController.fromCurrentEngine();
      const w = 420.0;
      const h = 560.0;
      final wc = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          borderless: false,
          width: w,
          height: h,
          arguments: jsonEncode({
            'bonioWindow': 'search_similar',
            'imagePath': imagePath,
            'mainWindowId': main.windowId,
          }),
        ),
      );
      await wc.setPosition(Offset(x - w / 2, y + 80));
      await wc.show();
    } catch (e, st) {
      debugPrint('createSearchWindow: $e\n$st');
    }
  }

  void _pushAvatarSync() {
    final ctrl = _avatarWindowController;
    if (ctrl == null) return;
    unawaited(_invokeAvatarSync(ctrl));
  }

  /// Push the current plugin menu items to the avatar floating window.
  void pushPluginMenuToAvatar() {
    final ctrl = _avatarWindowController;
    if (ctrl == null) return;
    final items = pluginManager.getMenuItems();
    // Attach pluginId for routing on the avatar side
    final plugins = pluginManager.registry.enabledMenuPlugins;
    final enriched = <Map<String, dynamic>>[];
    for (var i = 0; i < items.length; i++) {
      enriched.add({
        ...items[i],
        'pluginId': i < plugins.length ? plugins[i].id : '',
      });
    }
    unawaited(() async {
      try {
        await ctrl.invokeMethod('syncPluginMenu', enriched);
      } catch (_) {}
    }());
  }

  Future<void> _invokeAvatarSync(WindowController ctrl) async {
    try {
      await ctrl.invokeMethod('sync', avatarController.toSnapshot().toJson());
    } catch (_) {}
  }

  Future<void> _closeAvatarWindow() async {
    final ctrl = _avatarWindowController;
    _avatarWindowController = null;
    if (ctrl == null) return;
    try {
      await ctrl.invokeMethod('window_close');
    } catch (_) {}
  }

  void connect({
    GatewayProfile profile = GatewayProfile.hiclaw,
    required String host,
    required int port,
    String? token,
    String? password,
    bool tls = false,
  }) {
    final endpoint = GatewayEndpoint.manual(_normalizeGatewayHost(host), port);

    final operatorOptions = GatewayConnectOptions(
      role: 'operator',
      scopes: profile.operatorScopes,
      client: _buildClientInfo(profile, role: 'operator'),
    );

    final nodeOptions = GatewayConnectOptions(
      role: 'node',
      caps: _buildNodeCaps(),
      commands: _buildNodeCommands(),
      client: _buildClientInfo(profile, role: 'node'),
    );

    _nodeConnectTimer?.cancel();
    operatorSession.connect(
      endpoint: endpoint,
      token: token,
      password: password,
      options: operatorOptions,
    );

    _nodeConnectTimer = Timer(const Duration(milliseconds: 400), () {
      _nodeConnectTimer = null;
      nodeSession.connect(
        endpoint: endpoint,
        token: token,
        password: password,
        options: nodeOptions,
      );
    });
  }

  void disconnect() {
    desktopTts.stop();
    _nodeConnectTimer?.cancel();
    _nodeConnectTimer = null;
    operatorSession.disconnect();
    nodeSession.disconnect();
    _isConnected = false;
    _nodeConnected = false;
    _connectionStatus = S.current.statusOffline;
    _serverName = null;
    _remoteAddress = null;
    _serverConfig = null;
    chatController.onDisconnected(S.current.statusOffline);
    notifyListeners();
  }

  Future<void> refreshServerConfig() async {
    try {
      _serverConfig = await configRepository.getConfig();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateServerConfig({
    String? defaultModel,
    List<ModelConfig>? models,
  }) async {
    try {
      await configRepository.setConfig(
        defaultModel: defaultModel,
        models: models,
      );
      await refreshServerConfig();
    } catch (_) {}
  }

  // -- Skills management --

  Future<void> refreshSkills() async {
    _skillsLoading = true;
    _skillsError = null;
    notifyListeners();
    try {
      _skills = await skillRepository.listSkills();
    } catch (e) {
      _skillsError = e.toString();
    } finally {
      _skillsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshChannel() async {
    try {
      _channelConfig = await channelRepository.getConfig();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleSkill(String id, bool enable) async {
    try {
      if (enable) {
        await skillRepository.enableSkill(id);
      } else {
        await skillRepository.disableSkill(id);
      }
      await refreshSkills();
    } catch (e) {
      _skillsError = e.toString();
      notifyListeners();
    }
  }

  Future<void> installSkill(String id, String content) async {
    try {
      await skillRepository.installSkill(id, content);
      await refreshSkills();
    } catch (e) {
      _skillsError = e.toString();
      notifyListeners();
    }
  }

  Future<void> removeSkill(String id) async {
    try {
      await skillRepository.removeSkill(id);
      await refreshSkills();
    } catch (e) {
      _skillsError = e.toString();
      notifyListeners();
    }
  }

  // -- Node capabilities (dynamic) --

  List<String> _buildNodeCaps() {
    return [
      'desktop.info',
      ...cameraService.capabilities,
    ];
  }

  List<String> _buildNodeCommands() {
    return [
      'device.info',
      'device.platform',
      ...cameraService.commands,
    ];
  }

  // -- Callbacks --

  void _onOperatorConnected(
      String? serverName, String? remoteAddress, String? mainSessionKey) {
    _isConnected = true;
    _serverName = serverName;
    _remoteAddress = remoteAddress;
    _updateConnectionStatus();
    notifyListeners();

    // applyMainSessionKey() already runs _bootstrap; avoid a second load() racing
    // and overwriting messages / clearing in-flight run state.
    if (mainSessionKey != null) {
      chatController.applyMainSessionKey(mainSessionKey);
    } else {
      chatController.load(chatController.sessionKey);
    }
    refreshServerConfig();
    refreshSkills();
    refreshChannel();
  }

  void _onOperatorDisconnected(String message) {
    _isConnected = false;
    _connectionStatus = message;
    _skills = [];
    _skillsError = null;
    _channelConfig = null;
    chatController.onDisconnected(message);
    notifyListeners();
  }

  /// Temporary event listener for one-shot operations (e.g. OCR).
  /// Set before sending a request, cleared after receiving the response.
  void Function(String event, String? payloadJson)? tempEventListener;

  void _onOperatorEvent(String event, String? payloadJson) {
    if (event == 'avatar.command') {
      avatarCommandExecutor.execute(payloadJson);
    }
    // Allow temporary listeners (OCR etc.) to intercept events first
    tempEventListener?.call(event, payloadJson);
    // Let NoteService intercept events for its sessions next.
    if (!noteService.handleGatewayEvent(event, payloadJson)) {
      if (!noteService.handleReadingEvent(event, payloadJson)) {
        chatController.handleGatewayEvent(event, payloadJson);
      }
    }
  }

  void _onNodeConnected(
      String? serverName, String? remoteAddress, String? mainSessionKey) {
    _nodeConnected = true;
    _updateConnectionStatus();
    notifyListeners();
  }

  void _onNodeDisconnected(String message) {
    _nodeConnected = false;
    _updateConnectionStatus();
    notifyListeners();
  }

  Future<InvokeResult> _onNodeInvoke(InvokeRequest request) async {
    switch (request.command) {
      case 'device.info':
        return InvokeResult.success(jsonEncode({
          'platform': Platform.operatingSystem,
          'version': Platform.operatingSystemVersion,
        }));
      case 'device.platform':
        return InvokeResult.success(jsonEncode({
          'platform': Platform.operatingSystem,
        }));
      case 'camera.list':
        return _handleCameraList();
      case 'camera.snap':
        return _handleCameraSnap(request.paramsJson);
      case 'camera.clip':
        return InvokeResult.fail(
            'NOT_IMPLEMENTED', 'camera.clip video recording is not yet supported on desktop');
      default:
        return InvokeResult.fail('UNSUPPORTED_COMMAND',
            'Desktop client does not support: ${request.command}');
    }
  }

  InvokeResult _handleCameraList() {
    if (!cameraService.available) {
      return InvokeResult.fail('CAMERA_UNAVAILABLE', 'No cameras detected on this device');
    }
    final cameras = cameraService.listCameras();
    return InvokeResult.success(jsonEncode({
      'cameras': cameras.map((c) => c.toJson()).toList(),
    }));
  }

  Future<InvokeResult> _handleCameraSnap(String? paramsJson) async {
    if (!cameraService.available) {
      return InvokeResult.fail('CAMERA_UNAVAILABLE', 'No cameras detected on this device');
    }
    String? cameraId;
    String? facing;
    if (paramsJson != null && paramsJson.trim().isNotEmpty) {
      try {
        final params = jsonDecode(paramsJson) as Map<String, dynamic>;
        cameraId = params['cameraId'] as String?;
        facing = params['facing'] as String?;
      } catch (_) {}
    }
    // Default facing to 'front' on desktop (most common webcam position)
    facing ??= 'front';

    try {
      final result = await cameraService.snap(cameraId: cameraId, facing: facing);
      return InvokeResult.success(jsonEncode(result));
    } on CameraServiceException catch (e) {
      return InvokeResult.fail(e.code, e.message);
    } catch (e) {
      return InvokeResult.fail('CAMERA_CAPTURE_FAILED', 'Unexpected error: $e');
    }
  }

  void _updateConnectionStatus() {
    if (_isConnected && _nodeConnected) {
      _connectionStatus = S.current.statusConnected;
    } else if (_isConnected) {
      _connectionStatus = S.current.statusConnectedNodeOffline;
    } else {
      _connectionStatus = S.current.statusOffline;
    }
  }

  GatewayClientInfo _buildClientInfo(GatewayProfile profile,
          {required String role}) =>
      GatewayClientInfo(
        id: profile.clientId,
        displayName: S.current.appName,
        version: '1.0.0',
        platform: Platform.operatingSystem,
        mode: profile.clientModeForRole(role),
        deviceFamily: 'desktop',
      );

  @override
  void dispose() {
    _nodeConnectTimer?.cancel();
    _nodeConnectTimer = null;
    unawaited(_closeAvatarWindow());
    unawaited(_closeReadingWindow());
    guiAgent.dispose();
    pluginManager.removeListener(pushPluginMenuToAvatar);
    pluginManager.dispose();
    chatController.removeListener(_onChatControllerChanged);
    avatarController.removeListener(_onAvatarControllerChanged);
    operatorSession.dispose();
    nodeSession.dispose();
    chatController.dispose();
    avatarController.dispose();
    super.dispose();
  }
}
