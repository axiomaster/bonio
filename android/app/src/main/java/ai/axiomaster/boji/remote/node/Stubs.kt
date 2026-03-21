package ai.axiomaster.boji.remote.node

import ai.axiomaster.boji.remote.gateway.GatewaySession

class SystemHandler { suspend fun handleSystemNotify(p: String?) = GatewaySession.InvokeResult.ok(null) }
class PhotosHandler { suspend fun handlePhotosLatest(p: String?) = GatewaySession.InvokeResult.ok(null) }
class ContactsHandler { suspend fun handleContactsSearch(p: String?) = GatewaySession.InvokeResult.ok(null); suspend fun handleContactsAdd(p: String?) = GatewaySession.InvokeResult.ok(null) }
class CalendarHandler { suspend fun handleCalendarEvents(p: String?) = GatewaySession.InvokeResult.ok(null); suspend fun handleCalendarAdd(p: String?) = GatewaySession.InvokeResult.ok(null) }
class MotionHandler { suspend fun handleMotionActivity(p: String?) = GatewaySession.InvokeResult.ok(null); suspend fun handleMotionPedometer(p: String?) = GatewaySession.InvokeResult.ok(null) }
class SmsHandler { suspend fun handleSmsSend(p: String?) = GatewaySession.InvokeResult.ok(null) }
class DebugHandler { suspend fun handleEd25519() = GatewaySession.InvokeResult.ok(null); suspend fun handleLogs() = GatewaySession.InvokeResult.ok(null) }
class AppUpdateHandler { suspend fun handleUpdate(p: String?) = GatewaySession.InvokeResult.ok(null) }
