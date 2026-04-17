import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../platform/screen_capture.dart';

/// Fullscreen overlay for AI Lens: shows a captured screenshot with a dark
/// mask, lets the user drag-select a region, then returns the cropped PNG.
class AiLensScreen extends StatefulWidget {
  const AiLensScreen({super.key});

  /// Shows the AI Lens overlay and returns the selected region as PNG bytes,
  /// or null if cancelled.
  static Future<Uint8List?> show(BuildContext context) async {
    final capture = ScreenCapture.captureScreen();
    if (capture == null) {
      debugPrint('AiLens: screen capture failed');
      return null;
    }

    final result = await Navigator.of(context).push<Uint8List>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => AiLensScreen._withCapture(capture),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 150),
      ),
    );
    return result;
  }

  static Widget _withCapture(ScreenCaptureResult capture) =>
      _AiLensOverlay(capture: capture);

  @override
  State<AiLensScreen> createState() => _AiLensScreenState();
}

class _AiLensScreenState extends State<AiLensScreen> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _AiLensOverlay extends StatefulWidget {
  final ScreenCaptureResult capture;
  const _AiLensOverlay({required this.capture});

  @override
  State<_AiLensOverlay> createState() => _AiLensOverlayState();
}

class _AiLensOverlayState extends State<_AiLensOverlay> {
  Offset? _dragStart;
  Offset? _dragEnd;
  bool _selecting = false;
  MemoryImage? _screenshotImage;

  @override
  void initState() {
    super.initState();
    _prepareImage();
  }

  Future<void> _prepareImage() async {
    final cap = widget.capture;
    final rgba = cap.cropToRgba(0, 0, cap.width, cap.height);
    setState(() {
      _screenshotImage = MemoryImage(rgba);
    });
  }

  Rect get _selectionRect {
    if (_dragStart == null || _dragEnd == null) return Rect.zero;
    return Rect.fromPoints(_dragStart!, _dragEnd!);
  }

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _selecting = true;
      _dragStart = d.localPosition;
      _dragEnd = d.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _dragEnd = d.localPosition;
    });
  }

  void _onPanEnd(DragEndDetails _) async {
    _selecting = false;
    final rect = _selectionRect;
    if (rect.width < 10 || rect.height < 10) {
      Navigator.of(context).pop(null);
      return;
    }

    final scale = widget.capture.dpiScale;
    final px = (rect.left * scale).round();
    final py = (rect.top * scale).round();
    final pw = (rect.width * scale).round();
    final ph = (rect.height * scale).round();

    final png = await widget.capture.cropToPng(px, py, pw, ph);
    if (mounted) {
      Navigator.of(context).pop(png);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            // Dark overlay
            Container(
              width: size.width,
              height: size.height,
              color: Colors.black.withValues(alpha: 0.4),
            ),

            // Selection rectangle (clear region)
            if (_dragStart != null && _dragEnd != null)
              Positioned.fromRect(
                rect: _selectionRect,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),

            // Instructions
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Drag to select a region for AI analysis. Press Esc to cancel.',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),

            // Selection size indicator
            if (_dragStart != null && _dragEnd != null && _selectionRect.width > 20)
              Positioned(
                left: _selectionRect.right + 8,
                top: _selectionRect.bottom + 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_selectionRect.width.round()} × ${_selectionRect.height.round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
