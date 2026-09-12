package ai.axiomaster.bonio.ui.screens

import ai.axiomaster.bonio.MainViewModel
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Store
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController

import androidx.compose.material.icons.filled.Widgets
import androidx.compose.ui.graphics.Color

sealed class Screen(val route: String, val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    object Chat : Screen("chat", "Chat", Icons.Default.ChatBubble)
    object Memory : Screen("memory", "Memory", Icons.Default.AutoStories)
    object Personalization : Screen("personalization", "个性化", Icons.Default.Widgets)
    object Settings : Screen("settings", "Settings", Icons.Default.Settings)
}

val items = listOf(
    Screen.Chat,
    Screen.Memory,
    Screen.Personalization,
    Screen.Settings
)

@Composable
fun MainScreen(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val navController = rememberNavController()

    Scaffold(
        modifier = modifier,
        topBar = {
            NavigationBar(
                modifier = Modifier
                    .windowInsetsPadding(WindowInsets.statusBars)
                    .height(48.dp),
                containerColor = Color(0xFFF8F8F8),
                tonalElevation = 0.dp
            ) {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination
                items.forEach { screen ->
                    val isSelected = currentDestination?.hierarchy?.any { it.route == screen.route } == true
                    NavigationBarItem(
                        icon = {
                            Icon(
                                screen.icon,
                                contentDescription = screen.title,
                                modifier = Modifier.size(22.dp)
                            )
                        },
                        label = null,
                        alwaysShowLabel = false,
                        selected = isSelected,
                        colors = NavigationBarItemDefaults.colors(
                            indicatorColor = Color.Transparent,
                            selectedIconColor = Color(0xFF0A59F7),
                            unselectedIconColor = Color(0xFF999999)
                        ),
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Chat.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Chat.route) { ChatTab(viewModel = viewModel) }
            composable(Screen.Memory.route) { MemoryTab(viewModel = viewModel) }
            composable(Screen.Personalization.route) { PersonalizationTab(viewModel = viewModel) }
            composable(Screen.Settings.route) { SettingsTab(viewModel = viewModel) }
        }
    }
}
