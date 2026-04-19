import '../gui_agent.dart';
import '../screen_capture_types.dart';
import '../win32_screen_capture.dart';

/// Windows [ScreenAgent] implementation backed by Win32 BitBlt / PrintWindow.
class Win32ScreenAgent implements ScreenAgent {
  @override
  ScreenCaptureResult? captureScreen() => Win32ScreenCapture.captureScreen();

  @override
  ScreenCaptureResult? captureWindow(int windowHandle) =>
      Win32ScreenCapture.captureWindow(windowHandle);

  @override
  double getDpiScale(int windowHandle) =>
      Win32ScreenCapture.getDpiScaleForWindow(windowHandle);
}
