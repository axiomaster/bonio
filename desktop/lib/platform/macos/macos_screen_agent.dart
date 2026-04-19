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
  double getDpiScale(int windowHandle) => 2.0; // Retina default
}
