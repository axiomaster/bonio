package ai.axiomaster.bonio.remote.memory

import android.util.Log
import ai.axiomaster.bonio.remote.cue.MagicCueController
import ai.axiomaster.bonio.remote.gateway.GatewaySession
import ai.axiomaster.bonio.remote.node.asObjectOrNull
import ai.axiomaster.bonio.remote.node.asStringOrNull
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONObject
import java.util.Collections
import java.util.UUID

/**
 * Companion memory (伴随记忆): on avatar double-tap, run a hidden ephemeral
 * LLM session over the captured screen text that decides whether the page is
 * worth remembering; worthwhile pages are stored via memo.save. Ported from
 * harmonyos CompanionMemoryController.ets (SmartEdge trigger → a11y trigger).
 */
class CompanionMemoryController(
  private val session: GatewaySession,
  private val memoryService: MemoryService,
) {
  private val json = Json { ignoreUnknownKeys = true }
  private val pendingRuns: MutableMap<String, CompletableDeferred<String?>> =
    Collections.synchronizedMap(mutableMapOf())

  /** Consume operator-session `chat` events for the hidden session. */
  fun handleGatewayEvent(event: String, payloadJson: String?) {
    if (event != "chat" || payloadJson == null) return
    val payload = try {
      json.parseToJsonElement(payloadJson).asObjectOrNull()
    } catch (_: Throwable) {
      null
    } ?: return
    val sessionKey = payload["sessionKey"].asStringOrNull()?.trim() ?: return
    if (sessionKey != SESSION_KEY) return
    val runId = payload["runId"].asStringOrNull() ?: return
    val state = payload["state"].asStringOrNull() ?: return
    if (state != "final" && state != "error" && state != "aborted") return
    val deferred = synchronized(pendingRuns) {
      pendingRuns.remove(runId)
    } ?: return
    val text = if (state == "final") {
      payload["message"].asStringOrNull() ?: payload["text"].asStringOrNull()
    } else {
      null
    }
    ai.axiomaster.bonio.util.AppLogger.i(TAG, "handleGatewayEvent matched runId=$runId text=${text?.take(60)}")
    deferred.complete(text)
  }

  /**
   * Analyze the screen and remember it if worthwhile. Returns true when a
   * memo was saved (only meaningful for explicit captures).
   */
  suspend fun capture(
    screen: MagicCueController.ScreenContext,
    explicit: Boolean,
    coverImage: String? = null,
    originalImage: String? = null,
  ): Boolean {
    val text = screen.content.ifBlank {
      if (explicit) screen.title.ifBlank { "应用: ${screen.packageName}" } else ""
    }
    if (text.isBlank() && coverImage.isNullOrEmpty()) return false
    ai.axiomaster.bonio.util.AppLogger.i(
      TAG,
      "capture: explicit=$explicit text=${text.length}ch hasCover=${!coverImage.isNullOrEmpty()}"
    )

    try {
      session.request("sessions.reset", """{"sessionKey":"$SESSION_KEY"}""", timeoutMs = 5_000)
    } catch (e: Throwable) {
      Log.w(TAG, "sessions.reset failed (continuing): ${e.message}")
    }

    val runId = UUID.randomUUID().toString()
    val deferred = CompletableDeferred<String?>()
    synchronized(pendingRuns) { pendingRuns[runId] = deferred }
    try {
      val prompt = buildPrompt(screen, text, explicit)
      val params = buildJsonObject {
        put("sessionKey", JsonPrimitive(SESSION_KEY))
        put("message", JsonPrimitive(prompt))
        put("thinking", JsonPrimitive("low"))
        put("timeoutMs", JsonPrimitive(RUN_TIMEOUT_MS))
        put("idempotencyKey", JsonPrimitive(runId))
      }
      val res = try {
        session.request("chat.send", params.toString(), timeoutMs = 15_000)
      } catch (e: Throwable) {
        ai.axiomaster.bonio.util.AppLogger.e(TAG, "chat.send failed: ${e.message}", e)
        return false
      }
      val resObj = try { json.parseToJsonElement(res).asObjectOrNull() } catch (_: Throwable) { null }
      val payloadObj = resObj?.get("payload")?.asObjectOrNull()
      val actualRunId = payloadObj?.get("runId")?.asStringOrNull() ?: resObj?.get("runId")?.asStringOrNull()
      ai.axiomaster.bonio.util.AppLogger.i(TAG, "chat.send response: actualRunId=$actualRunId (local=$runId)")
      if (!actualRunId.isNullOrEmpty() && actualRunId != runId) {
        synchronized(pendingRuns) {
          if (pendingRuns.containsKey(runId)) {
            pendingRuns.remove(runId)
            pendingRuns[actualRunId] = deferred
          }
        }
      }
      val reply = try {
        withTimeout(RUN_TIMEOUT_MS) { deferred.await() }
      } catch (_: TimeoutCancellationException) {
        ai.axiomaster.bonio.util.AppLogger.w(TAG, "companion memory run timed out")
        return false
      } ?: return false

      val summary = parseSummary(reply) ?: return false
      if (summary.shouldRemember == false || summary.content.isBlank()) return false

      val saveParams = MemoryService.SaveParams(
        title = summary.title.ifBlank { "屏幕记忆" },
        content = summary.content,
        source = if (explicit) "a11y_trigger" else "a11y_subscribe",
        tags = summary.tags.take(3),
        sourceApp = summary.sourceApp ?: screen.packageName,
        pageTitle = summary.pageTitle ?: screen.title,
        coverImage = coverImage,
        originalImage = originalImage ?: coverImage,
      )
      return memoryService.save(saveParams).isSuccess
    } finally {
      synchronized(pendingRuns) {
        pendingRuns.remove(runId)
      }
    }
  }

  private data class Summary(
    val shouldRemember: Boolean?,
    val title: String,
    val content: String,
    val tags: List<String>,
    val sourceApp: String?,
    val pageTitle: String?,
  )

  private fun parseSummary(reply: String): Summary? {
    val start = reply.indexOf('{')
    val end = reply.lastIndexOf('}')
    if (start < 0 || end <= start) return null
    return try {
      val obj = JSONObject(reply.substring(start, end + 1))
      val tags = mutableListOf<String>()
      val tagsArr = obj.optJSONArray("tags")
      if (tagsArr != null) {
        for (i in 0 until tagsArr.length()) {
          val t = tagsArr.optString(i).trim()
          if (t.isNotEmpty()) tags.add(t)
        }
      }
      Summary(
        shouldRemember = when (obj.opt("shouldRemember")) {
          is Boolean -> obj.optBoolean("shouldRemember")
          else -> obj.optString("shouldRemember").toBooleanStrictOrNull()
        },
        title = obj.optString("title").trim(),
        content = obj.optString("content").trim(),
        tags = tags,
        sourceApp = obj.optString("sourceApp").trim().ifEmpty { null },
        pageTitle = obj.optString("pageTitle").trim().ifEmpty { null },
      )
    } catch (e: Throwable) {
      Log.w(TAG, "parseSummary failed: ${e.message}")
      null
    }
  }

  private fun buildPrompt(screen: MagicCueController.ScreenContext, text: String, explicit: Boolean): String {
    val sb = StringBuilder()
    sb.append("你是 Bonio 的后台伴随记忆助手。这不是主对话，不要回复用户；判断下面的屏幕内容是否值得为用户记住。\n")
    sb.append("（应用：").append(screen.packageName.ifEmpty { "未知" })
    if (screen.title.isNotEmpty()) sb.append("，页面标题：【").append(screen.title).append("】")
    sb.append("）：\n")
    sb.append("<屏幕文本>\n")
    val clipped = if (text.length > MAX_PAYLOAD_CHARS) {
      "[早期屏幕内容已省略]\n" + text.takeLast(MAX_PAYLOAD_CHARS)
    } else {
      text
    }
    sb.append(clipped).append("\n</屏幕文本>\n")
    if (explicit) {
      sb.append("用户刚刚双击头像主动保存了这个页面，必须 shouldRemember:true。\n")
      sb.append("如果页面包含订单/卡片详情，字段要逐字转录（订单号、金额、日期、状态）。\n")
    } else {
      sb.append("高价值内容：支付/账单、证件、文章、商品、店铺、订单。忽略：密码、验证码、私信闲聊、瞬时提示。\n")
    }
    sb.append(
      "不调用工具、不输出 Markdown，只返回一个可 JSON.parse 的对象：" +
        "有价值 {\"shouldRemember\":true,\"title\":\"简短标题\",\"content\":\"1到3句中文摘要\"," +
        "\"tags\":[\"1到3个内容类别\"],\"sourceApp\":\"…\",\"pageTitle\":\"…\",\"pageLink\":\"…\"}；" +
        "无价值 {\"shouldRemember\":false}。",
    )
    return sb.toString()
  }

  companion object {
    private const val TAG = "CompanionMemory"
    const val SESSION_KEY = "system:companion-memory"
    private const val RUN_TIMEOUT_MS = 30_000L
    private const val MAX_PAYLOAD_CHARS = 60_000
  }
}
