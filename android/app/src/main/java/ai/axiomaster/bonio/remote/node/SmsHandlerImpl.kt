package ai.axiomaster.bonio.remote.node

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log
import androidx.core.content.ContextCompat
import ai.axiomaster.bonio.remote.gateway.GatewaySession
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private data class SmsRecord(
  val msgId: Long?,
  val senderNumber: String,
  val startTime: Long,
  val content: String,
)

private data class TelecomBillInfo(
  val carrier: String,
  val sender: String,
  val time: Long,
  val totalBill: Double?,
  val amountDue: Double?,
  val balance: Double?,
  val isPastDue: Boolean,
  val billingCycle: String?,
  val phoneNumber: String?,
  val rawContent: String,
  val summary: String,
) {
  fun toJson() = buildJsonObject {
    put("carrier", carrier)
    put("sender", sender)
    put("time", time)
    if (totalBill != null) put("totalBill", totalBill)
    if (amountDue != null) put("amountDue", amountDue)
    if (balance != null) put("balance", balance)
    put("isPastDue", isPastDue)
    if (billingCycle != null) put("billingCycle", billingCycle)
    if (phoneNumber != null) put("phoneNumber", phoneNumber)
    put("rawContent", rawContent)
    put("summary", summary)
  }
}

/**
 * Device SMS: send (sms.send), inbox search (sms.search) and carrier bill
 * parsing (sms.bill), ported from dsh-plugins/bonio-bridge sms_store.ts.
 * Uses SEND_SMS / READ_SMS standard permissions.
 */
class SmsHandler(private val context: Context) {

  private val json = Json { encodeDefaults = false }

  // ── sms.send ──

