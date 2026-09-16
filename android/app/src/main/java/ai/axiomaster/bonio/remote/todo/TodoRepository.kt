package ai.axiomaster.bonio.remote.todo

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Result of a calendar → todo sync. */
data class CalendarSyncResult(
    val added: Int,
    val totalEvents: Int,
    val permissionDenied: Boolean = false,
    val error: String? = null,
)

/**
 * 待办事项本地存储与响应式仓库
 * 持久化于 context.filesDir/todos.json
 */
class TodoRepository(
    private val context: Context,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {
    private val TAG = "TodoRepository"
    private val mutex = Mutex()
    private val todoFile = File(context.filesDir, "todos.json")

    private val _todos = MutableStateFlow<List<TodoItem>>(emptyList())
    val todos: StateFlow<List<TodoItem>> = _todos.asStateFlow()

    init {
        loadFromDisk()
    }

    private fun loadFromDisk() {
        try {
            if (todoFile.exists()) {
                val jsonStr = todoFile.readText()
                if (jsonStr.isNotBlank()) {
                    val jsonArray = JSONArray(jsonStr)
                    val items = mutableListOf<TodoItem>()
                    for (i in 0 until jsonArray.length()) {
                        val obj = jsonArray.getJSONObject(i)
                        items.add(TodoItem.fromJsonObject(obj))
                    }
                    _todos.value = sortTodos(items)
                    Log.i(TAG, "Loaded ${_todos.value.size} todos from disk")
                    return
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load todos from disk", e)
        }
        _todos.value = emptyList()
    }

    private suspend fun saveToDisk(items: List<TodoItem>) {
        try {
            val jsonArray = JSONArray()
            items.forEach { jsonArray.put(it.toJsonObject()) }
            todoFile.writeText(jsonArray.toString(2))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save todos to disk", e)
        }
    }

    /** 统一排序：未完成在前；有时间戳的按时间从近到远；无时间戳的按加入时间倒序。 */
    private fun sortTodos(items: List<TodoItem>): List<TodoItem> = items.sortedWith(
        compareBy<TodoItem> { it.isCompleted }
            .thenBy { it.sortTs ?: Long.MAX_VALUE }
            .thenByDescending { it.createdAt }
    )

    fun addTodo(item: TodoItem) {
        scope.launch {
            mutex.withLock {
                // 防重检查：如果已存在相同任务且未完成，可忽略或更新
                val existing = _todos.value.find {
                    it.task == item.task && it.time == item.time && !it.isCompleted
                }
                if (existing != null) {
                    Log.d(TAG, "Duplicate todo detected, skipping: ${item.task}")
                    return@withLock
                }

                val updated = listOf(item) + _todos.value
                val sorted = sortTodos(updated)
                _todos.value = sorted
                saveToDisk(sorted)
                Log.i(TAG, "Added todo: ${item.task}, id=${item.id}")
            }
        }
    }

    fun toggleTodo(id: String) {
        scope.launch {
            mutex.withLock {
                val updated = _todos.value.map { item ->
                    if (item.id == id) {
                        val nextCompleted = !item.isCompleted
                        item.copy(
                            isCompleted = nextCompleted,
                            completedAt = if (nextCompleted) System.currentTimeMillis() else null
                        )
                    } else {
                        item
                    }
                }
                val sorted = sortTodos(updated)
                _todos.value = sorted
                saveToDisk(sorted)
                Log.i(TAG, "Toggled todo id=$id")
            }
        }
    }

    fun deleteTodo(id: String) {
        scope.launch {
            mutex.withLock {
                val updated = _todos.value.filter { it.id != id }
                _todos.value = updated
                saveToDisk(updated)
                Log.i(TAG, "Deleted todo id=$id")
            }
        }
    }

    fun clearCompleted() {
        scope.launch {
            mutex.withLock {
                val updated = _todos.value.filter { !it.isCompleted }
                _todos.value = updated
                saveToDisk(updated)
                Log.i(TAG, "Cleared all completed todos")
            }
        }
    }

    /**
     * 从系统日历同步未来 [days] 天的日程为待办事项。
     * 使用确定性 id（cal-<eventId>-<begin>）：重复同步不会产生重复项，
     * 日历中已删除/移出窗口的日程对应的历史待办会被清理（已完成的保留）。
     */
    suspend fun syncFromCalendar(days: Int = 7): CalendarSyncResult = withContext(Dispatchers.IO) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return@withContext CalendarSyncResult(added = 0, totalEvents = 0, permissionDenied = true)
        }

        val now = System.currentTimeMillis()
        val windowFrom = now
        val windowTo = now + days * DAY_MS
        val events = mutableListOf<TodoItem>()
        try {
            val projection = arrayOf(
                CalendarContract.Instances.EVENT_ID,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.EVENT_LOCATION,
            )
            // 时间范围必须编码进 URI（instances/when/<begin>/<end>）——部分厂商
            // 提供者（如华为）对不带范围的 Instances URI 会返回空结果。
            val uri = CalendarContract.Instances.CONTENT_URI
                .buildUpon()
                .appendPath(windowFrom.toString())
                .appendPath(windowTo.toString())
                .build()
            context.contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${CalendarContract.Instances.BEGIN} ASC",
            )?.use { c ->
                val iEventId = c.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID)
                val iTitle = c.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
                val iBegin = c.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
                val iAllDay = c.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY)
                val iLoc = c.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_LOCATION)
                while (c.moveToNext()) {
                    val eventId = c.getLong(iEventId)
                    val begin = c.getLong(iBegin)
                    val allDay = c.getInt(iAllDay) != 0
                    val title = c.getString(iTitle)?.trim()?.ifEmpty { null } ?: "未命名日程"
                    val location = c.getString(iLoc)?.trim()?.ifEmpty { null }
                    events.add(
                        TodoItem(
                            id = "cal-$eventId-$begin",
                            task = title,
                            time = formatEventTime(begin, allDay),
                            location = location,
                            sourceApp = "日历",
                            sortTs = begin,
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            return@withContext CalendarSyncResult(added = 0, totalEvents = 0, permissionDenied = true)
        } catch (e: Throwable) {
            Log.e(TAG, "calendar sync query failed", e)
            return@withContext CalendarSyncResult(added = 0, totalEvents = 0, error = e.message ?: "日历查询失败")
        }

        mutex.withLock {
            val mergedById = _todos.value.associateBy { it.id }.toMutableMap()
            var added = 0
            for (event in events) {
                val prev = mergedById[event.id]
                if (prev == null) {
                    mergedById[event.id] = event
                    added++
                } else {
                    // 日历是这些字段的事实来源：刷新内容/时间/地点/排序时间戳，
                    // 保留用户的完成状态与加入时间
                    val updated = prev.copy(
                        task = event.task,
                        time = event.time,
                        location = event.location,
                        sortTs = event.sortTs,
                    )
                    mergedById[event.id] = updated
                }
            }
            // 清理已不在日历窗口内的历史同步项（用户手动勾选完成的保留）
            val currentIds = events.map { it.id }.toHashSet()
            val kept = mergedById.values.filter {
                !it.id.startsWith("cal-") || it.isCompleted || it.id in currentIds
            }
            val sorted = sortTodos(kept)
            _todos.value = sorted
            saveToDisk(sorted)
            Log.i(TAG, "calendar sync: ${events.size} events, $added added")
            CalendarSyncResult(added = added, totalEvents = events.size)
        }
    }

    private fun formatEventTime(begin: Long, allDay: Boolean): String {
        val date = SimpleDateFormat("MM月dd日", Locale.getDefault()).format(Date(begin))
        return if (allDay) "$date 全天"
        else "$date " + SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(begin))
    }

    companion object {
        private const val DAY_MS = 24L * 60 * 60 * 1000
    }
}
