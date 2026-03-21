package ai.axiomaster.boji.remote.theme

import kotlinx.serialization.Serializable

@Serializable
data class ThemeInfo(
    val id: String,
    val name: String = "",
    val version: String = "",
    val description: String = "",
    val states: Map<String, String> = emptyMap(),
) {
    /** Asset path for a given state, e.g. "themes/installed/default-cat/cat-idle.lottie" */
    fun assetPathForState(state: String): String? {
        val stateFile = states[state.lowercase()] ?: return null
        return "themes/installed/$id/$stateFile"
    }
}
