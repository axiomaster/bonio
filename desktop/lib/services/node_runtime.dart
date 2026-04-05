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
import 'gateway_session.dart';
import 'device_identity_store.dart';
import 'device_auth_store.dart';
import 'config_repository.dart';
import 'avatar_command_executor.dart';
import 'avatar_controller.dart';
import 'chat_controller.dart';
import 'camera_service.dart';
import 'desktop_tts.dart';

class NodeRuntime extends ChangeNotifier {
  final DeviceIdentityStore identityStore;
  final DeviceAuthStore deviceAuthStore;
  final CameraService cameraService;

  late final GatewaySession operatorSession;
  late final GatewaySession nodeSession;
  late final ConfigRepository configRepository;
  late final ChatController chatController;
  late final AvatarController avatarController;
  late final AvatarCommandExecutor avatarCommandExecutor;
  late final DesktopTts desktopTts;

  WindowController? _avatarWindowController;

  /// When true, read assistant replies aloud after each completed turn.
  bool speakAssistantReplies = true;

  /// Avoid racing [AvatarController] with chat-driven activity while TTS runs.
  bool _avatarTtsSpeaking = false;

  bool _isConnected = false;
  bool _nodeConnected = false;
  String _connectionStatus = 'Offline';
  String? _serverName;
  String? _remoteAddress;
  ServerConfig? _serverConfig;

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
    // ChatController / AvatarController updates must bubble to AppState.
    chatController.addListener(_onChatControllerChanged);
    avatarController.addListener(_onAvatarControllerChanged);
  }

  void _onAssistantReplyForTts(String text) {
    if (!speakAssistantReplies) return;
    _avatarTtsSpeaking = true;
    avatarController.setActivity(AgentAvatarActivity.speaking);
    avatarController.setBubble(text: text);
    unawaited(() async {
      try {
        await desktopTts.speak(text);
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
          arguments: jsonEncode({
            'bojiWindow': 'avatar',
            'mainWindowId': main.windowId,
          }),
        ),
      );
      await _avatarWindowController!.show();
      _pushAvatarSync();
    } catch (e, st) {
      debugPrint('avatar floating window: $e\n$st');
    }
  }

  void _pushAvatarSync() {
    final ctrl = _avatarWindowController;
    if (ctrl == null) return;
    unawaited(_invokeAvatarSync(ctrl));
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
    final endpoint = GatewayEndpoint.manual(host, port);

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
    _nodeConnectTimer?.cancel();
    _nodeConnectTimer = null;
    operatorSession.disconnect();
    nodeSession.disconnect();
    _isConnected = false;
    _nodeConnected = false;
    _connectionStatus = 'Offline';
    _serverName = null;
    _remoteAddress = null;
    _serverConfig = null;
    chatController.onDisconnected('Offline');
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
  }

  void _onOperatorDisconnected(String message) {
    _isConnected = false;
    _connectionStatus = message;
    chatController.onDisconnected(message);
    notifyListeners();
  }

  void _onOperatorEvent(String event, String? payloadJson) {
    if (event == 'avatar.command') {
      avatarCommandExecutor.execute(payloadJson);
    }
    chatController.handleGatewayEvent(event, payloadJson);
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
      _connectionStatus = 'Connected';
    } else if (_isConnected) {
      _connectionStatus = 'Connected (node offline)';
    } else {
      _connectionStatus = 'Offline';
    }
  }

  GatewayClientInfo _buildClientInfo(GatewayProfile profile,
          {required String role}) =>
      GatewayClientInfo(
        id: profile.clientId,
        displayName: 'BoJi Desktop',
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
    chatController.removeListener(_onChatControllerChanged);
    avatarController.removeListener(_onAvatarControllerChanged);
    operatorSession.dispose();
    nodeSession.dispose();
    chatController.dispose();
    avatarController.dispose();
    super.dispose();
  }
}
