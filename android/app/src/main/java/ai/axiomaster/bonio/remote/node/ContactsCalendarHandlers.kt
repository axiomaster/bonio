package ai.axiomaster.bonio.remote.node

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import androidx.core.content.ContextCompat
import ai.axiomaster.bonio.remote.gateway.GatewaySession
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private const val DAY_MS = 24L * 60L * 60L * 1000L

/** One matched contact, flattened for the agent. */
private data class ContactHit(
  val name: String,
  val phones: MutableList<String> = mutableListOf(),
  val emails: MutableList<String> = mutableListOf(),
  var org: String? = null,
)

private data class EventHit(
  val title: String,
  val startTs: Long,
  val endTs: Long,
  val allDay: Boolean,
  val location: String?,
)

/**
 * Address-book lookup (contacts.search). Pulls names + phonetics and matches
 * locally (name / pinyin prefix / substring / phone-number suffix), which is
 * fine at personal-address-book scale. Mirrors the HarmonyOS implementation.
 */
class ContactsHandler(private val context: Context) {

  private val json = Json { encodeDefaults = false }

  suspend fun handleContactsSearch(p: String?): GatewaySession.InvokeResult {
    var query = ""
    var limit = 5
    if (p != null) {
      try {
        val params = json.parseToJsonElement(p) as? JsonObject ?: JsonObject(emptyMap())
        query = (params["query"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim() ?: ""
        limit = (params["limit"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toIntOrNull() ?: 5
      } catch (_: Throwable) {
        return error("INVALID_REQUEST", "contacts.search params must be valid JSON")
      }
    }
    if (query.isEmpty()) {
      return error("INVALID_REQUEST", "contacts.search requires a query string")
    }
    if (!hasReadContacts()) {
      return error("CONTACTS_QUERY_FAILED", "通讯录权限未授予 (READ_CONTACTS)")
    }

    return try {
      val needle = cleanQuery(query)
      val hits = searchContacts(needle, limit.coerceIn(1, 20))
      val payload = buildJsonObject {
        put("contacts", buildJsonArray {
          for (hit in hits) {
            add(buildJsonObject {
              put("name", hit.name)
              put("phones", buildJsonArray { hit.phones.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } })
              if (!hit.org.isNullOrEmpty()) put("org", hit.org)
              if (hit.emails.isNotEmpty()) {
                put("emails", buildJsonArray { hit.emails.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } })
              }
            })
          }
        })
        put("total", hits.size)
      }
      GatewaySession.InvokeResult.ok(payload.toString())
    } catch (e: SecurityException) {
      error("CONTACTS_QUERY_FAILED", "通讯录权限未授予 (READ_CONTACTS)")
    } catch (e: Throwable) {
      Log.w("ContactsHandler", "contacts.search failed", e)
      error("CONTACTS_QUERY_FAILED", e.message ?: "通讯录查询失败")
    }
  }

  private fun hasReadContacts(): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

  /** Strip common query suffixes & question words (e.g. "“鲍亚永”的手机号码是多少？" -> "鲍亚永", "我爸" -> "爸"). */
  private fun cleanQuery(raw: String): String {
    var needle = raw.trim().lowercase()
    needle = needle.replace(Regex("[\"“”'‘’]"), "").trim()
    needle = Regex("(是多少|是几|多少|是谁|是啥|是哪位|发一下|发下|告诉我|发给我|请发|有吗|有没|有么|吗)[？?！!。.]*$").replace(needle, "").trim()
    needle = Regex("(的)?(手机号码|电话号码|手机号|电话号|手机|电话|号码|联系方式|邮箱|微信)$").replace(needle, "").trim()
    needle = Regex("^(请问|帮我查一下|帮我查下|帮我查|查一下|查下|查询|找一下|找下|找|看看|看下|问下|发一下|发下|发我|发给我|把)").replace(needle, "").trim()
    if (needle.startsWith("我") && needle.length > 1 && (needle.startsWith("我爸") || needle.startsWith("我妈") || needle.startsWith("我哥") || needle.startsWith("我姐") || needle.startsWith("我弟") || needle.startsWith("我妹"))) {
      needle = needle.removePrefix("我")
    }
    if (needle.endsWith("的") && needle.length > 1) {
      needle = needle.removeSuffix("的").trim()
    }
    if (needle.isEmpty()) needle = raw.trim().lowercase()
    return needle
  }

  private fun searchContacts(needle: String, maxHits: Int): List<ContactHit> {
    val resolver = context.contentResolver

    // contactId -> (name, phonetic)
    data class Entry(val id: Long, val name: String, val phonetic: String)
    val entries = mutableListOf<Entry>()
    resolver.query(
      ContactsContract.Contacts.CONTENT_URI,
      arrayOf(
        ContactsContract.Contacts._ID,
        ContactsContract.Contacts.DISPLAY_NAME,
        ContactsContract.Contacts.PHONETIC_NAME,
      ),
      null, null, null,
    )?.use { c ->
      val iId = c.getColumnIndex(ContactsContract.Contacts._ID)
      val iName = c.getColumnIndex(ContactsContract.Contacts.DISPLAY_NAME)
      val iPhon = c.getColumnIndex(ContactsContract.Contacts.PHONETIC_NAME)
      while (c.moveToNext()) {
        val id = if (iId >= 0) c.getLong(iId) else -1L
        val name = if (iName >= 0) c.getString(iName)?.trim().orEmpty() else ""
        val phonetic = if (iPhon >= 0) c.getString(iPhon)?.trim()?.lowercase().orEmpty() else ""
        if (id >= 0) {
          entries.add(
            Entry(
              id = id,
              name = name,
              phonetic = phonetic,
            ),
          )
        }
      }
    }

    val digits = needle.filter { it.isDigit() }
    val looksLikeNumber = digits.length >= 3 && needle.any { it.isDigit() }
    val cleanNeedle = needle.replace(" ", "").lowercase()

    val matched = linkedMapOf<Long, ContactHit>()
    for (e in entries) {
      val haystack = e.name.lowercase()
      val cleanHaystack = haystack.replace(" ", "")
      val contactName = e.name.ifEmpty { "未命名" }
      val nameMatch = cleanHaystack.contains(cleanNeedle) ||
        (cleanHaystack.isNotEmpty() && cleanNeedle.contains(cleanHaystack)) ||
        (cleanNeedle.length >= 2 && e.phonetic.replace(" ", "").contains(cleanNeedle))
      if (nameMatch && !matched.containsKey(e.id)) {
        matched[e.id] = ContactHit(contactName)
      }
    }

    // For digit needles also match phone numbers directly.
    val numberMatchedIds = if (looksLikeNumber) queryIdsByNumber(digits) else emptySet()
    for (id in numberMatchedIds) {
      if (!matched.containsKey(id)) {
        val entry = entries.firstOrNull { it.id == id }
        matched[id] = ContactHit(entry?.name?.ifEmpty { null } ?: "未命名")
      }
    }

    if (matched.isEmpty()) return emptyList()

    // Hydrate phones/emails/org for the matched contacts only (bounded).
    val ids = matched.keys.toList()
    for (chunk in ids.chunked(200)) {
      hydrate(resolver, chunk, matched)
    }

    return matched.values.take(maxHits)
  }

  private fun queryIdsByNumber(digits: String): Set<Long> {
    val ids = mutableSetOf<Long>()
    if (digits.length < 3) return ids
    val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
    context.contentResolver.query(
      uri,
      arrayOf(ContactsContract.CommonDataKinds.Phone.CONTACT_ID),
      "${ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER} LIKE ? OR ${ContactsContract.CommonDataKinds.Phone.NUMBER} LIKE ?",
      arrayOf("%$digits%", "%$digits%"),
      null,
    )?.use { c ->
      while (c.moveToNext()) {
        ids.add(c.getLong(0))
        if (ids.size >= 50) break
      }
    } ?: return ids
    return ids
  }

  private fun hydrate(resolver: android.content.ContentResolver, ids: List<Long>, matched: MutableMap<Long, ContactHit>) {
    val inClause = ids.joinToString(",") { "?" }
    val args = ids.map { it.toString() }.toTypedArray()

    fun dataQuery(mimeType: String, columns: Array<String>): android.database.Cursor? =
      resolver.query(
        ContactsContract.Data.CONTENT_URI,
        columns,
        "${ContactsContract.Data.MIMETYPE} = ? AND ${ContactsContract.Data.CONTACT_ID} IN ($inClause)",
        arrayOf(mimeType) + args,
        null,
      )

    dataQuery(ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE, arrayOf(
      ContactsContract.Data.CONTACT_ID,
      ContactsContract.CommonDataKinds.Phone.NUMBER,
    ))?.use { c ->
      while (c.moveToNext()) {
        val hit = matched[c.getLong(0)] ?: continue
        val number = c.getString(1)?.trim() ?: continue
        if (number.isNotEmpty() && !hit.phones.contains(number)) hit.phones.add(number)
      }
    }

    dataQuery(ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE, arrayOf(
      ContactsContract.Data.CONTACT_ID,
      ContactsContract.CommonDataKinds.Email.ADDRESS,
    ))?.use { c ->
      while (c.moveToNext()) {
        val hit = matched[c.getLong(0)] ?: continue
        val address = c.getString(1)?.trim() ?: continue
        if (address.isNotEmpty() && !hit.emails.contains(address)) hit.emails.add(address)
      }
    }

    dataQuery(ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE, arrayOf(
      ContactsContract.Data.CONTACT_ID,
      ContactsContract.CommonDataKinds.Organization.COMPANY,
    ))?.use { c ->
      while (c.moveToNext()) {
        val hit = matched[c.getLong(0)] ?: continue
        if (hit.org.isNullOrEmpty()) {
          val company = c.getString(1)?.trim().orEmpty()
          if (company.isNotEmpty()) hit.org = company
        }
      }
    }
  }

  /** contacts.add has no LLM-facing tool schema today; explicit no-op for protocol parity. */
  suspend fun handleContactsAdd(p: String?): GatewaySession.InvokeResult =
    GatewaySession.InvokeResult.error(code = "NOT_IMPLEMENTED", message = "NOT_IMPLEMENTED: contacts.add is not supported yet")

  private fun error(code: String, message: String): GatewaySession.InvokeResult =
    GatewaySession.InvokeResult.error(code = code, message = message)
}

/**
 * Calendar lookup (calendar.events). Reads instances in a window (default
 * today ±7 days; a title query searches all events, bounded to ±90 days).
 * Accepts both the hiclaw schema ({days}) and the bridge schema
 * ({fromTs,toTs,titleQuery,limit}). Uses READ_CALENDAR.
 */
class CalendarHandler(private val context: Context) {

  private val json = Json { encodeDefaults = false }

  suspend fun handleCalendarEvents(p: String?): GatewaySession.InvokeResult {
    var fromTs: Long? = null
    var toTs: Long? = null
    var titleQuery: String? = null
    var limit = 10
    var days: Long? = null
    if (p != null) {
      try {
        val params = json.parseToJsonElement(p) as? JsonObject ?: JsonObject(emptyMap())
        fromTs = (params["fromTs"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toLongOrNull()
        toTs = (params["toTs"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toLongOrNull()
        titleQuery = (params["titleQuery"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim()
        limit = (params["limit"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toIntOrNull() ?: 10
        days = (params["days"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toLongOrNull()
      } catch (_: Throwable) {
        return error("INVALID_REQUEST", "calendar.events params must be valid JSON")
      }
    }

    if (!hasReadCalendar()) {
      return error("CALENDAR_QUERY_FAILED", "日历权限未授予 (READ_CALENDAR)")
    }

    val now = System.currentTimeMillis()
    val query = titleQuery.orEmpty()
    var effectiveFrom = fromTs
    var effectiveTo = toTs
    if (effectiveFrom == null && effectiveTo == null && days != null && days > 0) {
      effectiveFrom = startOfDay(now)
      effectiveTo = startOfDay(now) + days * DAY_MS
    }
    if (effectiveFrom == null) effectiveFrom = now - 7 * DAY_MS
    if (effectiveTo == null) effectiveTo = now + 7 * DAY_MS

    val windowFrom = if (query.isNotEmpty()) now - 90 * DAY_MS else effectiveFrom
    val windowTo = if (query.isNotEmpty()) now + 90 * DAY_MS else effectiveTo
    val maxHits = limit.coerceIn(1, 20)

    return try {
      val hits = mutableListOf<EventHit>()
      val projection = arrayOf(
        CalendarContract.Instances.TITLE,
        CalendarContract.Instances.BEGIN,
        CalendarContract.Instances.END,
        CalendarContract.Instances.ALL_DAY,
        CalendarContract.Instances.EVENT_LOCATION,
      )
      val cursor = if (query.isEmpty()) {
        context.contentResolver.query(
          CalendarContract.Instances.CONTENT_URI, projection,
          "${CalendarContract.Instances.BEGIN} >= ? AND ${CalendarContract.Instances.BEGIN} <= ?",
          arrayOf(windowFrom.toString(), windowTo.toString()),
          "${CalendarContract.Instances.BEGIN} ASC",
        )
      } else {
        context.contentResolver.query(
          CalendarContract.Instances.CONTENT_SEARCH_URI.buildUpon()
            .appendPath(query)
            .appendQueryParameter(CalendarContract.Instances.BEGIN, windowFrom.toString())
            .appendQueryParameter(CalendarContract.Instances.END, windowTo.toString())
            .build(),
          projection, null, null,
          "${CalendarContract.Instances.BEGIN} ASC",
        )
      }
      cursor?.use { c ->
        val iTitle = c.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
        val iBegin = c.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
        val iEnd = c.getColumnIndexOrThrow(CalendarContract.Instances.END)
        val iAllDay = c.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY)
        val iLoc = c.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_LOCATION)
        while (c.moveToNext() && hits.size < maxHits) {
          val begin = c.getLong(iBegin)
          val end = c.getLong(iEnd)
          if (begin > windowTo || end < windowFrom) continue
          val location = c.getString(iLoc)?.trim().orEmpty()
          hits.add(
            EventHit(
              title = c.getString(iTitle)?.trim()?.ifEmpty { null } ?: "未命名日程",
              startTs = begin,
              endTs = end,
              allDay = c.getInt(iAllDay) != 0,
              location = location.ifEmpty { null },
            ),
          )
        }
      }
      hits.sortBy { it.startTs }
      val payload = buildJsonObject {
        put("events", buildJsonArray {
          for (hit in hits) {
            add(buildJsonObject {
              put("title", hit.title)
              put("startTs", hit.startTs)
              put("endTs", hit.endTs)
              put("allDay", hit.allDay)
              if (hit.location != null) put("location", hit.location)
            })
          }
        })
        put("total", hits.size)
      }
      GatewaySession.InvokeResult.ok(payload.toString())
    } catch (e: SecurityException) {
      error("CALENDAR_QUERY_FAILED", "日历权限未授予 (READ_CALENDAR)")
    } catch (e: Throwable) {
      Log.w("CalendarHandler", "calendar.events failed", e)
      error("CALENDAR_QUERY_FAILED", e.message ?: "日历查询失败")
    }
  }

  private fun hasReadCalendar(): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

  private fun startOfDay(now: Long): Long {
    val cal = java.util.Calendar.getInstance()
    cal.timeInMillis = now
    cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
    cal.set(java.util.Calendar.MINUTE, 0)
    cal.set(java.util.Calendar.SECOND, 0)
    cal.set(java.util.Calendar.MILLISECOND, 0)
    return cal.timeInMillis
  }

  /** calendar.add has no LLM-facing tool schema today; explicit no-op for protocol parity. */
  suspend fun handleCalendarAdd(p: String?): GatewaySession.InvokeResult =
    GatewaySession.InvokeResult.error(code = "NOT_IMPLEMENTED", message = "NOT_IMPLEMENTED: calendar.add is not supported yet")

  private fun error(code: String, message: String): GatewaySession.InvokeResult =
    GatewaySession.InvokeResult.error(code = code, message = message)
}
