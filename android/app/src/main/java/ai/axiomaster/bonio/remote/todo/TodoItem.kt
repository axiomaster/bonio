package ai.axiomaster.bonio.remote.todo

import org.json.JSONObject
import java.util.UUID

/**
 * 待办事项数据实体 (Todo Item extracted from notifications or created manually)
 */
data class TodoItem(
    val id: String = UUID.randomUUID().toString(),
    val task: String,              // 待办任务内容 (例: 招行信用卡还款 5,800.00元)
    val time: String? = null,      // 时间信息 (例: 09月25日、明天上午10点)
    val location: String? = null,  // 地点 (例: A座302会议室、虹桥火车站)
    val person: String? = null,    // 相关人/机构 (例: 张总、招商银行)
    val sourceApp: String? = null, // 来源应用 (例: 微信、短信、钉钉)
    val rawText: String? = null,   // 原始通知内容
    val sortTs: Long? = null,      // 排序时间戳（日历事件的开始时间；无则为 null，按加入时间排序）
    val createdAt: Long = System.currentTimeMillis(),
    val isCompleted: Boolean = false,
    val completedAt: Long? = null
) {
    fun toJsonObject(): JSONObject {
        return JSONObject().apply {
            put("id", id)
            put("task", task)
            put("time", time ?: JSONObject.NULL)
            put("location", location ?: JSONObject.NULL)
            put("person", person ?: JSONObject.NULL)
            put("sourceApp", sourceApp ?: JSONObject.NULL)
            put("rawText", rawText ?: JSONObject.NULL)
            put("sortTs", sortTs ?: JSONObject.NULL)
            put("createdAt", createdAt)
            put("isCompleted", isCompleted)
            put("completedAt", completedAt ?: JSONObject.NULL)
        }
    }

    companion object {
        fun fromJsonObject(obj: JSONObject): TodoItem {
            return TodoItem(
                id = obj.optString("id", UUID.randomUUID().toString()),
                task = obj.optString("task", ""),
                time = if (obj.isNull("time")) null else obj.optString("time").ifEmpty { null },
                location = if (obj.isNull("location")) null else obj.optString("location").ifEmpty { null },
                person = if (obj.isNull("person")) null else obj.optString("person").ifEmpty { null },
                sourceApp = if (obj.isNull("sourceApp")) null else obj.optString("sourceApp").ifEmpty { null },
                rawText = if (obj.isNull("rawText")) null else obj.optString("rawText").ifEmpty { null },
                sortTs = if (obj.isNull("sortTs")) null else obj.optLong("sortTs").takeIf { it > 0 },
                createdAt = obj.optLong("createdAt", System.currentTimeMillis()),
                isCompleted = obj.optBoolean("isCompleted", false),
                completedAt = if (obj.isNull("completedAt")) null else obj.optLong("completedAt")
            )
        }
    }
}
