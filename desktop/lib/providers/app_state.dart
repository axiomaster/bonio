import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/node_runtime.dart';
import '../services/device_identity_store.dart';
import '../services/device_auth_store.dart';
import '../services/camera_service.dart';

class AppState extends ChangeNotifier {
  late final NodeRuntime runtime;
  final DeviceIdentityStore _identityStore = DeviceIdentityStore();
  final DeviceAuthStore _deviceAuthStore = DeviceAuthStore();
  final CameraService cameraService = CameraService();

  String _host = '';
  int _port = 10724;
  String _token = '';
  bool _tls = false;

  String get host => _host;
  int get port => _port;
  String get token => _token;
  bool get tls => _tls;

  AppState() {
    _initCamera();
    runtime = NodeRuntime(
      identityStore: _identityStore,
      deviceAuthStore: _deviceAuthStore,
      cameraService: cameraService,
    );
    runtime.addListener(_onRuntimeChanged);
    cameraService.addListener(_onCameraChanged);
    _loadPrefs();
  }

  Future<void> _initCamera() async {
    await cameraService.initialize();
  }

  void _onRuntimeChanged() => notifyListeners();
  void _onCameraChanged() => notifyListeners();

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString('gateway.host') ?? '';
    _port = prefs.getInt('gateway.port') ?? 10724;
    _token = prefs.getString('gateway.token') ?? '';
    _tls = prefs.getBool('gateway.tls') ?? false;
    notifyListeners();
  }

  Future<void> updateConnectionSettings({
    String? host,
    int? port,
    String? token,
    bool? tls,
  }) async {
    if (host != null) _host = host;
    if (port != null) _port = port;
    if (token != null) _token = token;
    if (tls != null) _tls = tls;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gateway.host', _host);
    await prefs.setInt('gateway.port', _port);
    await prefs.setString('gateway.token', _token);
    await prefs.setBool('gateway.tls', _tls);
  }

  void connectToGateway() {
    if (_host.trim().isEmpty) return;
    runtime.connect(
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
    runtime.removeListener(_onRuntimeChanged);
    cameraService.removeListener(_onCameraChanged);
    runtime.dispose();
    cameraService.dispose();
    super.dispose();
  }
}
