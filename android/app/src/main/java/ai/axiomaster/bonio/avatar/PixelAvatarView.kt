package ai.axiomaster.bonio.avatar

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.view.View
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.min

class KunAnimationSpec(val row: Int, val frameDurations: IntArray)

object KunAnimations {
    val idle = KunAnimationSpec(0, intArrayOf(280, 110, 110, 140, 140, 320))
    val runRight = KunAnimationSpec(1, intArrayOf(120, 120, 120, 120, 120, 120, 120, 220))
    val runLeft = KunAnimationSpec(2, intArrayOf(120, 120, 120, 120, 120, 120, 120, 220))
    val wave = KunAnimationSpec(3, intArrayOf(140, 140, 140, 280))
    val jump = KunAnimationSpec(4, intArrayOf(140, 140, 140, 140, 280))
    val failed = KunAnimationSpec(5, intArrayOf(140, 140, 140, 140, 140, 140, 140, 240))
    val waiting = KunAnimationSpec(6, intArrayOf(150, 150, 150, 150, 150, 260))
    val working = KunAnimationSpec(7, intArrayOf(120, 120, 120, 120, 120, 220))
    val thinking = KunAnimationSpec(8, intArrayOf(150, 150, 150, 150, 150, 280))
}

class PixelAvatarView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private const val TAG = "PixelAvatarView"
        private const val SPRITE_COLS = 8
        private const val SPRITE_ROWS = 9
        private const val FRAME_WIDTH = 192
        private const val FRAME_HEIGHT = 208

        private val bitmapCache = ConcurrentHashMap<String, Bitmap>()
    }

    private val pixelPaint = Paint().apply {
        isFilterBitmap = false // Nearest-neighbor scaling for crisp retro pixel art
        isDither = false
        isAntiAlias = false
    }

    private var currentBitmap: Bitmap? = null
    private var currentSkin: String = "cat"
    private var visualState: String = "idle"
    private var currentFrame: Int = 0
    private var celebrateWithJump: Boolean = false

    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false

    private val frameRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return
            val spec = getAnimationSpec()
            if (spec.frameDurations.isEmpty()) return
            currentFrame = (currentFrame + 1) % spec.frameDurations.size
            invalidate()
            val delay = spec.frameDurations.getOrNull(currentFrame) ?: 150
            handler.postDelayed(this, delay.toLong())
        }
    }

    init {
        loadSkin(currentSkin)
    }

    fun setSkin(skinId: String) {
        val normalized = skinId.lowercase().trim().ifEmpty { "cat" }
        if (normalized == currentSkin && currentBitmap != null) return
        currentSkin = normalized
        currentFrame = 0
        loadSkin(currentSkin)
        scheduleNextFrame()
        invalidate()
    }

    fun getSkin(): String = currentSkin

    fun setVisualState(state: String) {
        val normalized = normalizeState(state)
        if (normalized == visualState) return
        visualState = normalized
        if (normalized == "completed") {
            celebrateWithJump = !celebrateWithJump
        }
        currentFrame = 0
        scheduleNextFrame()
        invalidate()
    }

    fun getVisualState(): String = visualState

    private fun normalizeState(state: String?): String {
        return when (state?.lowercase()) {
            "working" -> "working"
            "thinking", "confused" -> "thinking"
            "waiting", "listening" -> "waiting"
            "failed" -> "failed"
            "completed", "happy" -> "completed"
            "interacting", "speaking", "recording" -> "wave"
            "dragleft" -> "dragLeft"
            "dragright" -> "dragRight"
            else -> "idle"
        }
    }

    private fun getAnimationSpec(): KunAnimationSpec {
        return when (visualState) {
            "working" -> KunAnimations.working
            "thinking" -> KunAnimations.thinking
            "waiting" -> KunAnimations.waiting
            "failed" -> KunAnimations.failed
            "completed" -> if (celebrateWithJump) KunAnimations.jump else KunAnimations.wave
            "wave" -> KunAnimations.wave
            "dragLeft" -> KunAnimations.runLeft
            "dragRight" -> KunAnimations.runRight
            else -> KunAnimations.idle
        }
    }

    private fun loadSkin(skinId: String) {
        val skinItem = CustomSkinManager.getSkinById(skinId)
        val fileName = "avatars/${skinItem.rawfileName}"
        val cached = bitmapCache[fileName]
        if (cached != null && !cached.isRecycled) {
            currentBitmap = cached
            return
        }

        try {
            context.assets.open(fileName).use { stream ->
                val opts = BitmapFactory.Options().apply {
                    inScaled = false // Load raw pixel data without DPI scaling
                }
                val bmp = BitmapFactory.decodeStream(stream, null, opts)
                if (bmp != null) {
                    bitmapCache[fileName] = bmp
                    currentBitmap = bmp
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load spritesheet for skin: $skinId from $fileName", e)
        }
    }

    private fun scheduleNextFrame() {
        handler.removeCallbacks(frameRunnable)
        if (!isRunning) return
        val spec = getAnimationSpec()
        val delay = spec.frameDurations.getOrNull(currentFrame) ?: 150
        handler.postDelayed(frameRunnable, delay.toLong())
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isRunning = true
        scheduleNextFrame()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        isRunning = false
        handler.removeCallbacks(frameRunnable)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val bmp = currentBitmap ?: return

        val spec = getAnimationSpec()
        val row = spec.row.coerceIn(0, SPRITE_ROWS - 1)
        val col = currentFrame.coerceIn(0, SPRITE_COLS - 1)

        val srcLeft = col * FRAME_WIDTH
        val srcTop = row * FRAME_HEIGHT
        val srcRight = srcLeft + FRAME_WIDTH
        val srcBottom = srcTop + FRAME_HEIGHT
        val srcRect = Rect(srcLeft, srcTop, srcRight, srcBottom)

        // Fit sprite into view while maintaining 192:208 aspect ratio
        val viewW = width
        val viewH = height
        if (viewW <= 0 || viewH <= 0) return

        val scale = min(viewW.toFloat() / FRAME_WIDTH, viewH.toFloat() / FRAME_HEIGHT)
        val drawW = (FRAME_WIDTH * scale).toInt()
        val drawH = (FRAME_HEIGHT * scale).toInt()
        val dstLeft = (viewW - drawW) / 2
        val dstTop = (viewH - drawH) / 2
        val dstRect = Rect(dstLeft, dstTop, dstLeft + drawW, dstTop + drawH)

        canvas.drawBitmap(bmp, srcRect, dstRect, pixelPaint)
    }
}

@androidx.compose.runtime.Composable
fun PixelAvatar(
    skinId: String,
    visualState: String = "idle",
    modifier: androidx.compose.ui.Modifier = androidx.compose.ui.Modifier
) {
    androidx.compose.ui.viewinterop.AndroidView(
        factory = { ctx ->
            PixelAvatarView(ctx).apply {
                setSkin(skinId)
                setVisualState(visualState)
            }
        },
        update = { view ->
            view.setSkin(skinId)
            view.setVisualState(visualState)
        },
        modifier = modifier
    )
}
