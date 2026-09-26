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
    private fun spec(state: String) =
        SkinManifest.defaultAnim(state).let { KunAnimationSpec(it.row, it.frames) }
    val idle = spec("idle")
    val runRight = spec("run_right")
    val runLeft = spec("run_left")
    val wave = spec("wave")
    val jump = spec("jump")
    val failed = spec("failed")
    val waiting = spec("waiting")
    val working = spec("working")
    val thinking = spec("thinking")
}

class PixelAvatarView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private const val TAG = "PixelAvatarView"

        /** Per-row opaque-pixel bounds cache capacity — grid rows are capped by SkinManifest.MAX_GRID. */
        private const val MAX_ROWS = SkinManifest.MAX_GRID

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

    /** Grid + animation table of the active skin; defaults until a custom manifest says otherwise. */
    private var currentGrid: SkinGrid = SkinGrid.DEFAULT
    private var currentSpecs: Map<String, KunAnimationSpec> = emptyMap()

    /**
     * Per-row opaque-pixel bounds (union over all frames of the row), in
     * spritesheet pixel coordinates. Sprites carry large transparent margins
     * (the cat has huge headroom); drawing the tight box keeps the head pill
     * close to the visible cat and guarantees edge-docked peeks show real
     * pixels on both sides.
     */
    private val rowBounds = arrayOfNulls<Rect>(MAX_ROWS)

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

    /** Map a normalized visual state to its logical animation key. */
    private fun logicalAnimKey(state: String): String = when (state) {
        "working" -> "working"
        "thinking" -> "thinking"
        "waiting" -> "waiting"
        "failed" -> "failed"
        "completed" -> if (celebrateWithJump) "jump" else "wave"
        "wave" -> "wave"
        "dragLeft" -> "run_left"
        "dragRight" -> "run_right"
        else -> "idle"
    }

    private fun getAnimationSpec(): KunAnimationSpec {
        val key = logicalAnimKey(visualState)
        return currentSpecs[key]
            ?: KunAnimations.run { when (key) {
                "working" -> working
                "thinking" -> thinking
                "waiting" -> waiting
                "failed" -> failed
                "jump" -> jump
                "wave" -> wave
                "run_left" -> runLeft
                "run_right" -> runRight
                else -> idle
            } }
    }

    private fun specsFor(item: SkinItem): Map<String, KunAnimationSpec> {
        val manifest = item.manifest ?: return emptyMap()
        val specs = mutableMapOf<String, KunAnimationSpec>()
        for (state in SkinManifest.STATES) {
            val anim = manifest.resolvedAnim(state)
            specs[state] = KunAnimationSpec(anim.row, anim.frames)
        }
        return specs
    }

    private fun loadSkin(skinId: String) {
        val skinItem = CustomSkinManager.getSkinById(skinId, context)

        val cacheKey: String
        val bitmap: Bitmap?
        if (skinItem.sheetFile != null) {
            val file = java.io.File(skinItem.sheetFile)
            // mtime in the key invalidates the cache after an overwrite-import.
            cacheKey = "file:${skinItem.sheetFile}:${file.lastModified()}"
            val cached = bitmapCache[cacheKey]
            if (cached != null && !cached.isRecycled) {
                applySkinBitmap(skinItem, cached)
                return
            }
            val opts = BitmapFactory.Options().apply { inScaled = false }
            bitmap = BitmapFactory.decodeFile(skinItem.sheetFile, opts)
        } else {
            cacheKey = "asset:avatars/${skinItem.rawfileName}"
            val cached = bitmapCache[cacheKey]
            if (cached != null && !cached.isRecycled) {
                applySkinBitmap(skinItem, cached)
                return
            }
            bitmap = try {
                context.assets.open("avatars/${skinItem.rawfileName}").use { stream ->
                    val opts = BitmapFactory.Options().apply {
                        inScaled = false // Load raw pixel data without DPI scaling
                    }
                    BitmapFactory.decodeStream(stream, null, opts)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load spritesheet for skin: $skinId from ${skinItem.rawfileName}", e)
                null
            }
        }

        if (bitmap != null) {
            bitmapCache[cacheKey] = bitmap
            applySkinBitmap(skinItem, bitmap)
        }
    }

    private fun applySkinBitmap(item: SkinItem, bmp: Bitmap) {
        currentBitmap = bmp
        currentGrid = item.manifest?.grid ?: SkinGrid.DEFAULT
        currentSpecs = specsFor(item)
        currentFrame = 0
        java.util.Arrays.fill(rowBounds, null)
    }

    /** Union of opaque pixels across all frames of [row]; computed once, cached. */
    private fun rowContentBounds(bmp: Bitmap, row: Int): Rect? {
        val cached = rowBounds.getOrNull(row)
        if (cached != null) return cached
        val fw = currentGrid.frameWidth
        val fh = currentGrid.frameHeight
        val top = row * fh
        val bounds = Rect(-1, -1, -1, -1)
        val pixels = IntArray(fw * fh)
        for (col in 0 until currentGrid.cols) {
            bmp.getPixels(pixels, 0, fw, col * fw, top, fw, fh)
            for (py in 0 until fh) {
                val base = py * fw
                for (px in 0 until fw) {
                    if ((pixels[base + px] ushr 24) != 0) {
                        if (bounds.left < 0 || px < bounds.left) bounds.left = px
                        if (bounds.right < 0 || px > bounds.right) bounds.right = px
                        if (bounds.top < 0 || py < bounds.top) bounds.top = py
                        if (bounds.bottom < 0 || py > bounds.bottom) bounds.bottom = py
                    }
                }
            }
        }
        val result = if (bounds.left < 0) null else bounds
        if (row in rowBounds.indices) rowBounds[row] = result
        return result
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
        val row = spec.row.coerceIn(0, currentGrid.rows - 1)
        val col = currentFrame.coerceIn(0, (spec.frameDurations.size - 1).coerceAtLeast(0))
            .coerceAtMost(currentGrid.cols - 1)

        val viewW = width
        val viewH = height
        if (viewW <= 0 || viewH <= 0) return

        // Draw only the row's opaque content (tight crop): transparent sprite
        // margins are skipped so the character fills the view and the head
        // status pill sits right above the visible head.
        val content = rowContentBounds(bmp, row)
        val srcTop = row * currentGrid.frameHeight
        val srcRect = if (content != null) {
            Rect(col * currentGrid.frameWidth + content.left, srcTop + content.top,
                 col * currentGrid.frameWidth + content.right + 1, srcTop + content.bottom + 1)
        } else {
            Rect(col * currentGrid.frameWidth, srcTop,
                 col * currentGrid.frameWidth + currentGrid.frameWidth, srcTop + currentGrid.frameHeight)
        }

        val srcW = srcRect.width()
        val srcH = srcRect.height()
        val scale = min(viewW.toFloat() / srcW, viewH.toFloat() / srcH)
        val drawW = (srcW * scale).toInt().coerceAtLeast(1)
        val drawH = (srcH * scale).toInt().coerceAtLeast(1)
        // Anchor top-center: for wide characters (the lying cat) the head stays
        // close to the pill above; tall characters fill the height anyway.
        val dstLeft = (viewW - drawW) / 2
        val dstTop = 0
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
