package ai.axiomaster.bonio.remote.memory

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import ai.axiomaster.bonio.util.AppLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Charging-triggered incremental memory sync. Listens to
 * ACTION_BATTERY_CHANGED / ACTION_POWER_CONNECTED and calls the backend's memory.incremental_sync RPC
 * when the device is plugged in (reason=plugged_in) or periodically while
 * charging (reason=periodic_charging, >=5 min apart). Ported from harmonyos
 * ChargingTriggeredScheduler.ets (30s poll -> battery broadcast push).
 */
class ChargingTriggeredSync(
  private val context: Context,
  private val scope: CoroutineScope,
  private val isConnected: () -> Boolean,
  private val sync: suspend (reason: String, soc: Int, timestamp: Long) -> Boolean,
) {
  private var registered = false
  private var firstEvent = true
  private var wasCharging = false
  private var lastTriggerAt = 0L

  private val receiver = object : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
      val action = intent.action ?: return
      val batteryIntent = if (action == Intent.ACTION_BATTERY_CHANGED) {
        intent
      } else {
        context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
      } ?: return

      val level = batteryIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
      val scale = batteryIntent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
      val soc = if (level >= 0 && scale > 0) level * 100 / scale else -1
      val status = batteryIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
      val plugged = batteryIntent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
      val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
        status == BatteryManager.BATTERY_STATUS_FULL ||
        plugged != 0 ||
        action == Intent.ACTION_POWER_CONNECTED

      val now = System.currentTimeMillis()
      if (firstEvent) {
        firstEvent = false
        wasCharging = isCharging
        AppLogger.i(TAG, "initial battery state: isCharging=$isCharging soc=$soc%")
        if (isCharging) {
          triggerSync("initial_charging", soc, now)
        }
        return
      }

      val reason = when {
        isCharging && !wasCharging -> "plugged_in"
        isCharging && (now - lastTriggerAt >= COOLDOWN_MS) -> "periodic_charging"
        else -> null
      }
      wasCharging = isCharging
      if (reason != null) {
        triggerSync(reason, soc, now)
      }
    }
  }

  private fun triggerSync(reason: String, soc: Int, now: Long) {
    if (!isConnected()) {
      AppLogger.d(TAG, "skip incremental_sync ($reason): backend not connected")
      return
    }
    lastTriggerAt = now
    AppLogger.i(TAG, "charging detected ($reason, soc=$soc%); triggering incremental sync & vectorization")
    scope.launch {
      val ok = sync(reason, soc, now)
      AppLogger.i(TAG, "incremental_sync reason=$reason soc=$soc ok=$ok")
    }
  }

  fun start() {
    if (registered) return
    val filter = IntentFilter().apply {
      addAction(Intent.ACTION_BATTERY_CHANGED)
      addAction(Intent.ACTION_POWER_CONNECTED)
      addAction(Intent.ACTION_POWER_DISCONNECTED)
    }
    context.registerReceiver(receiver, filter)
    registered = true
    AppLogger.i(TAG, "ChargingTriggeredSync registered and started")
  }

  fun stop() {
    if (!registered) return
    runCatching { context.unregisterReceiver(receiver) }
    registered = false
    firstEvent = true
    AppLogger.i(TAG, "ChargingTriggeredSync stopped")
  }

  companion object {
    private const val TAG = "ChargingTrigger"
    private const val COOLDOWN_MS = 5 * 60 * 1000L
  }
}
