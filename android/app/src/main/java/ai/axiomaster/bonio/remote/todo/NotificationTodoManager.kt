package ai.axiomaster.bonio.remote.todo

import android.util.Log
import ai.axiomaster.bonio.remote.node.DeviceNotificationEntry
import java.util.Collections
import java.util.LinkedHashSet

/**
 * 监听通知并驱动待办提取与入库管理
 */
class NotificationTodoManager(
    private val todoRepository: TodoRepository
) {
    private val TAG = "NotificationTodoManager"
    // 滑动窗口去重缓存 (最大容量 100)
    private val recentHashes = Collections.synchronizedSet(LinkedHashSet<String>())
    private val MAX_HISTORY = 100

    fun onNotificationPosted(entry: DeviceNotificationEntry) {
        try {
            val key = entry.key
            val textContent = "${entry.title.orEmpty()}|${entry.text.orEmpty()}|${entry.subText.orEmpty()}"
            val hash = "$key:$textContent"

            synchronized(recentHashes) {
                if (recentHashes.contains(hash)) {
                    return
                }
                recentHashes.add(hash)
                if (recentHashes.size > MAX_HISTORY) {
                    val first = recentHashes.iterator().next()
                    recentHashes.remove(first)
                }
            }

            val todo = NotificationTodoExtractor.extract(
                packageName = entry.packageName,
                title = entry.title,
                text = entry.text,
                subText = entry.subText,
                category = entry.category,
                postTimeMs = entry.postTimeMs
            )

            if (todo != null) {
                Log.i(TAG, "Extracted todo from ${entry.packageName}: ${todo.task} (time=${todo.time}, loc=${todo.location}, person=${todo.person})")
                todoRepository.addTodo(todo)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing notification for todo", e)
        }
    }
}
