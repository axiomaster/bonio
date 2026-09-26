package ai.axiomaster.bonio.avatar

import org.json.JSONArray
import org.json.JSONObject

/** Sprite sheet grid geometry (see docs/design/prd/skin-import-prd-20260926.md §3.2). */
data class SkinGrid(
  val cols: Int,
  val rows: Int,
  val frameWidth: Int,
  val frameHeight: Int,
) {
  val sheetWidth: Int get() = cols * frameWidth
  val sheetHeight: Int get() = rows * frameHeight
  val pixelCount: Long get() = sheetWidth.toLong() * sheetHeight

  companion object {
    val DEFAULT = SkinGrid(cols = 8, rows = 9, frameWidth = 192, frameHeight = 208)
  }
}

/** One resolved animation row: [row] of the sheet, [count] frames, per-frame durations in ms. */
data class SkinAnim(val row: Int, val count: Int, val frames: IntArray) {
  override fun equals(other: Any?): Boolean =
    other is SkinAnim && other.row == row && other.count == count && other.frames.contentEquals(frames)
  override fun hashCode(): Int = row * 31 + count * 1013 + frames.contentHashCode()
}

/**
 * Parsed skin manifest (format_version 1). Pure JVM (org.json only) so it is unit-testable.
 */
class SkinManifest(
  val formatVersion: Int,
  val id: String,
  val name: String,
  val subtitle: String,
  val version: String?,
  val author: String?,
  val victoryQuote: String?,
  val spritesheet: String,
  val preview: String?,
  val grid: SkinGrid,
  val animations: Map<String, SkinAnim>,
) {

  /** Returns null when the manifest is valid, otherwise a stable error code. */
  fun validate(): String? {
    if (formatVersion != FORMAT_VERSION) return ERR_BAD_MANIFEST
    if (!ID_REGEX.matches(id)) return ERR_BAD_MANIFEST
    if (id in RESERVED_IDS) return ERR_RESERVED_ID
    if (name.isEmpty() || name.length > MAX_NAME) return ERR_BAD_MANIFEST
    if (subtitle.length > MAX_SUBTITLE) return ERR_BAD_MANIFEST
    if ((version?.length ?: 0) > MAX_VERSION) return ERR_BAD_MANIFEST
    if ((author?.length ?: 0) > MAX_AUTHOR) return ERR_BAD_MANIFEST
    if (!SHEET_REGEX.matches(spritesheet)) return ERR_BAD_MANIFEST
    if (preview != null && !PREVIEW_REGEX.matches(preview)) return ERR_BAD_MANIFEST

    if (grid.cols !in 1..MAX_GRID || grid.rows !in 1..MAX_GRID) return ERR_BAD_MANIFEST
    if (grid.frameWidth !in MIN_FRAME..MAX_FRAME || grid.frameHeight !in MIN_FRAME..MAX_FRAME) return ERR_BAD_MANIFEST
    if (grid.sheetWidth > MAX_SHEET_SIDE || grid.sheetHeight > MAX_SHEET_SIDE) return ERR_BAD_MANIFEST
    if (grid.pixelCount > MAX_SHEET_PIXELS) return ERR_BAD_MANIFEST

    for ((state, anim) in animations) {
      if (state !in STATES) return ERR_BAD_MANIFEST
      if (anim.row !in 0 until grid.rows) return ERR_BAD_MANIFEST
      if (anim.count !in 1..grid.cols) return ERR_BAD_MANIFEST
      if (anim.frames.size != anim.count) return ERR_BAD_MANIFEST
      if (anim.frames.any { it < MIN_FRAME_MS || it > MAX_FRAME_MS }) return ERR_BAD_MANIFEST
    }
    return null
  }

  /**
   * Resolve the animation for a logical state: manifest override first, then the
   * built-in default table (which matches the bundled skins' row layout).
   */
  fun resolvedAnim(state: String): SkinAnim {
    animations[state]?.let { return it }
    val default = defaultAnim(state)
    return if (grid == SkinGrid.DEFAULT) default
    else default.copy(row = default.row.coerceAtMost(grid.rows - 1))
  }

  companion object {
    const val FORMAT_VERSION = 1
    const val ERR_BAD_MANIFEST = "ERR_BAD_MANIFEST"
    const val ERR_RESERVED_ID = "ERR_RESERVED_ID"

    const val MAX_NAME = 24
    const val MAX_SUBTITLE = 32
    const val MAX_VERSION = 16
    const val MAX_AUTHOR = 24
    const val MAX_GRID = 16
    const val MIN_FRAME = 32
    const val MAX_FRAME = 512
    const val MAX_SHEET_SIDE = 2048
    const val MAX_SHEET_PIXELS = 4_000_000L
    const val MIN_FRAME_MS = 1
    const val MAX_FRAME_MS = 10_000

    val ID_REGEX = Regex("^[a-z0-9][a-z0-9_-]{1,31}$")
    val SHEET_REGEX = Regex("spritesheet\\.(webp|png)")
    val PREVIEW_REGEX = Regex("preview\\.(png|jpg|jpeg|webp)")

    /** Logical animation states, in built-in default row order. */
    val STATES = listOf(
      "idle", "run_right", "run_left", "wave", "jump",
      "failed", "waiting", "working", "thinking"
    )

    /** Built-in default row/duration table — mirrors the bundled sprite sheets. */
    private val DEFAULT_ANIMS: Map<String, SkinAnim> = mapOf(
      "idle" to SkinAnim(0, 6, intArrayOf(280, 110, 110, 140, 140, 320)),
      "run_right" to SkinAnim(1, 8, intArrayOf(120, 120, 120, 120, 120, 120, 120, 220)),
      "run_left" to SkinAnim(2, 8, intArrayOf(120, 120, 120, 120, 120, 120, 120, 220)),
      "wave" to SkinAnim(3, 4, intArrayOf(140, 140, 140, 280)),
      "jump" to SkinAnim(4, 5, intArrayOf(140, 140, 140, 140, 280)),
      "failed" to SkinAnim(5, 8, intArrayOf(140, 140, 140, 140, 140, 140, 140, 240)),
      "waiting" to SkinAnim(6, 6, intArrayOf(150, 150, 150, 150, 150, 260)),
      "working" to SkinAnim(7, 6, intArrayOf(120, 120, 120, 120, 120, 220)),
      "thinking" to SkinAnim(8, 6, intArrayOf(150, 150, 150, 150, 150, 280)),
    )

    fun defaultAnim(state: String): SkinAnim =
      DEFAULT_ANIMS[state] ?: DEFAULT_ANIMS.getValue("idle")

    fun isReservedId(id: String): Boolean = id in RESERVED_IDS

    val RESERVED_IDS: Set<String> = setOf("cat", "kun", "mario", "messi")

    /** Parse a manifest JSON body; throws [SkinManifestException] on structural errors. */
    fun parse(text: String): SkinManifest {
      try {
        val obj = JSONObject(text)
        val gridObj = obj.optJSONObject("grid")
        val grid = if (gridObj == null) SkinGrid.DEFAULT else SkinGrid(
          cols = gridObj.getInt("cols"),
          rows = gridObj.getInt("rows"),
          frameWidth = gridObj.getInt("frame_width"),
          frameHeight = gridObj.getInt("frame_height"),
        )
        val animsObj = obj.optJSONObject("animations")
        val anims = mutableMapOf<String, SkinAnim>()
        if (animsObj != null) {
          for (state in animsObj.keys()) {
            val a = animsObj.getJSONObject(state)
            val framesArr: JSONArray? = a.optJSONArray("frames")
            val count = a.optInt("count", framesArr?.length() ?: grid.cols)
            // Omitted "frames" = uniform 150ms per frame.
            val frames = framesArr?.let { arr -> IntArray(arr.length()) { arr.getInt(it) } }
              ?: IntArray(count) { 150 }
            anims[state] = SkinAnim(row = a.getInt("row"), count = count, frames = frames)
          }
        }
        return SkinManifest(
          formatVersion = obj.getInt("format_version"),
          id = obj.getString("id"),
          name = obj.getString("name"),
          subtitle = obj.optString("subtitle", ""),
          version = obj.optString("version", "").ifEmpty { null },
          author = obj.optString("author", "").ifEmpty { null },
          victoryQuote = obj.optString("victory_quote", "").ifEmpty { null },
          spritesheet = obj.getString("spritesheet"),
          preview = obj.optString("preview", "").ifEmpty { null },
          grid = grid,
          animations = anims,
        )
      } catch (e: Exception) {
        throw SkinManifestException(ERR_BAD_MANIFEST, e.message ?: "malformed manifest")
      }
    }
  }
}

class SkinManifestException(val code: String, message: String) : Exception(message)
