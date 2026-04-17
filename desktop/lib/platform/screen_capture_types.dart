import 'dart:typed_data';
import 'dart:ui' as ui;

/// Shared result type returned by all screen capture implementations.
class ScreenCaptureResult {
  final int width;
  final int height;
  final Uint8List bgraPixels;
  final double dpiScale;

  ScreenCaptureResult({
    required this.width,
    required this.height,
    required this.bgraPixels,
    required this.dpiScale,
  });

  /// Convert the entire capture from BGRA to RGBA.
  Uint8List toRgba() {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      final srcIdx = i * 4;
      final dstIdx = i * 4;
      rgba[dstIdx + 0] = bgraPixels[srcIdx + 2]; // R
      rgba[dstIdx + 1] = bgraPixels[srcIdx + 1]; // G
      rgba[dstIdx + 2] = bgraPixels[srcIdx + 0]; // B
      rgba[dstIdx + 3] = 255; // A
    }
    return rgba;
  }

  /// Encode the full capture as PNG bytes.
  Future<Uint8List?> toPng() async {
    if (width <= 0 || height <= 0) return null;
    final rgba = toRgba();
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    codec.dispose();
    descriptor.dispose();
    return byteData?.buffer.asUint8List();
  }

  /// Crop to a region (in physical pixels) and convert BGRA to RGBA.
  Uint8List cropToRgba(int x, int y, int w, int h) {
    final cx = x.clamp(0, width);
    final cy = y.clamp(0, height);
    final cw = w.clamp(0, width - cx);
    final ch = h.clamp(0, height - cy);

    final rgba = Uint8List(cw * ch * 4);
    for (var row = 0; row < ch; row++) {
      for (var col = 0; col < cw; col++) {
        final srcIdx = ((cy + row) * width + (cx + col)) * 4;
        final dstIdx = (row * cw + col) * 4;
        rgba[dstIdx + 0] = bgraPixels[srcIdx + 2]; // R
        rgba[dstIdx + 1] = bgraPixels[srcIdx + 1]; // G
        rgba[dstIdx + 2] = bgraPixels[srcIdx + 0]; // B
        rgba[dstIdx + 3] = 255; // A
      }
    }
    return rgba;
  }

  /// Encode a cropped region as PNG bytes.
  Future<Uint8List?> cropToPng(int x, int y, int w, int h) async {
    final cw = w.clamp(0, width - x.clamp(0, width));
    final ch = h.clamp(0, height - y.clamp(0, height));
    if (cw <= 0 || ch <= 0) return null;

    final rgba = cropToRgba(x, y, cw, ch);

    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: cw,
      height: ch,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    codec.dispose();
    descriptor.dispose();

    return byteData?.buffer.asUint8List();
  }
}

/// Information about a captured window.
class WindowInfo {
  final int windowID;
  final String ownerName;
  final String? windowName;
  final Map<String, int>? bounds;

  WindowInfo({
    required this.windowID,
    required this.ownerName,
    this.windowName,
    this.bounds,
  });
}
