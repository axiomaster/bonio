package ai.axiomaster.bonio.remote.node

import ai.axiomaster.bonio.remote.gateway.GatewaySession
import ai.axiomaster.bonio.remote.ocr.ScreenOcrRecognizer
import ai.axiomaster.bonio.util.AppLogger
import android.graphics.Bitmap
import org.json.JSONArray
import org.json.JSONObject

class ScreenHandler(
  private val screenRecorder: ScreenRecordManager,
  private val screenCapturer: ScreenCaptureManager,
  private val setScreenRecordActive: (Boolean) -> Unit,
  private val invokeErrorFromThrowable: (Throwable) -> Pair<String, String>,
) {
  private val screenOcr = ScreenOcrRecognizer()

  private data class Line(val top: Int, val left: Int, val text: String)

  /**
   * screen.context: readable text snapshot of the current screen. Prefers the
   * accessibility tree; when it yields no text (restricted settings, restricted
   * windows), degrades to on-device OCR over a silent screenshot and returns
   * the same payload shape with source="ocr".
   * See docs/design/arch/20260918-screen-ocr-degrade-arch.md.
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
    var providedScreenshotB64: String? = null
    if (paramsJson != null) {
      try {
        providedScreenshotB64 = JSONObject(paramsJson).optString("screenshotBase64").ifEmpty { null }
      } catch (_: Throwable) {}
    }
    val dump = a11y.dumpActiveWindow(maxNodes = 250, maxTextLength = 240)
      ?: return GatewaySession.InvokeResult.error(
        code = "SCREEN_CONTEXT_FAILED",
        message = "SCREEN_CONTEXT_FAILED: no accessible window content",
      )

    return try {
      val obj = JSONObject(dump)
      var nodes = obj.optJSONArray("nodes") ?: JSONArray()
      var source = "accessibility"

      fun linesFromNodes(arr: JSONArray): List<Line> = buildList {
        for (i in 0 until arr.length()) {
          val n = arr.optJSONObject(i) ?: continue
          val text = n.optString("text").trim()
          val desc = n.optString("description").trim()
          val value = text.ifEmpty { desc }
          if (value.isEmpty()) continue
          val bounds = n.optString("bounds").split(",").mapNotNull { it.toIntOrNull() }
          add(
            Line(
              top = bounds.getOrElse(1) { 0 },
              left = bounds.getOrElse(0) { 0 },
              text = value,
            ),
          )
        }
      }

      var lines = linesFromNodes(nodes)
      if (lines.isEmpty()) {
        // ── OCR 降级：无障碍树无文本（受限设置/受限窗口）──
        try {
          val ocrStarted = android.os.SystemClock.elapsedRealtime()
          // Full-screen size for mapping OCR boxes back to a11y coordinates.
          val screenW = a11y.resources.displayMetrics.widthPixels
          val screenH = a11y.resources.displayMetrics.heightPixels
          val screenLongest = maxOf(screenW, screenH)
          val decodeProvided: () -> Bitmap? = {
            providedScreenshotB64?.let { b64 ->
              try {
                val bytes = android.util.Base64.decode(b64, android.util.Base64.DEFAULT)
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
              } catch (_: Throwable) {
                null
              }
            }
          }
          var input = decodeProvided()
          var sourceWasProvided = input != null
          if (input == null) {
            // Take our own screenshot. takeScreenshot has a minimum interval
            // (a parallel capture may just have completed) — back off between
            // attempts instead of failing fast.
            val waits = longArrayOf(0, 400, 1_200)
            for (wait in waits) {
              if (wait > 0) kotlinx.coroutines.delay(wait)
              input = a11y.takeScreenshotBitmap(maxEdge = OCR_MAX_EDGE)
              if (input != null) break
            }
            sourceWasProvided = false
          }
          if (input == null) {
            AppLogger.w("ScreenHandler", "ocr degrade: screenshot unavailable after retries")
          } else {
            val inputLongest = maxOf(input.width, input.height)
            val inv = if (sourceWasProvided && screenLongest > 0 && inputLongest > 0) {
              screenLongest.toFloat() / inputLongest
            } else {
              1f
            }
            val ocrLines = screenOcr.recognize(input)
            if (!sourceWasProvided) input.recycle()
            AppLogger.i(
              "ScreenHandler",
              "ocr degrade: took ${android.os.SystemClock.elapsedRealtime() - ocrStarted}ms lines=${ocrLines.size} provided=$sourceWasProvided",
            )
            if (ocrLines.isNotEmpty()) {
              val ocrNodes = JSONArray()
              val ocrLineList = mutableListOf<Line>()
              for (l in ocrLines) {
                val left = (l.left * inv).toInt()
                val top = (l.top * inv).toInt()
                val right = (l.right * inv).toInt()
                val bottom = (l.bottom * inv).toInt()
                ocrNodes.put(
                  JSONObject().put("text", l.text).put("bounds", "$left,$top,$right,$bottom"),
                )
                ocrLineList.add(Line(top = top, left = left, text = l.text))
              }
              nodes = ocrNodes
              lines = ocrLineList
              source = "ocr"
            }
          }
        } catch (e: Throwable) {
          AppLogger.w("ScreenHandler", "ocr degrade failed: ${e.message}")
        }
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

      AppLogger.i(
        "ScreenHandler",
        "screen.context source=$source pkg=${obj.optString("package")} title=${obj.optString("window_title")} total_nodes=${nodes.length()} lines=${lines.size} content_len=${content.length}\n${content.take(300)}",
      )

      val payload = JSONObject()
        .put("source", source)
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

  companion object {
    private const val OCR_MAX_EDGE = 1080
  }
}
