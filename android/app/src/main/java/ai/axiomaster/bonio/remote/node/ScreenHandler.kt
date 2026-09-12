package ai.axiomaster.bonio.remote.node

import ai.axiomaster.bonio.remote.gateway.GatewaySession
import org.json.JSONArray
import org.json.JSONObject

class ScreenHandler(
  private val screenRecorder: ScreenRecordManager,
  private val screenCapturer: ScreenCaptureManager,
  private val setScreenRecordActive: (Boolean) -> Unit,
  private val invokeErrorFromThrowable: (Throwable) -> Pair<String, String>,
) {
  /**
   * screen.context: readable text snapshot of the current screen via the
   * accessibility tree. Returns flattened text (`content`, visual order,
   * deduped) plus the raw `nodes` array for input/send coordinate resolution.
   */
  suspend fun handleScreenContext(paramsJson: String?): GatewaySession.InvokeResult {
    var maxTextLength = 6000
    if (paramsJson != null) {
      try {
        val obj = JSONObject(paramsJson)
        maxTextLength = obj.optInt("maxTextLength", 6000)
      } catch (_: Throwable) {
        return GatewaySession.InvokeResult.error(
          code = "INVALID_REQUEST",
          message = "screen.context params must be valid JSON",
        )
      }
    }
    maxTextLength = maxTextLength.coerceIn(1, 12000)

    val a11y = BonioAccessibilityService.instance
      ?: return GatewaySession.InvokeResult.error(
        code = "ACCESSIBILITY_NOT_ENABLED",
        message = "ACCESSIBILITY_NOT_ENABLED: accessibility service is not enabled",
      )
    val dump = a11y.dumpActiveWindow(maxNodes = 250, maxTextLength = 240)
      ?: return GatewaySession.InvokeResult.error(
        code = "SCREEN_CONTEXT_FAILED",
        message = "SCREEN_CONTEXT_FAILED: no accessible window content",
      )

    return try {
      val obj = JSONObject(dump)
      val nodes = obj.optJSONArray("nodes") ?: JSONArray()

      data class Line(val top: Int, val left: Int, val text: String)
      val lines = mutableListOf<Line>()
      for (i in 0 until nodes.length()) {
        val n = nodes.optJSONObject(i) ?: continue
        val text = n.optString("text").trim()
        val desc = n.optString("description").trim()
        val value = text.ifEmpty { desc }
        if (value.isEmpty()) continue
        val bounds = n.optString("bounds").split(",").mapNotNull { it.toIntOrNull() }
        lines.add(
          Line(
            top = bounds.getOrElse(1) { 0 },
            left = bounds.getOrElse(0) { 0 },
            text = value,
          ),
        )
      }

      val content = StringBuilder()
      var last = ""
      var truncated = false
      for (line in lines.sortedWith(compareBy({ it.top }, { it.left }))) {
        if (line.text == last) continue
        last = line.text
        if (content.length + line.text.length + 1 > maxTextLength) {
          truncated = true
          break
        }
        if (content.isNotEmpty()) content.append('\n')
        content.append(line.text)
      }

      ai.axiomaster.bonio.util.AppLogger.i(
        "ScreenHandler",
        "screen.context: pkg=${obj.optString("package")} title=${obj.optString("window_title")} total_nodes=${nodes.length()} lines=${lines.size} content_len=${content.length}\n${content.take(300)}"
      )

      val payload = JSONObject()
        .put("source", "accessibility")
        .put("package", obj.optString("package"))
        .put("title", obj.optString("window_title"))
        .put("content", content.toString())
        .put("truncated", truncated)
        .put("nodes", nodes)
      GatewaySession.InvokeResult.ok(payload.toString())
    } catch (e: Throwable) {
      GatewaySession.InvokeResult.error(
        code = "SCREEN_CONTEXT_FAILED",
        message = e.message ?: "screen context failed",
      )
    }
  }

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