  suspend fun handleSmsSend(p: String?): GatewaySession.InvokeResult {
    var to = ""
    var message = ""
    if (p != null) {
      try {
        val params = json.parseToJsonElement(p) as? JsonObject ?: JsonObject(emptyMap())
        to = (params["to"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim() ?: ""
        message = (params["message"] as? kotlinx.serialization.json.JsonPrimitive)?.content ?: ""
      } catch (_: Throwable) {
        return error("INVALID_REQUEST", "sms.send params must be valid JSON")
      }
    }
    if (to.isEmpty() || message.isEmpty()) {
      return error("INVALID_REQUEST", "sms.send requires 'to' and 'message'")
    }
    if (!hasPermission(Manifest.permission.SEND_SMS)) {
      return error("SMS_PERMISSION_DENIED", "短信发送权限未授予 (SEND_SMS)")
    }
    return try {
      val sm = SmsManager.getDefault() ?: return error("SMS_UNAVAILABLE", "SMS not available on this device")
      // Long messages must be split; sendMultipartTextMessage handles that.
      if (message.length > SINGLE_PART_LIMIT) {
        val parts = sm.divideMessage(message)
        sm.sendMultipartTextMessage(to, null, parts, null, null)
      } else {
        sm.sendTextMessage(to, null, message, null, null)
      }
      GatewaySession.InvokeResult.ok(buildJsonObject { put("ok", true); put("to", to) }.toString())
    } catch (e: Throwable) {
      Log.w("SmsHandler", "sms.send failed", e)
      error("SMS_SEND_FAILED", e.message ?: "短信发送失败")
    }
  }

  // ── sms.search ──

  suspend fun handleSmsSearch(p: String?): GatewaySession.InvokeResult {
    var query = ""
    var sender = ""
    var limit = 20
    if (p != null) {
      try {
        val params = json.parseToJsonElement(p) as? JsonObject ?: JsonObject(emptyMap())
        query = (params["query"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim() ?: ""
        sender = (params["sender"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim() ?: ""
        limit = (params["limit"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toIntOrNull() ?: 20
      } catch (_: Throwable) {
        return error("INVALID_REQUEST", "sms.search params must be valid JSON")
      }
    }
    val records = queryInbox(limit.coerceIn(1, 100), query, sender)
    val payload = buildJsonObject {
      put("messages", buildJsonArray {
        for (r in records) {
          add(buildJsonObject {
            if (r.msgId != null) put("msgId", r.msgId)
            put("senderNumber", r.senderNumber)
            put("startTime", r.startTime)
            put("content", r.content)
          })
        }
      })
      put("total", records.size)
    }
    return GatewaySession.InvokeResult.ok(payload.toString())
  }

  // ── sms.bill ──

  suspend fun handleSmsBill(p: String?): GatewaySession.InvokeResult {
    val candidates = queryBillCandidates()
    val billSms = candidates.firstOrNull { isBillSms(it.content) && resolveCarrier(it.senderNumber, it.content) != "未知运营商" }
      ?: return GatewaySession.InvokeResult.ok(
        buildJsonObject {
          put("found", false)
          put("message", "未找到近期运营商账单短信。")
        }.toString(),
      )
    val info = parseBill(billSms)
    val payload = buildJsonObject {
      put("found", true)
      put("bill", info.toJson())
    }
    return GatewaySession.InvokeResult.ok(payload.toString())
  }

  // ── inbox access ──

  private fun hasPermission(permission: String): Boolean =
    ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

  private fun ensureReadPermission(): GatewaySession.InvokeResult? {
    if (hasPermission(Manifest.permission.READ_SMS)) return null
    return error("SMS_PERMISSION_DENIED", "短信读取权限未授予 (READ_SMS)")
  }

  private fun queryInbox(limit: Int, query: String, sender: String): List<SmsRecord> {
    ensureReadPermission()?.let { return emptyList() }
    val selections = mutableListOf<String>()
    val args = mutableListOf<String>()
    if (query.isNotEmpty()) {
      selections.add("${Telephony.Sms.BODY} LIKE ?")
      args.add("%$query%")
    }
    if (sender.isNotEmpty()) {
      selections.add("${Telephony.Sms.ADDRESS} LIKE ?")
      args.add("%${sender.trimStart('+')}%")
    }
    return querySms(
      Telephony.Sms.CONTENT_URI,
      selections.joinToString(" AND "),
      args.toTypedArray(),
      limit,
    )
  }

  private fun queryBillCandidates(): List<SmsRecord> {
    ensureReadPermission()?.let { return emptyList() }
    val carriers = listOf("10000", "10086", "10010")
    val keywords = listOf("账单", "欠费", "话费", "应付", "余额", "消费")
    val placeholders = carriers.joinToString(",") { "?" }
    val keywordClauses = keywords.joinToString(" OR ") { "${Telephony.Sms.BODY} LIKE ?" }
    val selection = "(${Telephony.Sms.ADDRESS} IN ($placeholders)) AND ($keywordClauses)"
    val args = (carriers + keywords.map { "%$it%" }).toTypedArray()
    return querySms(
      Telephony.Sms.CONTENT_URI,
      selection,
      args,
      10,
    )
  }

  private fun querySms(uri: android.net.Uri, selection: String?, args: Array<String>, limit: Int): List<SmsRecord> {
    val out = mutableListOf<SmsRecord>()
    try {
      context.contentResolver.query(
        uri,
        arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.DATE, Telephony.Sms.BODY),
        selection, args,
        "${Telephony.Sms.DATE} DESC",
      )?.use { c ->
        while (c.moveToNext() && out.size < limit) {
          out.add(
            SmsRecord(
              msgId = c.getLong(0),
              senderNumber = c.getString(1)?.trim().orEmpty(),
              startTime = c.getLong(2),
              content = c.getString(3).orEmpty(),
            ),
          )
        }
      }
    } catch (e: SecurityException) {
      Log.w("SmsHandler", "READ_SMS not granted")
    } catch (e: Throwable) {
      Log.w("SmsHandler", "sms query failed", e)
    }
    return out
  }

  // ── bill parsing (ported from sms_store.ts) ──

  private fun isBillSms(content: String): Boolean =
    Regex("(账单|欠费|话费|应付|余额|停机|消费)").containsMatchIn(content)

  private fun resolveCarrier(sender: String, content: String): String {
    if (sender == "10000" || content.contains("中国电信") || content.contains("电信")) return "中国电信"
    if (sender == "10086" || content.contains("中国移动") || content.contains("移动")) return "中国移动"
    if (sender == "10010" || content.contains("中国联通") || content.contains("联通")) return "中国联通"
    return "未知运营商"
  }

  private fun parseBill(sms: SmsRecord): TelecomBillInfo {
    val content = sms.content
    val carrier = resolveCarrier(sms.senderNumber, content)
    val amountDue = Regex("(?:实际应付|待缴金额|应付)(?:\\s*)([\\d\\.]+)元").find(content)?.groupValues?.get(1)?.toDoubleOrNull()
    val totalBill = Regex("(?:账单合计|共消费|消费合计|总消费|消费)(?:\\s*)([\\d\\.]+)元").find(content)?.groupValues?.get(1)?.toDoubleOrNull()
    val balance = Regex("(?:当前)?余额(?:\\s*)([\\d\\.-]+)元").find(content)?.groupValues?.get(1)?.toDoubleOrNull()
    val billingCycle = Regex("(?:账单周期为?|您)([0-9]{2}月[0-9]{2}日-[0-9]{2}月[0-9]{2}日|[^\\s，,。\r\n]+(?:至|-)[^\\s，,。\r\n]+)").find(content)?.groupValues?.get(1)
      ?: Regex("账单周期为?([^\\s，,。\r\n]+)").find(content)?.groupValues?.get(1)
    val phoneNumber = Regex("(?:号码为?|尊敬的|用户)([0-9*xX]{7,13})").find(content)?.groupValues?.get(1)
      ?: Regex("([0-9*xX]{7,13})客户").find(content)?.groupValues?.get(1)
    val isPastDue = (amountDue ?: 0.0) > 0 || (balance ?: 0.0) < 0 || content.contains("欠费") || content.contains("停机")

    val parts = mutableListOf(carrier)
    billingCycle?.let { parts.add("周期$it") }
    phoneNumber?.let { parts.add("号码$it") }
    totalBill?.let { parts.add("账单合计${it}元") }
    amountDue?.let { parts.add("实际应付${it}元") }
    balance?.let { parts.add("当前余额${it}元") }
    if (isPastDue) {
      parts.add("当前状态：待缴费/欠费")
    } else {
      parts.add("当前状态：正常")
    }

    return TelecomBillInfo(
      carrier = carrier,
      sender = sms.senderNumber,
      time = sms.startTime,
      totalBill = totalBill,
      amountDue = amountDue,
      balance = balance,
      isPastDue = isPastDue,
      billingCycle = billingCycle,
      phoneNumber = phoneNumber,
      rawContent = content,
      summary = parts.joinToString("，"),
    )
  }

  private fun error(code: String, message: String): GatewaySession.InvokeResult =
    GatewaySession.InvokeResult.error(code = code, message = message)

  private companion object {
    /** Single-part SMS ceiling per GSM 7-bit encoding (160 chars); over this we go multipart. */
    private const val SINGLE_PART_LIMIT = 160
  }
}
