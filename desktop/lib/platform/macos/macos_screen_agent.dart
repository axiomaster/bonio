import '../gui_agent.dart';
import '../screen_capture_types.dart';

/// macOS [ScreenAgent] stub.
///
/// Phase 2 will implement via CGWindowListCreateImage / ScreenCaptureKit.
class MacScreenAgent implements ScreenAgent {
  @override
  ScreenCaptureResult? captureScreen() => null;

  @override
  ScreenCaptureResult? captureWindow(int windowHandle) => null;

  @override
  // CG window bounds are in logical points, so no DPI scaling needed.
  @override
  double getDpiScale(int windowHandle) => 1.0;
}
