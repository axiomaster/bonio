package ai.axiomaster.boji.avatar

import ai.axiomaster.boji.ai.AgentState

data class AvatarState(
    val activity: AgentState = AgentState.Idle,
    val motion: MotionState = MotionState.Stationary,
    val action: AvatarAction = AvatarAction.None,
    val transition: AvatarTransition? = null,
    val position: AvatarPosition = AvatarPosition(0f, 100f),
    val targetPosition: AvatarPosition? = null,
)
