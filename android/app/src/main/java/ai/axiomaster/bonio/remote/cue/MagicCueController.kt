package ai.axiomaster.bonio.remote.cue

import android.util.Log
import ai.axiomaster.bonio.remote.gateway.GatewaySession
import ai.axiomaster.bonio.remote.node.asObjectOrNull
import ai.axiomaster.bonio.remote.node.asStringOrNull
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
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

  sealed class CueResult {
    data class Success(val cues: List<MagicCue>) : CueResult()
    data class Error(val message: String) : CueResult()
  }

  private sealed class RunOutcome {
    data class Success(val text: String) : RunOutcome()
    data class Error(val message: String) : RunOutcome()
  }

  private val json = Json { ignoreUnknownKeys = true }
  private val pendingRuns: MutableMap<String, CompletableDeferred<RunOutcome>> =
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
    val deferred = synchronized(pendingRuns) {
      pendingRuns.remove(runId)
    } ?: return
    if (state == "final") {
      val text = payload["message"].asStringOrNull() ?: payload["text"].asStringOrNull() ?: ""
      ai.axiomaster.bonio.util.AppLogger.i(TAG, "handleGatewayEvent matched runId=$runId (final) text=${text.take(60)}")
      deferred.complete(RunOutcome.Success(text))
    } else {
      val errMsg = payload["errorMessage"].asStringOrNull() ?: "模型执行失败 ($state)"
      ai.axiomaster.bonio.util.AppLogger.w(TAG, "handleGatewayEvent matched runId=$runId ($state) error=$errMsg")
      deferred.complete(RunOutcome.Error(errMsg))
    }
  }

  /**
   * Run one cue cycle for the given screen context. Returns CueResult,
   * indicating either parsed cues or an explicit failure reason.
   */
  suspend fun runCue(screen: ScreenContext, screenshotBase64: String? = null): CueResult {
    val screenText = screen.content
    val hasText = screenText.isNotBlank()
    if (!hasText && screenshotBase64.isNullOrEmpty()) {
      ai.axiomaster.bonio.util.AppLogger.w(TAG, "runCue: screenText is blank and no screenshot, pkg=${screen.packageName}")
      return CueResult.Success(emptyList())
    }
    val vision = !hasText

    val facts = if (hasText) collectFacts(screenText) else null
    val prompt = buildPrompt(screen, facts, vision)
    ai.axiomaster.bonio.util.AppLogger.i(
      TAG,
      "runCue: screenText=${screenText.length}ch facts=${facts?.length ?: 0}ch vision=$vision shot=${!screenshotBase64.isNullOrEmpty()}",
    )

    // Keep the cue session ephemeral: one conversation per run.
    try {
      session.request("sessions.reset", """{"sessionKey":"$SESSION_KEY"}""", timeoutMs = 5_000)
    } catch (e: Throwable) {
      Log.w(TAG, "sessions.reset failed (continuing): ${e.message}")
    }

    val runId = UUID.randomUUID().toString()
    val deferred = CompletableDeferred<RunOutcome>()
    synchronized(pendingRuns) { pendingRuns[runId] = deferred }
    try {
      val params = buildJsonObject {
        put("sessionKey", JsonPrimitive(SESSION_KEY))
        put("message", JsonPrimitive(prompt))
        put("thinking", JsonPrimitive("low"))
        put("timeoutMs", JsonPrimitive(RUN_TIMEOUT_MS))
        put("idempotencyKey", JsonPrimitive(runId))
        if (vision && !screenshotBase64.isNullOrEmpty()) {
          put(
            "attachments",
            JsonArray(
              listOf(
                buildJsonObject {
                  put("type", JsonPrimitive("image"))
                  put("mimeType", JsonPrimitive("image/jpeg"))
                  put("fileName", JsonPrimitive("screen.jpg"))
                  put("content", JsonPrimitive(screenshotBase64))
                },
              ),
            ),
          )
        }
      }
      val res = try {
        session.request("chat.send", params.toString(), timeoutMs = 15_000)
      } catch (e: Throwable) {
        ai.axiomaster.bonio.util.AppLogger.e(TAG, "chat.send failed: ${e.message}", e)
        return CueResult.Error(e.message ?: "网关请求失败")
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
      val outcome = try {
        withTimeout(RUN_TIMEOUT_MS) { deferred.await() }
      } catch (_: TimeoutCancellationException) {
        ai.axiomaster.bonio.util.AppLogger.w(TAG, "cue run timed out")
        RunOutcome.Error("分析超时，请稍后再试")
      }
      return when (outcome) {
        is RunOutcome.Success -> {
          ai.axiomaster.bonio.util.AppLogger.i(TAG, "cue reply: ${outcome.text.take(100)}")
          CueResult.Success(parseCues(outcome.text))
        }
        is RunOutcome.Error -> {
          ai.axiomaster.bonio.util.AppLogger.w(TAG, "cue error: ${outcome.message}")
          CueResult.Error(outcome.message)
        }
      }
    } finally {
      synchronized(pendingRuns) {
        pendingRuns.remove(runId)
      }
    }
  }

  // ── L1 domain pre-check: fetch on-device facts before invoking the LLM ──

  private suspend fun collectFacts(screenText: String): String? {
    val allLines = screenText.lines().map { it.trim() }.filter { it.isNotEmpty() }
    val tail = allLines.takeLast(20).joinToString("\n")
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
        ai.axiomaster.bonio.util.AppLogger.w(TAG, "sms.bill pre-check failed: ${e.message}")
      }
    }

    val contactName = matchContactQuery(tail)
    ai.axiomaster.bonio.util.AppLogger.i(TAG, "collectFacts: matchedContact=$contactName from tail_len=${tail.length}")
    if (contactName != null) {
      try {
        val res = withTimeout(3_000) { contactsSearch(contactName, 5) }
        ai.axiomaster.bonio.util.AppLogger.i(TAG, "contactsSearch res.ok=${res.ok} payload=${res.payloadJson?.take(100)}")
        if (res.ok && res.payloadJson != null) {
          val obj = JSONObject(res.payloadJson)
          val contacts = obj.optJSONArray("contacts")
          if (contacts != null && contacts.length() > 0) {
            facts = appendFact(facts, formatContactsFact(contacts))
          }
        }
      } catch (e: Throwable) {
        ai.axiomaster.bonio.util.AppLogger.w(TAG, "contacts.search pre-check failed: ${e.message}")
      }
    }

    // 备忘（长期记忆）预检：屏幕问题与本地备忘 bigram 模糊匹配，命中则把
    // 备忘内容直接作为事实 —— 银行卡/账号这类只存于备忘的答案不依赖模型
    // 主动调用工具。
    memoFacts(tail)?.let { facts = appendFact(facts, it) }
    return facts
  }

  /** Screen-question ↔ memo fuzzy match via shared CJK bigrams. */
  private suspend fun memoFacts(tail: String): String? {
    return try {
      val res = withTimeout(5_000) { session.request("memo.list", """{"limit":200}""") }
      val arr = JSONObject(res).optJSONArray("memos") ?: return null
      val qBigrams = cjkBigrams(tail)
      if (qBigrams.isEmpty()) return null
      data class Scored(val title: String, val content: String, val score: Int)
      val scored = mutableListOf<Scored>()
      for (i in 0 until arr.length()) {
        val m = arr.optJSONObject(i) ?: continue
        val title = m.optString("title").trim()
        val content = m.optString("content").trim()
        if (title.isEmpty() && content.isEmpty()) continue
        val score = qBigrams.count { "$title $content".contains(it) }
        if (score >= 3) scored.add(Scored(title, content, score))
      }
      scored.sortByDescending { it.score }
      if (scored.isEmpty()) {
        ai.axiomaster.bonio.util.AppLogger.i(TAG, "memoFacts: no memo matched (${arr.length()} scanned)")
        null
      } else {
        ai.axiomaster.bonio.util.AppLogger.i(TAG, "memoFacts: matched ${scored.size} memo(s), top=${scored.first().title.take(30)}")
        val sb = StringBuilder("【用户备忘（长期记忆）查询结果】\n")
        for (s in scored.take(2)) {
          sb.append("标题：").append(s.title).append('\n')
          sb.append("内容：").append(s.content.take(300)).append('\n')
        }
        sb.toString()
      }
    } catch (e: Throwable) {
      ai.axiomaster.bonio.util.AppLogger.w(TAG, "memo.list pre-check failed: ${e.message}")
      null
    }
  }

  private fun cjkBigrams(text: String): Set<String> {
    val t = text.filter { it.code in 0x4E00..0x9FFF }
    if (t.length < 2) return emptySet()
    return (0 until t.length - 1).map { t.substring(it, it + 2) }.toSet()
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
      val phoneList = mutableListOf<String>()
      if (phones != null) {
        for (j in 0 until phones.length()) {
          val p = phones.optString(j).trim()
          if (p.isNotEmpty()) phoneList.add(p)
        }
      }
      val phone = phoneList.joinToString(", ")
      sb.append("电话：").append(phone.ifEmpty { "未登记手机号码" }).append('\n')
      c.optString("org", "").takeIf { it.isNotEmpty() }?.let { sb.append("公司：").append(it).append('\n') }
    }
    return sb.toString()
  }

  // ── prompt ──

  private fun buildPrompt(screen: ScreenContext, facts: String?, vision: Boolean = false): String {
    val sb = StringBuilder()
    sb.append("你是 Bonio 的 Magic Cue 助手。基于用户当前屏幕内容，产出可直接执行的操作建议。\n")
    sb.append("（应用：").append(screen.packageName.ifEmpty { "未知" })
    if (screen.title.isNotEmpty()) sb.append("，会话对象/标题：【").append(screen.title).append("】")
    sb.append("）：\n")
    if (vision) {
      sb.append("（无障碍树为空，请直接分析附件中的屏幕截图）\n")
    } else {
      sb.append("<屏幕文本>\n").append(screen.content).append("\n</屏幕文本>\n")
      if (!facts.isNullOrEmpty()) {
        sb.append("<端侧已知事实>\n").append(facts).append("\n</端侧已知事实>\n")
      }
    }
    sb.append(
      """
      |规则：
      |1. 只答复时序上最后一次未回复的提问；忽略历史旧问题与标题栏。
      |2. 如果屏幕底部已经是对方问题的回答（已回复检查），必须输出 {"cues":[]}。
      |3. 先用<端侧已知事实>作答；事实中没有答案时，必须调用工具（memory_recall / contacts.search 等）查询实际结果，把结果原文作为 content，禁止不查询就作答。
      |4. 严禁输出"去查询/请查通讯录/你可以查一下"之类让用户自己操作的指令性建议；仅当工具查询后确认无答案时才输出 {"cues":[]}。
      |5. 通讯录没有手机号时，不得拿邮箱充当手机号。
      |6. 排除验证码、密码、支付转账信息。
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
      Regex("(?:请问|帮我查下|帮我查一下|帮我查|查一下|查下|帮我找一下|帮我找下|帮我找|找一下|找下|看看|看下|问下|发一下|发下|发我|发给我|把|谁有)?([^\\s，。？！?,\\.!？:：\"“”'‘’]{1,10}?)(?:的)?(?:手机号码|电话号码|手机号|电话号|手机|电话|号码|联系方式)(?!(?:银行|营业厅|应用|客户端|商城|充值|设置|卡|网络|配件|壳|膜|支架|壁纸|主题|专卖店|售后|维修))")
    private val CONTACT_NOISE = Regex("(这个|那个|什么|哪个|谁|有无|有么|在哪|这里|登录|注册|打开|下载|安装|进入|点击|使用|管理|办理|查询|支持|短信|银行|账号|账户|密码|验证码)")

    /** Extract the contact name for the pre-check from the visible question. */
    fun matchContactQuery(text: String): String? {
      val match = CONTACT_REGEX.findAll(text).lastOrNull() ?: return null
      var name = match.groupValues[1].trim()
      name = name.replace(Regex("[\"“”'‘’]"), "").trim()
      name = Regex("^(请问|帮我查下|帮我查一下|帮我查|查一下|查下|查询|找一下|找下|找|看看|看下|问下|发一下|发下|发我|发给我|把|谁有)").replace(name, "").trim()
      if (name.startsWith("我") && name.length > 1 && (name.startsWith("我爸") || name.startsWith("我妈") || name.startsWith("我哥") || name.startsWith("我姐") || name.startsWith("我弟") || name.startsWith("我妹"))) {
        name = name.removePrefix("我")
      }
      if (name.endsWith("的") && name.length > 1) {
        name = name.removeSuffix("的").trim()
      }
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
