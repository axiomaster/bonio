import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraInfo {
  final String id;
  final String facing;

  const CameraInfo({required this.id, required this.facing});

  Map<String, dynamic> toJson() => {'id': id, 'facing': facing};
}

class CameraService extends ChangeNotifier {
  List<CameraDescription>? _cameras;
  bool _available = false;
  bool _initialized = false;
  CameraController? _activeController;

  bool get available => _available;
  bool get initialized => _initialized;
  int get cameraCount => _cameras?.length ?? 0;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _cameras = await availableCameras();
      _available = _cameras != null && _cameras!.isNotEmpty;
    } catch (e) {
      debugPrint('CameraService: detection failed: $e');
      _cameras = null;
      _available = false;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    _initialized = false;
    await initialize();
  }

  List<CameraInfo> listCameras() {
    if (_cameras == null || _cameras!.isEmpty) return [];
    return _cameras!.map((c) {
      return CameraInfo(
        id: c.name,
        facing: _facingToString(c.lensDirection),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> snap({
    String? cameraId,
    String? facing,
  }) async {
    if (_cameras == null || _cameras!.isEmpty) {
      throw CameraServiceException('CAMERA_UNAVAILABLE', 'No cameras available');
    }

    final camera = _resolveCamera(cameraId: cameraId, facing: facing);
    if (camera == null) {
      throw CameraServiceException('CAMERA_NOT_FOUND',
          'No camera found matching cameraId=$cameraId facing=$facing');
    }

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller.initialize();
      _activeController = controller;

      // Small delay to let auto-exposure adjust
      await Future.delayed(const Duration(milliseconds: 500));

      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final base64Data = base64.encode(bytes);

      return {
        'cameraId': camera.name,
        'mimeType': 'image/jpeg',
        'base64': base64Data,
      };
    } catch (e) {
      throw CameraServiceException(
          'CAMERA_CAPTURE_FAILED', 'Capture failed: $e');
    } finally {
      _activeController = null;
      await controller.dispose();
    }
  }

  CameraDescription? _resolveCamera({String? cameraId, String? facing}) {
    if (_cameras == null || _cameras!.isEmpty) return null;

    // By explicit ID
    if (cameraId != null && cameraId.isNotEmpty) {
      for (final c in _cameras!) {
        if (c.name == cameraId) return c;
      }
      return null;
    }

    // By facing direction
    final targetDirection = _parseFacing(facing ?? 'front');
    for (final c in _cameras!) {
      if (c.lensDirection == targetDirection) return c;
    }

    // Desktop cameras are usually front-facing, fall back to first available
    return _cameras!.first;
  }

  CameraLensDirection _parseFacing(String facing) {
    switch (facing.toLowerCase()) {
      case 'back':
        return CameraLensDirection.back;
      case 'external':
        return CameraLensDirection.external;
      case 'front':
      default:
        return CameraLensDirection.front;
    }
  }

  String _facingToString(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.front:
        return 'front';
      case CameraLensDirection.back:
        return 'back';
      case CameraLensDirection.external:
        return 'external';
    }
  }

  List<String> get capabilities => _available ? ['camera'] : [];

  List<String> get commands => _available
      ? ['camera.list', 'camera.snap', 'camera.clip']
      : [];

  @override
  void dispose() {
    _activeController?.dispose();
    super.dispose();
  }
}

class CameraServiceException implements Exception {
  final String code;
  final String message;
  const CameraServiceException(this.code, this.message);

  @override
  String toString() => 'CameraServiceException($code: $message)';
}
