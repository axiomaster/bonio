package ai.axiomaster.BoJi.ai

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AgentStateManager {
    private val _currentState = MutableStateFlow(AgentState.Idle)
    val currentState: StateFlow<AgentState> = _currentState.asStateFlow()

    private val _currentTextBubble = MutableStateFlow<String?>(null)
    val currentTextBubble: StateFlow<String?> = _currentTextBubble.asStateFlow()

    fun transitionTo(newState: AgentState) {
        _currentState.value = newState
        when (newState) {
            AgentState.Idle -> clearBubble()
            AgentState.Listening -> setBubble("...")
            AgentState.Thinking -> setBubble("Hmm...")
            else -> {} // Kept as is or replaced by specific events
        }
    }

    fun setBubble(text: String?) {
        _currentTextBubble.value = text
    }

    fun clearBubble() {
        _currentTextBubble.value = null
    }
}
