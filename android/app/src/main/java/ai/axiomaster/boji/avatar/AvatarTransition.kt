package ai.axiomaster.boji.avatar

import ai.axiomaster.boji.ai.AgentState

/**
 * One-shot transition animations played between stable states.
 * After the transition completes, the avatar loops the target stable state.
 */
enum class AvatarTransition(val key: String) {
    Appear("appear"),
    Disappear("disappear"),
    IdleToListening("idle_to_listening"),
    ListeningToThinking("listening_to_thinking"),
    ThinkingToSpeaking("thinking_to_speaking"),
    SpeakingToIdle("speaking_to_idle"),
    IdleToWorking("idle_to_working"),
    WorkingToIdle("working_to_idle"),
    IdleToBored("idle_to_bored"),
    BoredToIdle("bored_to_idle"),
    IdleToSleeping("idle_to_sleeping"),
    SleepingToIdle("sleeping_to_idle"),
    StartDrag("startdrag"),
    EndDrag("enddrag"),
    ErrorShake("error_shake");

    companion object {
        /**
         * Determine the transition to play when activity changes from [from] to [to].
         * Returns null if no specific transition is defined for this pair.
         */
        fun between(from: AgentState, to: AgentState): AvatarTransition? = when {
            from == AgentState.Idle && to == AgentState.Listening -> IdleToListening
            from == AgentState.Listening && to == AgentState.Thinking -> ListeningToThinking
            from == AgentState.Thinking && to == AgentState.Speaking -> ThinkingToSpeaking
            from == AgentState.Speaking && to == AgentState.Idle -> SpeakingToIdle
            from == AgentState.Idle && to == AgentState.Working -> IdleToWorking
            from == AgentState.Working && to == AgentState.Idle -> WorkingToIdle
            from == AgentState.Idle && to == AgentState.Bored -> IdleToBored
            from == AgentState.Bored && to == AgentState.Idle -> BoredToIdle
            from == AgentState.Idle && to == AgentState.Sleeping -> IdleToSleeping
            from == AgentState.Bored && to == AgentState.Sleeping -> IdleToSleeping
            from == AgentState.Sleeping && to == AgentState.Idle -> SleepingToIdle
            from == AgentState.Confused && to == AgentState.Idle -> SpeakingToIdle
            from == AgentState.Happy && to == AgentState.Idle -> SpeakingToIdle
            from == AgentState.Angry && to == AgentState.Idle -> SpeakingToIdle
            from == AgentState.Watching && to == AgentState.Idle -> SpeakingToIdle
            else -> null
        }
    }
}
