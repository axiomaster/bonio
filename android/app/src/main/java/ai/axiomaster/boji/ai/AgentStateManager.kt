package ai.axiomaster.boji.ai

import android.graphics.Color
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AgentStateManager {
    private val _currentState = MutableStateFlow(AgentState.Idle)
    val currentState: StateFlow<AgentState> = _currentState.asStateFlow()

    private val _currentTextBubble = MutableStateFlow<String?>(null)
    val currentTextBubble: StateFlow<String?> = _currentTextBubble.asStateFlow()

    /** Background color as ARGB int */
    private val _bubbleColor = MutableStateFlow(Color.WHITE)
    val bubbleColor: StateFlow<Int> = _bubbleColor.asStateFlow()

    /** Primary text color for bubble body and label */
    private val _bubbleTextColor = MutableStateFlow(Color.BLACK)
    val bubbleTextColor: StateFlow<Int> = _bubbleTextColor.asStateFlow()

    /**
     * When non-null, shown in the bubble label area instead of the activity label (e.g. countdown "3…").
     * Cleared by [clearBubble].
     */
    private val _bubbleCountdownLabel = MutableStateFlow<String?>(null)
    val bubbleCountdownLabel: StateFlow<String?> = _bubbleCountdownLabel.asStateFlow()

    /** Optional PorterDuff color filter tint for the avatar Lottie (e.g. red for spam calls). */
    private val _avatarColorFilter = MutableStateFlow<Int?>(null)
    val avatarColorFilter: StateFlow<Int?> = _avatarColorFilter.asStateFlow()

    fun setAvatarColorFilter(color: Int?) {
        _avatarColorFilter.value = color
    }

    fun transitionTo(newState: AgentState) {
        _currentState.value = newState
        when (newState) {
            AgentState.Idle -> clearBubble()
            AgentState.Bored -> clearBubble()
            AgentState.Sleeping -> clearBubble()
            AgentState.Listening -> setBubble("...")
            AgentState.Thinking -> setBubble("Hmm...")
            AgentState.Happy -> clearBubble()
            AgentState.Confused -> clearBubble()
            else -> {}
        }
    }

    fun setBubble(text: String?) {
        _currentTextBubble.value = text
        if (text == null) {
            _bubbleColor.value = Color.WHITE
            _bubbleTextColor.value = Color.BLACK
        }
    }

    fun setBubble(text: String, bgColor: Int, textColor: Int = Color.WHITE) {
        _bubbleColor.value = bgColor
        _bubbleTextColor.value = textColor
        _currentTextBubble.value = text
    }

    /** Optional label override (e.g. countdown); pass null to clear. */
    fun setBubbleCountdown(text: String?) {
        _bubbleCountdownLabel.value = text
    }

    fun clearBubble() {
        _currentTextBubble.value = null
        _bubbleColor.value = Color.WHITE
        _bubbleTextColor.value = Color.BLACK
        _bubbleCountdownLabel.value = null
    }
}
