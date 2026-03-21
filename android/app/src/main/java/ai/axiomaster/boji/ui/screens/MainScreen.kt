package ai.axiomaster.boji.ui.screens

import ai.axiomaster.boji.MainViewModel
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Store
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
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

sealed class Screen(val route: String, val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    object Chat : Screen("chat", "Chat", Icons.Default.ChatBubble)
    object Marketplace : Screen("marketplace", "Marketplace", Icons.Default.Store)
    object Server : Screen("server", "Server", Icons.Default.Dns)
    object Settings : Screen("settings", "Settings", Icons.Default.Settings)
}

val items = listOf(
    Screen.Chat,
    Screen.Server,
    Screen.Marketplace,
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
                    .height(56.dp), // Slimmer height
                containerColor = MaterialTheme.colorScheme.surface,
                tonalElevation = 0.dp
            ) {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination
                items.forEach { screen ->
                    NavigationBarItem(
                        icon = { Icon(screen.icon, contentDescription = null, modifier = Modifier.size(24.dp)) },
                        label = null, // Remove text label
                        alwaysShowLabel = false,
                        selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
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
            composable(Screen.Marketplace.route) { MarketplaceTab(viewModel = viewModel) }
            composable(Screen.Server.route) { ServerTab(viewModel = viewModel) }
            composable(Screen.Settings.route) { SettingsTab(viewModel = viewModel) }
        }
    }
}
