package ai.axiomaster.bonio.util

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * One-shot tab navigation requests from overlay windows (e.g. the floating
 * avatar bubble) to MainActivity's MainScreen.
 */
object NavigationBus {
    private val _requestedTab = MutableStateFlow<String?>(null)
    val requestedTab: StateFlow<String?> = _requestedTab.asStateFlow()

    fun requestTab(tab: String) {
        _requestedTab.value = tab
    }

    fun consume() {
        _requestedTab.value = null
    }
}
