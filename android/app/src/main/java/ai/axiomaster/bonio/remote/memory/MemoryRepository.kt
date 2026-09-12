package ai.axiomaster.bonio.remote.memory

import android.util.Log
import ai.axiomaster.bonio.remote.gateway.GatewaySession
import ai.axiomaster.bonio.remote.node.asObjectOrNull
import ai.axiomaster.bonio.remote.node.asStringOrNull
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** One saved memo (记一记 entry) as returned by the memo.list / memo.get RPC. */
data class BonioMemo(
  val id: String,
  val title: String,
  val content: String,
  val source: String,
  val createdAt: Long?,
  val tags: List<String>,
  val sourceApp: String? = null,
  val pageTitle: String? = null,
  val pageLink: String? = null,
  val coverImage: String? = null,
  val originalImage: String? = null,
  val originalImageMimeType: String? = null,
)

/**
 * Client for the memo.* gateway RPCs (hiclaw memo_tool / bonio-bridge
 * memo_store share the same protocol). Memos persist on the backend under
 * the engine's data dir.
 */
class MemoryService(private val session: GatewaySession) {

  private val json = Json { ignoreUnknownKeys = true }

  data class SaveParams(
    val title: String,
    val content: String,
    val source: String = "manual",
    val tags: List<String> = emptyList(),
    val sourceApp: String? = null,
    val pageTitle: String? = null,
    val pageLink: String? = null,
  )

  private fun parseMemo(m: JsonObject): BonioMemo? {
    val id = m["id"].asStringOrNull() ?: return null
    return BonioMemo(
      id = id,
      title = m["title"].asStringOrNull().orEmpty(),
      content = m["content"].asStringOrNull().orEmpty(),
      source = m["source"].asStringOrNull().orEmpty(),
      createdAt = (m["createdAt"] as? JsonPrimitive)?.content?.toLongOrNull()
        ?: (m["timestamp"] as? JsonPrimitive)?.content?.toLongOrNull(),
      tags = (m["tags"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content } ?: emptyList(),
      sourceApp = m["sourceApp"].asStringOrNull(),
      pageTitle = m["pageTitle"].asStringOrNull(),
      pageLink = m["pageLink"].asStringOrNull(),
      coverImage = m["coverImage"].asStringOrNull(),
      originalImage = m["originalImage"].asStringOrNull(),
      originalImageMimeType = m["originalImageMimeType"].asStringOrNull(),
    )
  }

  suspend fun save(params: SaveParams): Result<Unit> = runCatching {
    val body = buildJsonObject {
      put("title", JsonPrimitive(params.title.ifBlank { "Untitled" }))
      put("content", JsonPrimitive(params.content))
      put("source", JsonPrimitive(params.source))
      if (params.tags.isNotEmpty()) {
        put("tags", buildJsonArray { params.tags.forEach { add(JsonPrimitive(it)) } })
      }
      params.sourceApp?.let { put("sourceApp", JsonPrimitive(it)) }
      params.pageTitle?.let { put("pageTitle", JsonPrimitive(it)) }
      params.pageLink?.let { put("pageLink", JsonPrimitive(it)) }
    }
    val payload = session.request("memo.save", body.toString(), timeoutMs = 15_000)
    val obj = json.parseToJsonElement(payload).asObjectOrNull()
    val saved = (obj?.get("saved") as? JsonPrimitive)?.content?.toBooleanStrictOrNull() ?: false
    if (!saved) error("memo.save unexpected response")
    Unit
  }

  suspend fun list(limit: Int = 200): Result<List<BonioMemo>> = runCatching {
    val payload = session.request("memo.list", """{"limit":$limit}""", timeoutMs = 15_000)
    val obj = json.parseToJsonElement(payload).asObjectOrNull()
    val arr = obj?.get("memos") as? JsonArray ?: return Result.success(emptyList())
    arr.mapNotNull { el ->
      val m = el as? JsonObject ?: return@mapNotNull null
      parseMemo(m)
    }
  }

  suspend fun get(id: String): Result<BonioMemo?> = runCatching {
    val payload = session.request("memo.get", """{"id":${JsonPrimitive(id)}}""", timeoutMs = 15_000)
    val obj = json.parseToJsonElement(payload).asObjectOrNull()
    val m = obj?.get("memo") as? JsonObject ?: return@runCatching null
    parseMemo(m)
  }

  suspend fun delete(id: String): Result<Unit> = runCatching {
    session.request("memo.delete", """{"id":${JsonPrimitive(id)}}""", timeoutMs = 15_000)
    Unit
  }
}

/**
 * UI-facing state holder for the Memory tab: memo list + load/save/delete.
 */
class MemoryRepository(
  session: GatewaySession,
  private val scope: CoroutineScope,
) {
  private val service = MemoryService(session)

  private val _memos = MutableStateFlow<List<BonioMemo>>(emptyList())
  val memos: StateFlow<List<BonioMemo>> = _memos.asStateFlow()

  private val _loading = MutableStateFlow(false)
  val loading: StateFlow<Boolean> = _loading.asStateFlow()

  private val _error = MutableStateFlow<String?>(null)
  val error: StateFlow<String?> = _error.asStateFlow()

  fun refresh() {
    scope.launch {
      _loading.value = true
      _error.value = null
      service.list()
        .onSuccess { _memos.value = it }
        .onFailure {
          Log.w("MemoryRepository", "memo.list failed", it)
          _error.value = it.message
        }
      _loading.value = false
    }
  }

  fun save(params: MemoryService.SaveParams, onDone: (Boolean) -> Unit = {}) {
    scope.launch {
      val ok = service.save(params)
        .onSuccess { refresh() }
        .onFailure {
          Log.w("MemoryRepository", "memo.save failed", it)
          _error.value = it.message
        }
        .isSuccess
      onDone(ok)
    }
  }

  fun delete(id: String) {
    scope.launch {
      service.delete(id)
        .onSuccess { refresh() }
        .onFailure {
          Log.w("MemoryRepository", "memo.delete failed", it)
          _error.value = it.message
        }
    }
  }

  suspend fun get(id: String): BonioMemo? {
    return service.get(id).getOrNull()
  }
}
