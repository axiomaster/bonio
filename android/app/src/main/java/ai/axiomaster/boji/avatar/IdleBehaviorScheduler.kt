package ai.axiomaster.boji.avatar

import ai.axiomaster.boji.ai.AgentState
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlin.random.Random

class IdleBehaviorScheduler(
    private val controller: AvatarController,
    private val enabled: StateFlow<Boolean>,
    private val scope: CoroutineScope,
) {
    companion object {
        private const val TAG = "IdleBehavior"
        private const val MIN_IDLE_BEFORE_WANDER_MS = 8_000L
        private const val MAX_IDLE_BEFORE_WANDER_MS = 20_000L
        private const val WANDER_RADIUS_PX = 300f
    }

    private var schedulerJob: Job? = null

    fun start() {
        stop()
        schedulerJob = scope.launch {
            while (true) {
                val waitMs = Random.nextLong(MIN_IDLE_BEFORE_WANDER_MS, MAX_IDLE_BEFORE_WANDER_MS)
                delay(waitMs)

                if (!enabled.value) continue

                val state = controller.avatarState.value
                val canWander = (state.activity == AgentState.Idle || state.activity == AgentState.Bored)
                    && state.motion == MotionState.Stationary
                    && state.action == AvatarAction.None

                if (!canWander) continue

                val current = state.position
                val dx = Random.nextFloat() * WANDER_RADIUS_PX * 2 - WANDER_RADIUS_PX
                val dy = Random.nextFloat() * WANDER_RADIUS_PX * 2 - WANDER_RADIUS_PX
                val targetX = current.x + dx
                val targetY = current.y + dy

                Log.d(TAG, "Wandering to ($targetX, $targetY)")
                controller.walkTo(targetX, targetY)
            }
        }
    }

    fun stop() {
        schedulerJob?.cancel()
        schedulerJob = null
    }
}
