package ai.axiomaster.boji.avatar

import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.remote.chat.SystemTtsManager
import android.content.Context
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Calendar

class HealthNagScheduler(
    private val context: Context,
    private val controller: AvatarController,
    private val enabled: StateFlow<Boolean>,
    private val scope: CoroutineScope,
    private val tts: SystemTtsManager? = null,
) {
    private var schedulerJob: Job? = null
    private var lastNagTime = 0L
    private var nagLevel = 0

    private var lastCheckWallClock = System.currentTimeMillis()
    private var screenOnAccumMs = 0L

    private val lateNightStartHour = 23
    private val lateNightEndHour = 6
    private val maxContinuousUseMs = 2 * 60 * 60 * 1000L
    private val nagCooldownMs = 15 * 60 * 1000L
    private val checkIntervalMs = 60_000L

    companion object {
        private const val TAG = "HealthNag"
    }

    fun start() {
        stop()
        lastCheckWallClock = System.currentTimeMillis()
        screenOnAccumMs = 0L
        schedulerJob = scope.launch {
            while (true) {
                delay(checkIntervalMs)
                if (!enabled.value) {
                    nagLevel = 0
                    continue
                }
                updateScreenOnStreak()
                checkAndNag()
            }
        }
    }

    fun stop() {
        schedulerJob?.cancel()
        schedulerJob = null
    }

    private fun updateScreenOnStreak() {
        val now = System.currentTimeMillis()
        val delta = (now - lastCheckWallClock).coerceAtLeast(0L)
        lastCheckWallClock = now

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (powerManager != null && powerManager.isInteractive) {
            screenOnAccumMs += delta
        } else {
            screenOnAccumMs = 0L
        }
    }

    private suspend fun checkAndNag() {
        val currentState = controller.avatarState.value.activity
        if (currentState != AgentState.Idle &&
            currentState != AgentState.Bored &&
            currentState != AgentState.Sleeping
        ) {
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastNagTime < nagCooldownMs) return

        val shouldNag = isLateNight() || hasContinuousScreenOnUsage()
        if (!shouldNag) {
            nagLevel = 0
            return
        }

        nagLevel++
        lastNagTime = now

        if (nagLevel <= 1) {
            performGentleNag()
        } else {
            performStrongNag()
        }
    }

    private fun isLateNight(): Boolean {
        val cal = Calendar.getInstance()
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        return hour >= lateNightStartHour || hour < lateNightEndHour
    }

    private fun hasContinuousScreenOnUsage(): Boolean {
        if (!isLateNight()) return false
        return screenOnAccumMs >= maxContinuousUseMs
    }

    private suspend fun performGentleNag() {
        Log.i(TAG, "Gentle nag: it's late, user should rest")
        withContext(Dispatchers.Main) {
            controller.setActivity(AgentState.Sleeping)
            controller.setBubble("\u4e3b\u4eba\uff0c\u597d\u665a\u4e86\u559c\u2026")
        }
        delay(5000)
        withContext(Dispatchers.Main) {
            controller.clearBubble()
        }
    }

    private suspend fun performStrongNag() {
        Log.i(TAG, "Strong nag: walking to center and complaining")
        withContext(Dispatchers.Main) {
            val screenW = controller.getScreenWidth().toFloat()
            val screenH = controller.getScreenHeight().toFloat()
            val centerX = screenW / 2f - 90f
            val centerY = screenH / 2f - 90f
            controller.runTo(centerX, centerY)
        }

        awaitAvatarStationary()

        withContext(Dispatchers.Main) {
            controller.setActivity(AgentState.Angry)
            controller.setBubble(
                "\u8fd8\u4e0d\u7761\u89c9\uff01BoJi\u7684\u6bdb\u90fd\u8981\u6389\u5149\u4e86\uff01\u5feb\u5173\u6389\u624b\u673a\u7761\u89c9\u559c\uff01"
            )
            tts?.speak("\u8fd8\u4e0d\u7761\u89c9\uff01\u5feb\u5173\u6389\u624b\u673a\u7761\u89c9\u559c\uff01")
        }

        delay(5000)

        withContext(Dispatchers.Main) {
            controller.setActivity(AgentState.Confused)
            controller.setBubble("\u5524\u2026")
        }

        delay(2000)

        withContext(Dispatchers.Main) {
            controller.clearBubble()
            val density = controller.getDensity()
            val marginX = 20f * density
            val marginY = controller.getScreenHeight().toFloat() * 0.7f
            controller.walkTo(marginX, marginY)
        }

        awaitAvatarStationary()

        delay(500)

        withContext(Dispatchers.Main) {
            controller.setActivity(AgentState.Sleeping)
        }
    }

    private suspend fun awaitAvatarStationary() {
        while (controller.avatarState.value.motion != MotionState.Stationary) {
            delay(50)
        }
    }
}
