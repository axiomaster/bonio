package ai.axiomaster.bonio.remote.cue

import android.util.Log
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

/** One actionable suggestion capsule produced by the Magic Cue run. */
data class MagicCue(
  val kind: String,
  val title: String,
  val content: String,
)

/**
 * Magic Cue: double-tap the avatar → read the current screen via the
 * accessibility tree → optionally pre-fetch on-device facts (carrier bill,
 * contacts) → ask the LLM (hidden ephemeral session `system:magic-cue`) for
 * actionable suggestion capsules → parse pure-JSON reply into [MagicCue]s.
 *
 * Ported from harmonyos/entry/src/main/ets/node/MagicCueController.ets,
 * adapted to the Android accessibility dump shape and to hiclaw as backend
 * (whole prompt goes in the user message; the cue session is reset before
 * every run to keep it ephemeral).
 */
class MagicCueController(
  private val session: GatewaySession,
  private val smsBill: suspend () -> GatewaySession.InvokeResult,
  private val contactsSearch: suspend (query: String, limit: Int) -> GatewaySession.InvokeResult,
) {
  data class ScreenContext(
    val packageName: String,
    val title: String,
    val content: String,
    val rawJson: String,
  )

  private val json = Json { ignoreUnknownKeys = true }
  private val pendingRuns: MutableMap<String, CompletableDeferred<String?>> =
    Collections.synchronizedMap(mutableMapOf())

  /** Consume operator-session `chat` events; completes the awaiting run. */
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
    val deferred = synchronized(pendingRuns) { pendingRuns.remove(runId) } ?: return
    val text = if (state == "final") {
      payload["message"].asStringOrNull() ?: payload["text"].asStringOrNull()
    } else {
      payload["errorMessage"].asStringOrNull()
    }
    deferred.complete(text)
  }

  /**
   * Run one cue cycle for the given screen context. Returns the parsed cues,
   * or null when the screen had nothing to act on / the run failed.
   */
  suspend fun runCue(screen: ScreenContext): List<MagicCue>? {
    val screenText = screen.content
    if (screenText.isBlank()) return emptyList()

    val facts = collectFacts(screenText)
    val prompt = buildPrompt(screen, facts)
    Log.i(TAG, "runCue: screenText=${screenText.length}ch facts=${facts?.length ?: 0}ch")

    // Keep the cue session ephemeral: one conversation per run.
    try {
      session.request("sessions.reset", """{"sessionKey":"$SESSION_KEY"}""", timeoutMs = 5_000)
    } catch (e: Throwable) {
      Log.w(TAG, "sessions.reset failed (continuing): ${e.message}")
    }

    val runId = UUID.randomUUID().toString()
    val deferred = CompletableDeferred<String?>()
    synchronized(pendingRuns) { pendingRuns[runId] = deferred }
    try {
      val params = buildJsonObject {
        put("sessionKey", JsonPrimitive(SESSION_KEY))
        put("message", JsonPrimitive(prompt))
        put("thinking", JsonPrimitive("low"))
        put("timeoutMs", JsonPrimitive(RUN_TIMEOUT_MS))
        put("idempotencyKey", JsonPrimitive(runId))
      }
      try {
        session.request("chat.send", params.toString(), timeoutMs = 15_000)
      } catch (e: Throwable) {
        Log.w(TAG, "chat.send failed: ${e.message}")
        return null
      }
      val reply = try {
        withTimeout(RUN_TIMEOUT_MS) { deferred.await() }
      } catch (_: TimeoutCancellationException) {
        Log.w(TAG, "cue run timed out")
        null
      }
      return reply?.let { parseCues(it) }
    } finally {
      synchronized(pendingRuns) { pendingRuns.remove(runId) }
    }
  }

  // ── L1 domain pre-check: fetch on-device facts before invoking the LLM ──

  private suspend fun collectFacts(screenText: String): String? {
    val tail = screenText.lines().takeLast(4).joinToString("\n")
    var facts: String? = null

    if (BILL_HINT_REGEX.containsMatchIn(tail)) {
      try {
        val res = withTimeout(3_000) { smsBill() }
        if (res.ok && res.payloadJson != null) {
          val obj = JSONObject(res.payloadJson)
          if (obj.optBoolean("found", false)) {
            val bill = obj.optJSONObject("bill")
            if (bill != null) facts = appendFact(facts, formatBillFact(bill))
          }
        }
      } catch (e: Throwable) {
        Log.d(TAG, "sms.bill pre-check failed: ${e.message}")
      }
    }

    val contactName = matchContactQuery(tail)
    if (contactName != null) {
      try {
        val res = withTimeout(3_000) { contactsSearch(contactName, 5) }
        if (res.ok && res.payloadJson != null) {
          val obj = JSONObject(res.payloadJson)
          val contacts = obj.optJSONArray("contacts")
          if (contacts != null && contacts.length() > 0) {
            facts = appendFact(facts, formatContactsFact(contacts))
          }
        }
      } catch (e: Throwable) {
        Log.d(TAG, "contacts.search pre-check failed: ${e.message}")
      }
    }
    return facts
  }

  private fun appendFact(current: String?, addition: String): String =
    if (current.isNullOrEmpty()) addition else "$current\n$addition"

  private fun formatBillFact(bill: JSONObject): String {
    val sb = StringBuilder("【运营商最新账单事实】\n")
    sb.append("运营商：").append(bill.optString("carrier")).append('\n')
    bill.optString("billingCycle", "").takeIf { it.isNotEmpty() }?.let { sb.append("账期：").append(it).append('\n') }
    bill.optString("phoneNumber", "").takeIf { it.isNotEmpty() }?.let { sb.append("对应号码：").append(it).append('\n') }
    if (bill.has("totalBill")) sb.append("账单合计：").append(bill.optDouble("totalBill")).append("元\n")
    if (bill.has("amountDue")) sb.append("实际应付/待缴：").append(bill.optDouble("amountDue")).append("元\n")
    if (bill.has("balance")) sb.append("当前余额：").append(bill.optDouble("balance")).append("元\n")
    sb.append("状态：").append(if (bill.optBoolean("isPastDue")) "欠费" else "正常").append('\n')
    bill.optString("summary", "").takeIf { it.isNotEmpty() }?.let { sb.append("摘要：").append(it) }
    return sb.toString()
  }

  private fun formatContactsFact(contacts: org.json.JSONArray): String {
    val sb = StringBuilder("【通讯录查询结果】\n")
    for (i in 0 until contacts.length()) {
      val c = contacts.optJSONObject(i) ?: continue
      sb.append("姓名：").append(c.optString("name")).append('\n')
      val phones = c.optJSONArray("phones")
      val phone = if (phones != null && phones.length() > 0) phones.optString(0) else ""
      sb.append("电话：").append(phone.ifEmpty { "未登记手机号码" }).append('\n')
      c.optString("org", "").takeIf { it.isNotEmpty() }?.let { sb.append("公司：").append(it).append('\n') }
    }
    return sb.toString()
  }

  // ── prompt ──

  private fun buildPrompt(screen: ScreenContext, facts: String?): String {
    val sb = StringBuilder()
    sb.append("你是 Bonio 的 Magic Cue 助手。基于用户当前屏幕内容，产出可直接执行的操作建议。\n")
    sb.append("（应用：").append(screen.packageName.ifEmpty { "未知" })
    if (screen.title.isNotEmpty()) sb.append("，会话对象/标题：【").append(screen.title).append("】")
    sb.append("）：\n")
    sb.append("<屏幕文本>\n").append(screen.content).append("\n</屏幕文本>\n")
    if (!facts.isNullOrEmpty()) {
      sb.append("<端侧已知事实>\n").append(facts).append("\n</端侧已知事实>\n")
    }
    sb.append(
      """
      |规则：
      |1. 只答复时序上最后一次未回复的提问；忽略历史旧问题与标题栏。
      |2. 如果屏幕底部已经是对方问题的回答（已回复检查），必须输出 {"cues":[]}。
      |3. 优先采用端侧已知事实，禁止重复调用工具。
      |4. 通讯录没有手机号时，不得拿邮箱充当手机号。
      |5. 排除验证码、密码、支付转账信息。
      |输出格式：纯 JSON，不要 Markdown、不要解释：
      |{"cues":[{"kind":"bill|contact|calendar|memo|text","title":"…","content":"…"}]}
      |没有建议时输出 {"cues":[]}。
    """.trimMargin(),
    )
    return sb.toString()
  }

  // ── parsing ──

  private fun parseCues(reply: String): List<MagicCue> {
    val start = reply.indexOf('{')
    val end = reply.lastIndexOf('}')
    if (start < 0 || end <= start) return emptyList()
    val cues = mutableListOf<MagicCue>()
    try {
      val obj = JSONObject(reply.substring(start, end + 1))
      val arr = obj.optJSONArray("cues") ?: return emptyList()
      for (i in 0 until arr.length()) {
        if (cues.size >= MAX_CUES) break
        val item = arr.optJSONObject(i) ?: continue
        val kind = item.optString("kind").trim().lowercase()
        val title = item.optString("title").trim()
        val content = item.optString("content").trim()
        if (kind !in KIND_WHITELIST) continue
        if (title.isEmpty() || content.isEmpty()) continue
        cues.add(MagicCue(kind = kind, title = title, content = content))
      }
    } catch (e: Throwable) {
      Log.w(TAG, "parseCues failed: ${e.message}")
    }
    return cues
  }

  companion object {
    private const val TAG = "MagicCue"
    const val SESSION_KEY = "system:magic-cue"
    private const val RUN_TIMEOUT_MS = 30_000L
    private const val MAX_CUES = 2
    private val KIND_WHITELIST = setOf("contact", "calendar", "memo", "bill", "text", "sms")

    private val BILL_HINT_REGEX = Regex("(话费|欠费|账单|扣费|交费|缴费|停机|余额)")
    private val CONTACT_REGEX =
      Regex("(?:请问|帮我查下|帮我查一下|帮我查|查一下|查下|帮我找一下|帮我找下|帮我找|找一下|找下|看看|看下|问下|发一下|发下|发我|发给我|把)?([^\\s，。？！?,\\.!？:：]{1,10}?)(?:的)?(?:手机号码|电话号码|手机号|电话号|手机|电话|号码|联系方式)")
    private val CONTACT_NOISE = Regex("(这个|那个|什么|哪个|谁|有无|有么|在哪|这里)")

    /** Extract the contact name for the pre-check from the visible question. */
    fun matchContactQuery(text: String): String? {
      val match = CONTACT_REGEX.find(text) ?: return null
      val name = match.groupValues[1].trim()
      if (name.isEmpty() || name.length > 10) return null
      if (CONTACT_NOISE.containsMatchIn(name)) return null
      return name
    }

    /** Flatten screen text from a screen.context payload (Android shape). */
    fun extractScreenText(contextJson: String): String {
      return try {
        val obj = JSONObject(contextJson)
        obj.optString("content").orEmpty()
      } catch (_: Throwable) {
        ""
      }
    }
  }
}
