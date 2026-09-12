package ai.axiomaster.bonio.avatar

data class SkinItem(
    val id: String,
    val name: String,
    val subtitle: String,
    val rawfileName: String,
    val victoryQuote: String,
    val isBuiltin: Boolean = true,
)

object CustomSkinManager {
    val allSkins = listOf(
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

    fun getSkinById(id: String): SkinItem {
        return allSkins.find { it.id.equals(id, ignoreCase = true) } ?: allSkins.first()
    }

    fun getAgentBubble(state: String, skin: String = "cat"): String? {
        val s = skin.lowercase()
        return when (state) {
            "working" -> "努力工作中…"
            "thinking" -> if (s == "messi") "战术思考中…" else "思考中…"
            "waiting", "listening" -> "在等你回复哦~"
            "failed" -> if (s == "mario") "Mamma Mia! 出错了 (._.)" else "呜…出错了 (._.)"
            "idle" -> "休息中~ 有事叫我"
            "completed" -> when (s) {
                "mario" -> "Here we go! 任务完成！"
                "messi" -> "Vamos! 胜利完成！"
                "kun" -> "完成啦！你干嘛~哎哟"
                else -> "喵~ 任务完成啦！"
            }
            else -> null
        }
    }
}
