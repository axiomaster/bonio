package ai.axiomaster.boji.remote.theme

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File

class ThemeRepository(private val context: Context) {

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val installedThemesDir: File
        get() = File(context.filesDir, "themes/installed").apply { mkdirs() }

    /** List themes bundled in assets/themes/installed/ (read-only) */
    suspend fun listInstalledThemes(): List<ThemeInfo> = withContext(Dispatchers.IO) {
        val result = mutableListOf<ThemeInfo>()
        try {
            val assetManager = context.assets
            val themes = assetManager.list("themes/installed") ?: emptyArray()
            for (themeId in themes) {
                try {
                    val manifestJson = assetManager.open("themes/installed/$themeId/theme.json")
                        .bufferedReader().use { it.readText() }
                    val theme = json.decodeFromString<ThemeInfo>(manifestJson)
                    result.add(theme.copy(id = themeId))
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to load theme $themeId: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "listInstalledThemes failed", e)
        }
        result
    }

    companion object {
        private const val TAG = "ThemeRepository"
    }
}
