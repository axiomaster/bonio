package ai.axiomaster.bonio.remote.todo

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import java.io.File

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
                    _todos.value = items.sortedWith(
                        compareBy<TodoItem> { it.isCompleted }
                            .thenByDescending { it.createdAt }
                    )
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
                val sorted = updated.sortedWith(
                    compareBy<TodoItem> { it.isCompleted }
                        .thenByDescending { it.createdAt }
                )
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
                val sorted = updated.sortedWith(
                    compareBy<TodoItem> { it.isCompleted }
                        .thenByDescending { it.createdAt }
                )
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
}
