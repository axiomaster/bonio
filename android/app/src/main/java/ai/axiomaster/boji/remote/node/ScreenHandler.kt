package ai.axiomaster.boji.remote.node

import ai.axiomaster.boji.remote.gateway.GatewaySession

class ScreenHandler(
  private val screenRecorder: ScreenRecordManager,
  private val screenCapturer: ScreenCaptureManager,
  private val setScreenRecordActive: (Boolean) -> Unit,
  private val invokeErrorFromThrowable: (Throwable) -> Pair<String, String>,
) {
  suspend fun handleScreenRecord(paramsJson: String?): GatewaySession.InvokeResult {
    setScreenRecordActive(true)
    try {
      val res =
        try {
          screenRecorder.record(paramsJson)
        } catch (err: Throwable) {
          val (code, message) = invokeErrorFromThrowable(err)
          return GatewaySession.InvokeResult.error(code = code, message = message)
        }
      return GatewaySession.InvokeResult.ok(res.payloadJson)
    } finally {
      setScreenRecordActive(false)
    }
  }

  suspend fun handleScreenCapture(paramsJson: String?): GatewaySession.InvokeResult {
    try {
      val res =
        try {
          screenCapturer.capture(paramsJson)
        } catch (err: Throwable) {
          val (code, message) = invokeErrorFromThrowable(err)
          return GatewaySession.InvokeResult.error(code = code, message = message)
        }
      return GatewaySession.InvokeResult.ok(res.payloadJson)
    } catch (e: Throwable) {
      return GatewaySession.InvokeResult.error(
        code = "CAPTURE_FAILED",
        message = e.message ?: "capture failed",
      )
    }
  }
}
