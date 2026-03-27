package ai.axiomaster.boji.remote.theme

import kotlinx.serialization.Serializable

@Serializable
data class ThemeInfo(
    val id: String,
    val name: String = "",
    val version: String = "",
    val description: String = "",
    val states: Map<String, String> = emptyMap(),
    val motionStates: Map<String, String> = emptyMap(),
    val actionStates: Map<String, String> = emptyMap(),
    val transitionStates: Map<String, String> = emptyMap(),
) {
    private fun prefixPath(file: String): String = "themes/installed/$id/$file"

    fun assetPathForState(state: String): String? {
        val stateFile = states[state.lowercase()] ?: return null
        return prefixPath(stateFile)
    }

    fun motionAssetPath(motion: String): String? {
        val file = motionStates[motion.lowercase()] ?: return null
        return prefixPath(file)
    }

    fun actionAssetPath(action: String): String? {
        val file = actionStates[action.lowercase()] ?: return null
        return prefixPath(file)
    }

    fun transitionAssetPath(transitionKey: String): String? {
        val file = transitionStates[transitionKey.lowercase()] ?: return null
        return prefixPath(file)
    }
}
