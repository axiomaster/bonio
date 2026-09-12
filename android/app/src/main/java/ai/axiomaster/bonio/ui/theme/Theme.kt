package ai.axiomaster.bonio.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

enum class ThemeMode(val code: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark");

    companion object {
        fun fromCode(code: String): ThemeMode {
            return entries.firstOrNull { it.code.equals(code, ignoreCase = true) } ?: SYSTEM
        }
    }
}

data class AppColors(
    val isDark: Boolean,
    val background: Color,
    val surface: Color,
    val cardBackground: Color,
    val surfaceVariant: Color,
    val inputBackground: Color,
    val border: Color,
    val divider: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val accent: Color,
    val dropdownContainer: Color,
    val dropdownItemText: Color,
)

val LightAppColors = AppColors(
    isDark = false,
    background = Color(0xFFFAFAFA),
    surface = Color.White,
    cardBackground = Color.White,
    surfaceVariant = Color(0xFFF5F5F5),
    inputBackground = Color(0xFFEFF3F8),
    border = Color(0xFFE5E6EB),
    divider = Color(0xFFF2F3F5),
    textPrimary = Color(0xFF172033),
    textSecondary = Color(0xFF4E5969),
    textTertiary = Color(0xFF98A2B3),
    accent = Color(0xFF0A59F7),
    dropdownContainer = Color.White,
    dropdownItemText = Color(0xFF172033),
)

val DarkAppColors = AppColors(
    isDark = true,
    background = Color(0xFF121212),
    surface = Color(0xFF1C1C1E),
    cardBackground = Color(0xFF1C1C1E),
    surfaceVariant = Color(0xFF2C2C2E),
    inputBackground = Color(0xFF2C2C2E),
    border = Color(0xFF38383A),
    divider = Color(0xFF2C2C2E),
    textPrimary = Color(0xFFF5F5F7),
    textSecondary = Color(0xFFA1A1A6),
    textTertiary = Color(0xFF6E6E73),
    accent = Color(0xFF3B82F6),
    dropdownContainer = Color(0xFF242426),
    dropdownItemText = Color(0xFFF5F5F7),
)

val LocalAppColors = staticCompositionLocalOf { LightAppColors }

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF3B82F6),
    onPrimary = Color.White,
    background = Color(0xFF121212),
    onBackground = Color(0xFFF5F5F7),
    surface = Color(0xFF1C1C1E),
    onSurface = Color(0xFFF5F5F7),
    surfaceVariant = Color(0xFF2C2C2E),
    onSurfaceVariant = Color(0xFFA1A1A6),
    surfaceContainer = Color(0xFF242426),
    surfaceContainerHigh = Color(0xFF2C2C2E),
    outline = Color(0xFF38383A),
    outlineVariant = Color(0xFF2C2C2E),
)

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF0A59F7),
    onPrimary = Color.White,
    background = Color(0xFFFAFAFA),
    onBackground = Color(0xFF172033),
    surface = Color.White,
    onSurface = Color(0xFF172033),
    surfaceVariant = Color(0xFFF5F5F5),
    onSurfaceVariant = Color(0xFF4E5969),
    surfaceContainer = Color.White,
    surfaceContainerHigh = Color.White,
    outline = Color(0xFFE5E6EB),
    outlineVariant = Color(0xFFF2F3F5),
)

@Composable
fun BonioTheme(
    themeMode: ThemeMode = ThemeMode.SYSTEM,
    content: @Composable () -> Unit
) {
    val systemInDark = isSystemInDarkTheme()
    val isDark = when (themeMode) {
        ThemeMode.SYSTEM -> systemInDark
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }

    val appColors = if (isDark) DarkAppColors else LightAppColors
    val m3ColorScheme = if (isDark) DarkColorScheme else LightColorScheme

    CompositionLocalProvider(LocalAppColors provides appColors) {
        MaterialTheme(
            colorScheme = m3ColorScheme,
            typography = Typography,
            content = content
        )
    }
}