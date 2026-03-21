package ai.axiomaster.boji.ui.screens

import ai.axiomaster.boji.MainViewModel
import ai.axiomaster.boji.remote.theme.ThemeInfo
import ai.axiomaster.boji.ui.screens.chat.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
fun ThemeSectionCard(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
) {
    val themes by viewModel.installedThemes.collectAsState()

    var expanded by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.refreshInstalledThemes()
    }

    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        border = BorderStroke(1.dp, mobileBorder),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Themes", style = mobileHeadline, color = mobileAccent)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${themes.size} installed",
                        style = mobileCaption1,
                        color = mobileTextSecondary,
                    )
                    Spacer(Modifier.width(8.dp))
                    IconButton(onClick = { expanded = !expanded }) {
                        Icon(
                            if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                            contentDescription = if (expanded) "Collapse" else "Expand",
                            tint = mobileTextTertiary,
                        )
                    }
                }
            }

            if (expanded) {
                Spacer(Modifier.height(12.dp))
                if (themes.isEmpty()) {
                    Text("No themes installed", style = mobileBody, color = mobileTextSecondary)
                } else {
                    LazyColumn(
                        modifier = Modifier.heightIn(max = 300.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(themes, key = { it.id }) { theme ->
                            ThemeCard(theme = theme)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ThemeCard(
    theme: ThemeInfo,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = Color.White,
        border = BorderStroke(1.dp, mobileBorder),
        shadowElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Palette, contentDescription = null, tint = mobileAccent, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    theme.name.ifBlank { theme.id },
                    style = mobileCallout.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
                    color = mobileText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (theme.description.isNotBlank()) {
                    Text(
                        theme.description,
                        style = mobileCaption1,
                        color = mobileTextSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (theme.version.isNotBlank()) {
                    Text("v${theme.version}", style = mobileCaption2, color = mobileTextTertiary)
                }
            }
        }
    }
}
