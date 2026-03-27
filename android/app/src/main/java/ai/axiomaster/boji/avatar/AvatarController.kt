package ai.axiomaster.boji.avatar

import android.animation.ValueAnimator
import android.util.DisplayMetrics
import android.util.Log
import android.view.animation.AccelerateDecelerateInterpolator
import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.ai.AgentStateManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AvatarController(
    val stateManager: AgentStateManager,
    private val scope: CoroutineScope,
) {
    companion object {
        private const val TAG = "AvatarController"
        private const val WALK_SPEED_PX_PER_SEC = 600f
        private const val RUN_SPEED_PX_PER_SEC = 1200f
        private const val RUN_DISTANCE_THRESHOLD = 800f
        private const val ACTION_DISPLAY_DURATION_MS = 800L
        private const val BORED_TIMEOUT_MS = 30_000L
        private const val SLEEPING_TIMEOUT_MS = 120_000L
        private const val HAPPY_DISPLAY_MS = 3_000L
        private const val CONFUSED_DISPLAY_MS = 3_000L
        private const val ANGRY_DISPLAY_MS = 3_000L
    }

    private val _avatarState = MutableStateFlow(AvatarState())
    val avatarState: StateFlow<AvatarState> = _avatarState.asStateFlow()

    private var moveAnimator: ValueAnimator? = null
    private var actionClearJob: Job? = null
    private var stateObserverJob: Job? = null
    private var idleTimerJob: Job? = null
    private var tempStateClearJob: Job? = null

    private var screenWidth = 1080
    private var screenHeight = 2400

    /**
     * Callback invoked when a transition animation should be played.
     * The FloatingWindowService sets this to play the one-shot Lottie then loop the stable state.
     */
    var onTransition: ((AvatarTransition) -> Unit)? = null

    init {
        stateObserverJob = scope.launch {
            var previousActivity = AgentState.Idle
            stateManager.currentState.collect { agentState ->
                val current = _avatarState.value
                if (current.activity != agentState) {
                    val transition = AvatarTransition.between(previousActivity, agentState)
                    if (transition != null) {
                        _avatarState.value = current.copy(
                            activity = agentState,
                            transition = transition,
                        )
                        onTransition?.invoke(transition)
                    } else {
                        _avatarState.value = current.copy(activity = agentState, transition = null)
                    }
                    previousActivity = agentState
                    restartIdleTimer(agentState)
                }
            }
        }
    }

    fun clearTransition() {
        val current = _avatarState.value
        if (current.transition != null) {
            _avatarState.value = current.copy(transition = null)
        }
    }

    // ── Idle escalation: Idle -> Bored -> Sleeping ──

    private fun restartIdleTimer(state: AgentState) {
        idleTimerJob?.cancel()
        if (state != AgentState.Idle && state != AgentState.Bored) return

        idleTimerJob = scope.launch {
            if (state == AgentState.Idle) {
                delay(BORED_TIMEOUT_MS)
                if (_avatarState.value.activity == AgentState.Idle
                    && _avatarState.value.motion == MotionState.Stationary
                ) {
                    stateManager.transitionTo(AgentState.Bored)
                }
            }
            if (_avatarState.value.activity == AgentState.Bored) {
                delay(SLEEPING_TIMEOUT_MS - BORED_TIMEOUT_MS)
                if (_avatarState.value.activity == AgentState.Bored
                    && _avatarState.value.motion == MotionState.Stationary
                ) {
                    stateManager.transitionTo(AgentState.Sleeping)
                }
            }
        }
    }

    /**
     * Wake the avatar from Bored/Sleeping back to Idle when user interacts.
     */
    private fun wakeIfDormant() {
        val current = _avatarState.value.activity
        if (current == AgentState.Bored || current == AgentState.Sleeping) {
            stateManager.transitionTo(AgentState.Idle)
        }
    }

    fun updateScreenMetrics(metrics: DisplayMetrics) {
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
    }

    // ── Activity state ──

    fun setActivity(state: AgentState) {
        stateManager.transitionTo(state)
    }

    /**
     * Show a temporary emotional state (Happy, Confused, Angry) that auto-reverts to Idle.
     */
    fun showTemporaryState(state: AgentState) {
        tempStateClearJob?.cancel()
        stateManager.transitionTo(state)
        val duration = when (state) {
            AgentState.Happy -> HAPPY_DISPLAY_MS
            AgentState.Confused -> CONFUSED_DISPLAY_MS
            AgentState.Angry -> ANGRY_DISPLAY_MS
            else -> 2_000L
        }
        tempStateClearJob = scope.launch {
            delay(duration)
            if (_avatarState.value.activity == state) {
                stateManager.transitionTo(AgentState.Idle)
            }
        }
    }

    fun setBubble(text: String?) = stateManager.setBubble(text)
    fun clearBubble() = stateManager.clearBubble()

    // ── Motion ──

    fun walkTo(x: Float, y: Float) {
        wakeIfDormant()
        moveTo(x, y, forceRun = false)
    }

    fun runTo(x: Float, y: Float) {
        wakeIfDormant()
        moveTo(x, y, forceRun = true)
    }

    private fun moveTo(x: Float, y: Float, forceRun: Boolean) {
        moveAnimator?.cancel()

        val clamped = clampPosition(x, y)
        val current = _avatarState.value.position
        val distance = current.distanceTo(clamped)

        if (distance < 5f) {
            _avatarState.value = _avatarState.value.copy(
                motion = MotionState.Stationary,
                targetPosition = null,
            )
            return
        }

        val isRunning = forceRun || distance > RUN_DISTANCE_THRESHOLD
        val speed = if (isRunning) RUN_SPEED_PX_PER_SEC else WALK_SPEED_PX_PER_SEC
        val durationMs = ((distance / speed) * 1000f).toLong().coerceIn(100, 5000)

        _avatarState.value = _avatarState.value.copy(
            motion = if (isRunning) MotionState.Running else MotionState.Walking,
            targetPosition = clamped,
        )

        val startX = current.x
        val startY = current.y

        moveAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { anim ->
                val fraction = anim.animatedValue as Float
                val nx = startX + (clamped.x - startX) * fraction
                val ny = startY + (clamped.y - startY) * fraction
                _avatarState.value = _avatarState.value.copy(
                    position = AvatarPosition(nx, ny),
                )
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    _avatarState.value = _avatarState.value.copy(
                        motion = MotionState.Stationary,
                        position = clamped,
                        targetPosition = null,
                    )
                }

                override fun onAnimationCancel(animation: android.animation.Animator) {
                    _avatarState.value = _avatarState.value.copy(
                        motion = MotionState.Stationary,
                        targetPosition = null,
                    )
                }
            })
            start()
        }
    }

    // ── Drag ──

    fun dragTo(x: Float, y: Float) {
        wakeIfDormant()
        moveAnimator?.cancel()
        val clamped = clampPosition(x, y)
        _avatarState.value = _avatarState.value.copy(
            motion = MotionState.Dragging,
            position = clamped,
            targetPosition = null,
        )
    }

    fun endDrag() {
        _avatarState.value = _avatarState.value.copy(
            motion = MotionState.Stationary,
        )
    }

    // ── GUI agent actions ──

    fun performAction(actionType: String, x: Float? = null, y: Float? = null) {
        val action = AvatarAction.fromAgentAction(actionType)
        if (action == AvatarAction.None) return

        Log.d(TAG, "performAction: $actionType -> $action at ($x, $y)")
        wakeIfDormant()

        if (x != null && y != null) {
            val current = _avatarState.value.position
            val target = clampPosition(x, y)
            val distance = current.distanceTo(target)

            if (distance > 5f) {
                scope.launch {
                    walkTo(target.x, target.y)
                    awaitStationary()
                    applyAction(action)
                }
            } else {
                applyAction(action)
            }
        } else {
            applyAction(action)
        }
    }

    private fun applyAction(action: AvatarAction) {
        actionClearJob?.cancel()
        _avatarState.value = _avatarState.value.copy(action = action)

        actionClearJob = scope.launch {
            delay(ACTION_DISPLAY_DURATION_MS)
            clearAction()
        }
    }

    fun clearAction() {
        actionClearJob?.cancel()
        _avatarState.value = _avatarState.value.copy(action = AvatarAction.None)
    }

    private suspend fun awaitStationary() {
        while (_avatarState.value.motion != MotionState.Stationary) {
            delay(50)
        }
    }

    // ── Position helpers ──

    fun setPosition(x: Float, y: Float) {
        val clamped = clampPosition(x, y)
        _avatarState.value = _avatarState.value.copy(position = clamped)
    }

    private fun clampPosition(x: Float, y: Float): AvatarPosition {
        return AvatarPosition(
            x.coerceIn(0f, screenWidth.toFloat()),
            y.coerceIn(0f, screenHeight.toFloat()),
        )
    }

    fun destroy() {
        stateObserverJob?.cancel()
        stateObserverJob = null
        idleTimerJob?.cancel()
        idleTimerJob = null
        tempStateClearJob?.cancel()
        tempStateClearJob = null
        moveAnimator?.cancel()
        moveAnimator = null
        actionClearJob?.cancel()
        actionClearJob = null
    }
}
