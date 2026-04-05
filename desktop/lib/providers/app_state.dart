import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_avatar_models.dart';
import '../models/gateway_profile.dart';
import '../services/node_runtime.dart';
import '../services/device_identity_store.dart';
import '../services/device_auth_store.dart';
import '../services/camera_service.dart';
import '../services/speech_to_text_manager.dart';

class AppState extends ChangeNotifier {
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

  final SpeechToTextManager _sttManager = SpeechToTextManager();

  String get host => _host;
  int get port => _port;
  String get token => _token;
  bool get tls => _tls;
  GatewayProfile get gatewayProfile => _gatewayProfile;
  bool get showAvatarOverlay => _showAvatarOverlay;
  bool get speakAssistantReplies => _speakAssistantReplies;

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

  /// Matches Android `MainViewModel.startVoiceInput()` / floating-window
  /// `SpeechToTextManager.Listener` pattern: partial results go to the avatar
  /// bubble so the user can see what's being recognised in real-time.
  void _handleAvatarVoiceTap() {
    if (_sttManager.isListening) {
      _sttManager.stopListening();
      return;
    }
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
        debugPrint('STT error: $code');
        runtime.avatarController.clearBubble();
        runtime.avatarController.setActivity(AgentAvatarActivity.idle);
      },
      end: () {
        runtime.avatarController.clearBubble();
        runtime.avatarController.setActivity(AgentAvatarActivity.idle);
      },
    ));
  }

  Future<void> _registerMainWindowHandler() async {
    try {
      final wc = await WindowController.fromCurrentEngine();
      await wc.setWindowMethodHandler((call) async {
        if (call.method == 'avatarVoiceTap') {
          _handleAvatarVoiceTap();
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
    notifyListeners();
    unawaited(syncAvatarFloatingWindow());
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

  void connectToGateway() {
    if (_host.trim().isEmpty) return;
    runtime.connect(
      profile: _gatewayProfile,
      host: _host.trim(),
      port: _port,
      token: _token.trim().isEmpty ? null : _token.trim(),
      tls: _tls,
    );
  }

  void disconnectFromGateway() {
    runtime.disconnect();
  }

  @override
  void dispose() {
    _sttManager.destroy();
    runtime.removeListener(_onRuntimeChanged);
    cameraService.removeListener(_onCameraChanged);
    runtime.dispose();
    cameraService.dispose();
    super.dispose();
  }
}
