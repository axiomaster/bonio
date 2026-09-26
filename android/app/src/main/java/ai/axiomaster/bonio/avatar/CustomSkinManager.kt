package ai.axiomaster.bonio.avatar

import android.content.Context
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class SkinItem(
    val id: String,
    val name: String,
    val subtitle: String,
    val rawfileName: String,
    val victoryQuote: String,
    val isBuiltin: Boolean = true,
    /** Absolute spritesheet path for imported skins; null for built-ins (loaded from assets). */
    val sheetFile: String? = null,
    /** Parsed manifest for imported skins; null for built-ins. */
    val manifest: SkinManifest? = null,
)

/**
 * Registry of built-in skins (bundled in assets/avatars) plus user-imported skins
 * installed under filesDir/skins/<id>/ (see SkinImporter).
 */
object CustomSkinManager {
    private const val TAG = "CustomSkinManager"

    val builtinSkins = listOf(
        SkinItem(
            id = "cat",
            name = "Cat (像素小猫)",
            subtitle = "经典慵懒肥橘猫 趴地像素",
            rawfileName = "cat-spritesheet.webp",
            victoryQuote = "喵~ 任务搞定啦！"
        ),
        SkinItem(
            id = "kun",
            name = "Kun (小黄鸡)",
            subtitle = "经典高密度像素鸡伴侣",
            rawfileName = "kun-spritesheet.webp",
            victoryQuote = "完成啦！你干嘛~哎哟"
        ),
        SkinItem(
            id = "mario",
            name = "Mario (马里奥)",
            subtitle = "任天堂经典水管工 HD像素",
            rawfileName = "mario-spritesheet.webp",
            victoryQuote = "Here we go! 任务搞定！"
        ),
        SkinItem(
            id = "messi",
            name = "Messi (球王梅西)",
            subtitle = "阿根廷10号队长 HD像素",
            rawfileName = "messi-spritesheet.webp",
            victoryQuote = "Vamos! 胜利完成！"
        )
    )

    private val _customSkins = MutableStateFlow<List<SkinItem>>(emptyList())
    val customSkins: StateFlow<List<SkinItem>> = _customSkins.asStateFlow()

    /** Full gallery order: built-ins first, imported skins after. */
    fun allSkins(context: Context? = null): List<SkinItem> {
        if (context != null && _customSkins.value.isEmpty()) refresh(context)
        return builtinSkins + _customSkins.value
    }

    fun isCustomSkin(id: String): Boolean =
        _customSkins.value.any { it.id.equals(id, ignoreCase = true) }

    fun getSkinById(id: String, context: Context? = null): SkinItem {
        builtinSkins.firstOrNull { it.id.equals(id, ignoreCase = true) }?.let { return it }
        _customSkins.value.firstOrNull { it.id.equals(id, ignoreCase = true) }?.let { return it }
        if (context != null) {
            // Disk fallback: registry may be cold (e.g. the float window service
            // resolved before the view model refreshed it).
            refresh(context)
            _customSkins.value.firstOrNull { it.id.equals(id, ignoreCase = true) }?.let { return it }
        }
        return builtinSkins.first()
    }

    /** Rescan the skins directory (filesDir/skins/<id>/manifest.json) into the registry. */
    fun refresh(context: Context) {
        _customSkins.value = loadInstalled(context)
    }

    private fun skinsRoot(context: Context): File = File(context.filesDir, "skins")

    private fun loadInstalled(context: Context): List<SkinItem> {
        val root = skinsRoot(context)
        if (!root.isDirectory) return emptyList()
        val items = mutableListOf<SkinItem>()
        val dirs = root.listFiles { f -> f.isDirectory } ?: return emptyList()
        for (dir in dirs.sortedBy { it.name }) {
            try {
                val manifestFile = File(dir, "manifest.json")
                if (!manifestFile.isFile) continue
                val manifest = SkinManifest.parse(manifestFile.readText())
                if (manifest.validate() != null) continue
                val sheet = File(dir, manifest.spritesheet)
                if (!sheet.isFile) continue
                items.add(
                    SkinItem(
                        id = manifest.id,
                        name = manifest.name,
                        subtitle = manifest.subtitle.ifEmpty { manifest.author ?: "自定义皮肤" },
                        rawfileName = manifest.spritesheet,
                        victoryQuote = manifest.victoryQuote ?: "任务搞定啦！",
                        isBuiltin = false,
                        sheetFile = sheet.absolutePath,
                        manifest = manifest,
                    )
                )
            } catch (e: Exception) {
                Log.w(TAG, "skip broken installed skin ${dir.name}", e)
            }
        }
        return items
    }

    /** Serialize one installed skin's manifest (used by SkinImporter for atomic install). */
    fun writeManifest(dir: File, manifest: SkinManifest) {
        val obj = JSONObject()
        obj.put("format_version", manifest.formatVersion)
        obj.put("id", manifest.id)
        obj.put("name", manifest.name)
        obj.put("subtitle", manifest.subtitle)
        if (manifest.version != null) obj.put("version", manifest.version)
        if (manifest.author != null) obj.put("author", manifest.author)
        if (manifest.victoryQuote != null) obj.put("victory_quote", manifest.victoryQuote)
        obj.put("spritesheet", manifest.spritesheet)
        if (manifest.preview != null) obj.put("preview", manifest.preview)
        obj.put("grid", JSONObject().apply {
            put("cols", manifest.grid.cols)
            put("rows", manifest.grid.rows)
            put("frame_width", manifest.grid.frameWidth)
            put("frame_height", manifest.grid.frameHeight)
        })
        if (manifest.animations.isNotEmpty()) {
            obj.put("animations", JSONObject().apply {
                for ((state, anim) in manifest.animations) {
                    put(state, JSONObject().apply {
                        put("row", anim.row)
                        put("count", anim.count)
                        if (anim.frames.isNotEmpty()) put("frames", JSONArray(anim.frames.toList()))
                    })
                }
            })
        }
        File(dir, "manifest.json").writeText(obj.toString())
    }

    fun getAgentBubble(state: String, skin: String = "cat"): String? {
        val s = skin.lowercase()
        return when (state) {
            "working" -> "努力工作中…"
            "thinking" -> if (s == "messi") "战术思考中…" else "思考中…"
            "waiting", "listening" -> "在等你回复哦~"
            "speaking" -> "说话中…"
            "failed" -> if (s == "mario") "Mamma Mia! 出错了 (._.)" else "呜…出错了 (._.)"
            "idle" -> "休息中~ 有事叫我"
            "bored" -> "好无聊呀~"
            "sleeping" -> "呼噜噜…睡觉中"
            "angry" -> "气呼呼 ˋ^ˊ"
            "watching" -> "注视中…"
            "completed" -> when (s) {
                "mario" -> "Here we go! 任务完成！"
                "messi" -> "Vamos! 胜利完成！"
                "kun" -> "完成啦！你干嘛~哎哟"
                else -> "喵~ 任务完成啦！"
            }
            else -> "喵~"
        }
    }
}
