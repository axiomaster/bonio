package ai.axiomaster.bonio.remote.ocr

import ai.axiomaster.bonio.util.AppLogger
import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume

/** One recognized text line with its bounding box (in the input bitmap's coordinates). */
data class OcrLine(val text: String, val left: Int, val top: Int, val right: Int, val bottom: Int)

/**
 * Local on-device OCR used as the screen.context degrade path when the
 * accessibility tree is unavailable (restricted settings, restricted windows).
 * See docs/design/arch/20260918-screen-ocr-degrade-arch.md.
 *
 * ML Kit Text Recognition v2 with the bundled Chinese model — no GMS required,
 * inference fully on-device (only the recognized text leaves the device later).
 */
class ScreenOcrRecognizer {

  private val recognizer by lazy {
    TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
  }

  /** Line-level OCR of the given bitmap; overall 5s timeout, never throws. */
  suspend fun recognize(bitmap: Bitmap): List<OcrLine> = withContext(Dispatchers.Default) {
    try {
      withTimeout(5_000L) {
        val text = processImage(bitmap)
        text.textBlocks.flatMap { block -> block.lines }.mapNotNull { line ->
          val value = line.text.trim()
          if (value.isEmpty()) return@mapNotNull null
          val box = line.boundingBox ?: return@mapNotNull null
          OcrLine(value, box.left, box.top, box.right, box.bottom)
        }
      }
    } catch (e: Throwable) {
      AppLogger.w("ScreenOcr", "ocr failed: ${e.message}")
      emptyList()
    }
  }

  private suspend fun processImage(bitmap: Bitmap) =
    suspendCancellableCoroutine { cont ->
      recognizer
        .process(InputImage.fromBitmap(bitmap, 0))
        .addOnSuccessListener { if (cont.isActive) cont.resume(it) }
        .addOnFailureListener { if (cont.isActive) cont.cancel(it) }
    }
}
