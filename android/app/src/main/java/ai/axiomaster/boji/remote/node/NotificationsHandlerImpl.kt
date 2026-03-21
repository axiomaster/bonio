package ai.axiomaster.boji.remote.node

import android.content.Context
import ai.axiomaster.boji.remote.gateway.GatewaySession
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class NotificationsHandlerImpl(private val context: Context) {

  suspend fun handleNotificationsList(p: String?): GatewaySession.InvokeResult {
    val snapshot = DeviceNotificationListenerService.snapshot(context)

    val json = buildJsonObject {
      put("enabled", snapshot.enabled)
      put("connected", snapshot.connected)
      put(
        "notifications",
        JsonArray(snapshot.notifications.map { it.toJsonObject() }),
      )
      put("count", snapshot.notifications.size)
    }
    return GatewaySession.InvokeResult.ok(json.toString())
  }

  suspend fun handleNotificationsActions(p: String?): GatewaySession.InvokeResult {
    val params = parseJsonParamsObject(p)
    val key = parseJsonString(params, "key")
      ?: return GatewaySession.InvokeResult.error(
        code = "INVALID_REQUEST",
        message = "INVALID_REQUEST: key required",
      )

    val kindStr = parseJsonString(params, "action") ?: "open"
    val kind = when (kindStr.lowercase()) {
      "open" -> NotificationActionKind.Open
      "dismiss" -> NotificationActionKind.Dismiss
      "reply" -> NotificationActionKind.Reply
      else -> return GatewaySession.InvokeResult.error(
        code = "INVALID_REQUEST",
        message = "INVALID_REQUEST: action must be open, dismiss, or reply",
      )
    }

    val replyText = parseJsonString(params, "replyText")

    val request = NotificationActionRequest(
      key = key,
      kind = kind,
      replyText = replyText,
    )

    val result = DeviceNotificationListenerService.executeAction(context, request)
    if (!result.ok) {
      return GatewaySession.InvokeResult.error(
        code = result.code ?: "ACTION_FAILED",
        message = result.message ?: "ACTION_FAILED: unknown error",
      )
    }

    return GatewaySession.InvokeResult.ok(
      buildJsonObject { put("ok", true) }.toString()
    )
  }
}
