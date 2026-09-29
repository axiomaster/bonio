package ai.axiomaster.bonio.remote.node

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.util.Base64
import ai.axiomaster.bonio.NodeForegroundService
import ai.axiomaster.bonio.ScreenCaptureConsentActivity
import ai.axiomaster.bonio.ScreenCaptureRequester
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class ScreenCaptureManager(private val context: Context) {
  data class Payload(val payloadJson: String)

  @Volatile private var screenCaptureRequester: ScreenCaptureRequester? = null
  @Volatile private var latestCaptureResult: ScreenCaptureRequester.CaptureResult? = null

  fun attachScreenCaptureRequester(requester: ScreenCaptureRequester) {
    screenCaptureRequester = requester
  }

  fun setLatestCaptureResult(result: ScreenCaptureRequester.CaptureResult?) {
    latestCaptureResult = result
  }

  suspend fun capture(paramsJson: String?): Payload =
    withContext(Dispatchers.Default) {
      val params = parseJsonParamsObject(paramsJson)
      val quality = parseJsonInt(params, "quality")?.coerceIn(1, 100) ?: 80
      val maxWidth = parseJsonInt(params, "maxWidth")?.takeIf { it > 0 }

      val capture =
        latestCaptureResult ?: obtainConsent()
          ?: throw IllegalStateException(
            "SCREEN_PERMISSION_REQUIRED: grant Screen Recording permission",
          )
      latestCaptureResult = null

      // Android 14+ refuses MediaProjection unless a foreground service of type
      // mediaProjection is already running. Consent must be held first, so flip
      // the type on now and give the service a moment to apply it.
      runCatching { NodeForegroundService.updateMediaProjection(context, true) }
      delay(300)

      val mgr =
        context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
      val projection =
        mgr.getMediaProjection(capture.resultCode, capture.data)
          ?: throw IllegalStateException("UNAVAILABLE: screen capture unavailable")

      // Android 14+ requires a MediaProjection.Callback to be registered before
      // createVirtualDisplay, otherwise the system rejects the capture with
      // "Must register a callback before starting capture".
      val projectionCallback = object : MediaProjection.Callback() {}
      projection.registerCallback(
        projectionCallback,
        android.os.Handler(android.os.Looper.getMainLooper()),
      )

      val metrics = context.resources.displayMetrics
      val width = metrics.widthPixels
      val height = metrics.heightPixels
      val densityDpi = metrics.densityDpi

      val imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
      var virtualDisplay: VirtualDisplay? = null
      var acquired: Image? = null
      try {
        virtualDisplay =
          projection.createVirtualDisplay(
            "bonio-screen-capture",
            width,
            height,
            densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader.surface,
            null,
            null,
          )
        delay(500)
        acquired = imageReader.acquireLatestImage()
          ?: throw IllegalStateException("NO_FRAME: no frame captured")

        var bitmap = imageToBitmap(acquired)
        if (maxWidth != null && bitmap.width > maxWidth) {
          val ratio = maxWidth.toFloat() / bitmap.width
          val newH = (bitmap.height * ratio).toInt().coerceAtLeast(1)
          val scaled = Bitmap.createScaledBitmap(bitmap, maxWidth, newH, true)
          bitmap.recycle()
          bitmap = scaled
        }

        val outW = bitmap.width
        val outH = bitmap.height
        val out = ByteArrayOutputStream()
        try {
          if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)) {
            throw IllegalStateException("COMPRESS_FAILED: JPEG compression failed")
          }
        } finally {
          bitmap.recycle()
        }

        val bytes = out.toByteArray()
        val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        Payload(
          """{"format":"jpeg","base64":"$b64","width":$outW,"height":$outH}""",
        )
      } finally {
        try {
          acquired?.close()
        } catch (_: Throwable) {
        }
        try {
          virtualDisplay?.release()
        } catch (_: Throwable) {
        }
        try {
          imageReader.close()
        } catch (_: Throwable) {
        }
        try {
          projection.stop()
        } catch (_: Throwable) {
        }
        try {
          projection.unregisterCallback(projectionCallback)
        } catch (_: Throwable) {
        }
        // Drop the mediaProjection foreground-service type now that no
        // projection is active (Android 14 rejects a type without a projection).
        runCatching { NodeForegroundService.updateMediaProjection(context, false) }
      }
    }

  /**
   * Ask for MediaProjection consent. Prefers the main activity's registered
   * launcher; when that activity is not alive (the floating avatar can trigger
   * capture while the app is backgrounded) it falls back to a dedicated
   * transparent consent activity so the request is not lost.
   */
  private suspend fun obtainConsent(): ScreenCaptureRequester.CaptureResult? {
    val requester = screenCaptureRequester
    if (requester != null && requester.isAvailable()) {
      // A live launcher returning null means the user declined or let it time
      // out — do not re-prompt through the fallback path.
      return runCatching { requester.requestCapture(skipRationale = true) }.getOrNull()
    }
    return try {
      withTimeoutOrNull(CONSENT_TIMEOUT_MS) {
        ScreenCaptureConsentActivity.request(context).await()
      }
    } catch (_: Throwable) {
      null
    }
  }

  private fun imageToBitmap(image: Image): Bitmap {
    val planes = image.planes
    val plane = planes[0]
    val buffer = plane.buffer
    buffer.rewind()
    val pixelStride = plane.pixelStride
    val rowStride = plane.rowStride
    val w = image.width
    val imageHeight = image.height
    val bitmapWidth = rowStride / pixelStride
    val bitmap = Bitmap.createBitmap(bitmapWidth, imageHeight, Bitmap.Config.ARGB_8888)
    bitmap.copyPixelsFromBuffer(buffer)
    return if (bitmapWidth == w) {
      bitmap
    } else {
      val cropped = Bitmap.createBitmap(bitmap, 0, 0, w, imageHeight)
      bitmap.recycle()
      cropped
    }
  }

  companion object {
    private const val CONSENT_TIMEOUT_MS = 30_000L
  }
}
