import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/gateway_models.dart';
import '../models/server_config.dart';
import 'gateway_session.dart';
import 'device_identity_store.dart';
import 'device_auth_store.dart';
import 'config_repository.dart';
import 'chat_controller.dart';
import 'camera_service.dart';

class NodeRuntime extends ChangeNotifier {
  final DeviceIdentityStore identityStore;
  final DeviceAuthStore deviceAuthStore;
  final CameraService cameraService;

  late final GatewaySession operatorSession;
  late final GatewaySession nodeSession;
  late final ConfigRepository configRepository;
  late final ChatController chatController;

  bool _isConnected = false;
  bool _nodeConnected = false;
  String _connectionStatus = 'Offline';
  String? _serverName;
  String? _remoteAddress;
  ServerConfig? _serverConfig;

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
    chatController = ChatController(session: operatorSession);
  }

  void connect({
    required String host,
    required int port,
    String? token,
    String? password,
    bool tls = false,
  }) {
    final endpoint = GatewayEndpoint.manual(host, port);

    final operatorOptions = GatewayConnectOptions(
      role: 'operator',
      scopes: ['operator.read', 'operator.write', 'operator.talk.secrets'],
      client: _buildClientInfo(),
    );

    final nodeOptions = GatewayConnectOptions(
      role: 'node',
      caps: _buildNodeCaps(),
      commands: _buildNodeCommands(),
      client: _buildClientInfo(),
    );

    operatorSession.connect(
      endpoint: endpoint,
      token: token,
      password: password,
      options: operatorOptions,
    );

    nodeSession.connect(
      endpoint: endpoint,
      token: token,
      password: password,
      options: nodeOptions,
    );
  }

  void disconnect() {
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

    if (mainSessionKey != null) {
      chatController.applyMainSessionKey(mainSessionKey);
    }
    chatController.load(chatController.sessionKey);
    refreshServerConfig();
  }

  void _onOperatorDisconnected(String message) {
    _isConnected = false;
    _connectionStatus = message;
    chatController.onDisconnected(message);
    notifyListeners();
  }

  void _onOperatorEvent(String event, String? payloadJson) {
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

  GatewayClientInfo _buildClientInfo() => GatewayClientInfo(
        id: 'boji-desktop',
        displayName: 'BoJi Desktop',
        version: '1.0.0',
        platform: Platform.operatingSystem,
        mode: 'companion',
        deviceFamily: 'desktop',
      );

  @override
  void dispose() {
    operatorSession.dispose();
    nodeSession.dispose();
    chatController.dispose();
    super.dispose();
  }
}
