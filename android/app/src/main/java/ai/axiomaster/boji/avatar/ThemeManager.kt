package ai.axiomaster.boji.avatar

import android.content.Context
import android.content.SharedPreferences
import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.remote.theme.ThemeInfo
import ai.axiomaster.boji.remote.theme.ThemeRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class ThemeManager(private val context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("boji_theme", Context.MODE_PRIVATE)

    private val repository = ThemeRepository(context)

    private val _installedThemes = MutableStateFlow<List<ThemeInfo>>(emptyList())
    val installedThemes: StateFlow<List<ThemeInfo>> = _installedThemes.asStateFlow()

    private val _activeThemeId = MutableStateFlow(
        prefs.getString(KEY_ACTIVE_THEME, DEFAULT_THEME_ID) ?: DEFAULT_THEME_ID
    )
    val activeThemeId: StateFlow<String> = _activeThemeId.asStateFlow()

    suspend fun refreshThemes() {
        _installedThemes.value = repository.listInstalledThemes()
    }

    fun setActiveTheme(themeId: String) {
        _activeThemeId.value = themeId
        prefs.edit().putString(KEY_ACTIVE_THEME, themeId).apply()
    }

    fun getActiveTheme(): ThemeInfo? =
        _installedThemes.value.find { it.id == _activeThemeId.value }
            ?: _installedThemes.value.firstOrNull()

    /**
     * Resolve the Lottie asset path for the current [AvatarState].
     *
     * Priority:
     * 1. Active transition (one-shot animation between states)
     * 2. Motion animation (walking/running/dragging) while moving
     * 3. Action animation (tapping/swiping/etc.) while performing a GUI action
     * 4. Activity animation (idle/listening/thinking/speaking/working/bored/sleeping/happy/confused)
     */
    fun resolveAssetPath(state: AvatarState): String {
        val theme = getActiveTheme()

        if (state.transition != null) {
            val path = theme?.transitionAssetPath(state.transition.key)
            if (path != null) return path
        }

        if (state.motion != MotionState.Stationary) {
            val motionKey = state.motion.name.lowercase()
            val path = theme?.motionAssetPath(motionKey)
            if (path != null) return path
        }

        if (state.action != AvatarAction.None) {
            val actionKey = state.action.name.lowercase()
            val path = theme?.actionAssetPath(actionKey)
            if (path != null) return path
            return theme?.assetPathForState("working") ?: fallbackAssetPath(state.activity)
        }

        val activityKey = activityStateKey(state.activity)
        return theme?.assetPathForState(activityKey) ?: fallbackAssetPath(state.activity)
    }

    /**
     * Resolve the asset path for a specific transition, independent of current state.
     */
    fun resolveTransitionPath(transition: AvatarTransition): String? {
        return getActiveTheme()?.transitionAssetPath(transition.key)
    }

    private fun activityStateKey(state: AgentState): String = when (state) {
        AgentState.Idle -> "idle"
        AgentState.Bored -> "bored"
        AgentState.Sleeping -> "sleeping"
        AgentState.Listening -> "listening"
        AgentState.Thinking -> "thinking"
        AgentState.Speaking -> "speaking"
        AgentState.Working -> "working"
        AgentState.Happy -> "happy"
        AgentState.Confused -> "confused"
        AgentState.Angry -> "angry"
        AgentState.Watching -> "watching"
    }

    private fun fallbackAssetPath(state: AgentState): String = when (state) {
        AgentState.Idle -> "cat-idle.lottie"
        AgentState.Bored -> "cat-bored.lottie"
        AgentState.Sleeping -> "cat-sleeping.lottie"
        AgentState.Listening -> "cat-listening.lottie"
        AgentState.Thinking -> "cat-thinking.lottie"
        AgentState.Speaking -> "cat-speaking.lottie"
        AgentState.Working -> "cat-working.lottie"
        AgentState.Happy -> "cat-happy.lottie"
        AgentState.Confused -> "cat-confused.lottie"
        AgentState.Angry -> "cat-angry.lottie"
        AgentState.Watching -> "cat-watching.lottie"
    }

    companion object {
        private const val KEY_ACTIVE_THEME = "active_theme_id"
        private const val DEFAULT_THEME_ID = "default-cat"
    }
}
