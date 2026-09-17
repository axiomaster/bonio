package ai.axiomaster.bonio.ui.screens

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.i18n.AppStrings
import ai.axiomaster.bonio.i18n.LocalAppStrings
import ai.axiomaster.bonio.ui.theme.LocalAppColors

sealed class Screen(val route: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    object Chat : Screen("chat", Icons.Default.ChatBubble)
    object Todo : Screen("todo", Icons.Default.Checklist)
    object Memory : Screen("memory", Icons.Default.AutoStories)
    object Personalization : Screen("personalization", Icons.Default.Widgets)
    object Settings : Screen("settings", Icons.Default.Settings)
}

val items = listOf(
    Screen.Chat,
    Screen.Todo,
    Screen.Memory,
    Screen.Personalization,
    Screen.Settings
)

@Composable
fun MainScreen(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val currentLanguage by viewModel.appLanguage.collectAsState()
    val strings = remember(currentLanguage) { AppStrings.forLanguage(currentLanguage) }
    val colors = LocalAppColors.current

    CompositionLocalProvider(LocalAppStrings provides strings) {
        val navController = rememberNavController()
        val navBackStackEntry by navController.currentBackStackEntryAsState()
        val currentDestination = navBackStackEntry?.destination

        val selectedIndex = items.indexOfFirst { screen ->
            currentDestination?.hierarchy?.any { it.route == screen.route } == true
        }.coerceAtLeast(0)

        LaunchedEffect(currentDestination?.route) {
            if (currentDestination?.route == Screen.Memory.route) {
                viewModel.memoryRepository.refresh()
            }
        }

        // One-shot tab requests from overlay windows (avatar bubble taps).
        val requestedTab by ai.axiomaster.bonio.util.NavigationBus.requestedTab.collectAsState()
        LaunchedEffect(requestedTab) {
            if (requestedTab != null) {
                val target = items.firstOrNull { it.route == requestedTab }
                if (target != null) {
                    navController.navigate(target.route) {
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                }
                ai.axiomaster.bonio.util.NavigationBus.consume()
            }
        }

        Scaffold(
            modifier = modifier.fillMaxSize(),
            containerColor = colors.background,
            topBar = {
                TabRow(
                    selectedTabIndex = selectedIndex,
                    modifier = Modifier
                        .windowInsetsPadding(WindowInsets.statusBars)
                        .fillMaxWidth()
                        .height(48.dp),
                    containerColor = colors.surface,
                    contentColor = colors.accent,
                    indicator = {},
                    divider = {}
                ) {
                    items.forEachIndexed { index, screen ->
                        val isSelected = selectedIndex == index
                        val title = when (screen) {
                            Screen.Chat -> strings.tabChat
                            Screen.Todo -> strings.tabTodo
                            Screen.Memory -> strings.tabMemory
                            Screen.Personalization -> strings.tabPersonalization
                            Screen.Settings -> strings.tabSettings
                        }
                        Tab(
                            selected = isSelected,
                            onClick = {
                                if (!isSelected) {
                                    if (screen == Screen.Memory) {
                                        viewModel.memoryRepository.refresh()
                                    }
                                    navController.navigate(screen.route) {
                                        popUpTo(navController.graph.findStartDestination().id) {
                                            saveState = true
                                        }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            },
                            icon = {
                                Icon(
                                    screen.icon,
                                    contentDescription = title,
                                    modifier = Modifier.size(22.dp),
                                    tint = if (isSelected) colors.accent else colors.textTertiary
                                )
                            }
                        )
                    }
                }
            }
        ) { innerPadding ->
            Surface(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                color = colors.background
            ) {
                NavHost(
                    navController = navController,
                    startDestination = Screen.Chat.route,
                    enterTransition = { EnterTransition.None },
                    exitTransition = { ExitTransition.None },
                    popEnterTransition = { EnterTransition.None },
                    popExitTransition = { ExitTransition.None }
                ) {
                    composable(Screen.Chat.route) { ChatTab(viewModel = viewModel) }
                    composable(Screen.Todo.route) { TodoTab(viewModel = viewModel) }
                    composable(Screen.Memory.route) { MemoryTab(viewModel = viewModel) }
                    composable(Screen.Personalization.route) { PersonalizationTab(viewModel = viewModel) }
                    composable(Screen.Settings.route) { SettingsTab(viewModel = viewModel) }
                }
            }
        }
    }
}
