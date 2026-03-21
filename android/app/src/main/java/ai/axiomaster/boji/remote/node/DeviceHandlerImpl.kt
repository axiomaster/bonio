package ai.axiomaster.boji.remote.node

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import ai.axiomaster.boji.remote.gateway.GatewaySession
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class DeviceHandlerImpl(private val context: Context) {

  suspend fun handleDeviceStatus(p: String?): GatewaySession.InvokeResult {
    val battery = batteryInfo()
    val network = networkInfo()
    val storage = storageInfo()
    val mem = memoryInfo()

    val json = buildJsonObject {
      put("batteryLevel", battery.first)
      put("batteryCharging", battery.second)
      put("networkType", network.first)
      put("networkConnected", network.second)
      put("storageTotal", storage.first)
      put("storageFree", storage.second)
      put("memoryTotal", mem.first)
      put("memoryFree", mem.second)
    }
    return GatewaySession.InvokeResult.ok(json.toString())
  }

  suspend fun handleDeviceInfo(p: String?): GatewaySession.InvokeResult {
    val json = buildJsonObject {
      put("manufacturer", Build.MANUFACTURER)
      put("model", Build.MODEL)
      put("brand", Build.BRAND)
      put("device", Build.DEVICE)
      put("product", Build.PRODUCT)
      put("osVersion", Build.VERSION.RELEASE)
      put("sdkInt", Build.VERSION.SDK_INT)
      put("board", Build.BOARD)
      put("hardware", Build.HARDWARE)
      put("display", Build.DISPLAY)
      put("fingerprint", Build.FINGERPRINT)
    }
    return GatewaySession.InvokeResult.ok(json.toString())
  }

  suspend fun handleDevicePermissions(p: String?): GatewaySession.InvokeResult {
    val pm = context.packageManager
    val granted = mutableListOf<String>()
    val denied = mutableListOf<String>()

    val checks = listOf(
      android.Manifest.permission.CAMERA,
      android.Manifest.permission.RECORD_AUDIO,
      android.Manifest.permission.ACCESS_FINE_LOCATION,
      android.Manifest.permission.ACCESS_COARSE_LOCATION,
      android.Manifest.permission.SEND_SMS,
      android.Manifest.permission.READ_CONTACTS,
      android.Manifest.permission.WRITE_CONTACTS,
      android.Manifest.permission.READ_CALENDAR,
      android.Manifest.permission.WRITE_CALENDAR,
      android.Manifest.permission.ACTIVITY_RECOGNITION,
      android.Manifest.permission.POST_NOTIFICATIONS,
    )

    for (perm in checks) {
      if (androidx.core.content.ContextCompat.checkSelfPermission(context, perm)
        == android.content.pm.PackageManager.PERMISSION_GRANTED
      ) {
        granted.add(perm.substringAfterLast('.'))
      } else {
        denied.add(perm.substringAfterLast('.'))
      }
    }

    val notificationListenerEnabled =
      DeviceNotificationListenerService.isAccessEnabled(context)
    val overlayEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      android.provider.Settings.canDrawOverlays(context)
    } else true

    val json = buildJsonObject {
      put("granted", kotlinx.serialization.json.JsonArray(granted.map { kotlinx.serialization.json.JsonPrimitive(it) }))
      put("denied", kotlinx.serialization.json.JsonArray(denied.map { kotlinx.serialization.json.JsonPrimitive(it) }))
      put("notificationListener", notificationListenerEnabled)
      put("overlay", overlayEnabled)
    }
    return GatewaySession.InvokeResult.ok(json.toString())
  }

  suspend fun handleDeviceHealth(p: String?): GatewaySession.InvokeResult {
    val battery = batteryInfo()
    val mem = memoryInfo()
    val storage = storageInfo()

    val healthy = battery.first > 5 && storage.second > 100L * 1024 * 1024

    val json = buildJsonObject {
      put("healthy", healthy)
      put("batteryLevel", battery.first)
      put("batteryCharging", battery.second)
      put("memoryFree", mem.second)
      put("storageFree", storage.second)
    }
    return GatewaySession.InvokeResult.ok(json.toString())
  }

  private fun batteryInfo(): Pair<Int, Boolean> {
    val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
    val batteryIntent = context.registerReceiver(null, filter)
    val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
    val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
    val pct = if (scale > 0 && level >= 0) (level * 100) / scale else -1
    val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
    val charging = status == BatteryManager.BATTERY_STATUS_CHARGING
        || status == BatteryManager.BATTERY_STATUS_FULL
    return pct to charging
  }

  private fun networkInfo(): Pair<String, Boolean> {
    val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
      ?: return "unknown" to false
    val net = cm.activeNetwork ?: return "none" to false
    val caps = cm.getNetworkCapabilities(net) ?: return "none" to false
    val type = when {
      caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
      else -> "other"
    }
    return type to caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
  }

  @Suppress("DEPRECATION")
  private fun storageInfo(): Pair<Long, Long> {
    return try {
      val stat = StatFs(Environment.getDataDirectory().path)
      val total = stat.totalBytes
      val free = stat.availableBytes
      total to free
    } catch (_: Throwable) {
      0L to 0L
    }
  }

  private fun memoryInfo(): Pair<Long, Long> {
    val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
      ?: return 0L to 0L
    val mi = android.app.ActivityManager.MemoryInfo()
    am.getMemoryInfo(mi)
    return mi.totalMem to mi.availMem
  }
}
