package ai.axiomaster.bonio.remote.memory

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Charging-triggered incremental memory sync. Listens to
 * ACTION_BATTERY_CHANGED and calls the backend's memory.incremental_sync RPC
 * when the device is plugged in (reason=plugged_in) or periodically while
 * charging (reason=periodic_charging, ≥5 min apart). Ported from harmonyos
 * ChargingTriggeredScheduler.ets (30s poll → battery broadcast push).
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
      if (intent.action != Intent.ACTION_BATTERY_CHANGED) return
      val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
      val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
      val soc = if (level >= 0 && scale > 0) level * 100 / scale else -1
      val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
      val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
      val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
        status == BatteryManager.BATTERY_STATUS_FULL ||
        plugged != 0

      if (firstEvent) {
        // The sticky broadcast replays current state on register; record it
        // without triggering so reconnecting while charged doesn't fire.
        firstEvent = false
        wasCharging = isCharging
        return
      }

      val now = System.currentTimeMillis()
      val reason = when {
        isCharging && !wasCharging -> "plugged_in"
        isCharging && now - lastTriggerAt >= COOLDOWN_MS -> "periodic_charging"
        else -> null
      }
      wasCharging = isCharging
      if (reason == null) return
      if (!isConnected()) {
        Log.d(TAG, "skip incremental_sync ($reason): backend not connected")
        return
      }
      lastTriggerAt = now
      scope.launch {
        val ok = sync(reason, soc, now)
        Log.i(TAG, "incremental_sync reason=$reason soc=$soc ok=$ok")
      }
    }
  }

  fun start() {
    if (registered) return
    context.registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    registered = true
  }

  fun stop() {
    if (!registered) return
    runCatching { context.unregisterReceiver(receiver) }
    registered = false
    firstEvent = true
  }

  companion object {
    private const val TAG = "ChargingTrigger"
    private const val COOLDOWN_MS = 5 * 60 * 1000L
  }
}
