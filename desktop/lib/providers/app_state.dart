import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'dart:convert';

import '../models/agent_avatar_models.dart';
import '../models/chat_models.dart';
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

  /// Long-press end → stop STT, finalize and send accumulated text.
  void _handleAvatarVoiceStop() {
    if (!_sttManager.isListening) return;
    _sttManager.stopListening();
  }

  void _handleAvatarClick() {
    runtime.avatarController.triggerClickReaction();
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
      text.isNotEmpty ? text : '[Image attachment]',
      attachments: attachments,
    );
  }

  void _handleAvatarLensResult(Map<String, dynamic> data) {
    debugPrint('AppState: received avatarLensResult, keys=${data.keys.toList()}');
    final windowTitle = data['windowTitle'] as String? ?? '';
    final rects = (data['rects'] as List?)
            ?.map((r) => Map<String, dynamic>.from(r as Map))
            .toList() ??
        [];
    final pngBase64 = data['pngBase64'] as String? ?? '';

    debugPrint('AppState: lens title="$windowTitle", rects=${rects.length}, '
        'base64Len=${pngBase64.length}');

    if (pngBase64.isEmpty) {
      debugPrint('AppState: lens result has no screenshot');
      return;
    }

    // Build structured prompt
    final buf = StringBuffer();
    buf.writeln('[BoJi Lens] 用户在应用窗口 "$windowTitle" 上进行了圈选标注。');
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

    debugPrint('AppState: sending lens result via chat.send...');
    runtime.chatController.sendMessage(
      buf.toString(),
      attachments: [
        OutgoingAttachment(
          type: 'image',
          mimeType: 'image/png',
          fileName: 'boji_lens_capture.png',
          base64: pngBase64,
        ),
      ],
    );
    debugPrint('AppState: lens chat.send dispatched');
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
          case 'avatarInputDismiss':
            runtime.avatarController.hideInput();
          case 'avatarLensResult':
            final data = call.arguments;
            if (data is Map) {
              _handleAvatarLensResult(Map<String, dynamic>.from(data));
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
