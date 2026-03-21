package ai.axiomaster.boji.ui.screens

import ai.axiomaster.boji.MainViewModel
import ai.axiomaster.boji.remote.skills.ClawHubSearchResult
import ai.axiomaster.boji.remote.skills.ClawHubSkillDetail
import ai.axiomaster.boji.ui.screens.chat.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.text.NumberFormat
import java.util.Locale

@Composable
fun MarketplaceTab(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
) {
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }

    Column(modifier = modifier.fillMaxSize()) {
        TabRow(
            selectedTabIndex = selectedTab,
            containerColor = Color.Transparent,
            contentColor = mobileAccent,
            modifier = Modifier.padding(horizontal = 20.dp),
        ) {
            Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 }) {
                Text(
                    "Skills",
                    style = mobileCallout.copy(fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.padding(vertical = 12.dp),
                )
            }
            Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 }) {
                Text(
                    "Models",
                    style = mobileCallout.copy(fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.padding(vertical = 12.dp),
                )
            }
            Tab(selected = selectedTab == 2, onClick = { selectedTab = 2 }) {
                Text(
                    "Themes",
                    style = mobileCallout.copy(fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.padding(vertical = 12.dp),
                )
            }
        }

        when (selectedTab) {
            0 -> SkillMarketplaceContent(viewModel = viewModel)
            1 -> ModelProviderMarketplaceContent()
            2 -> ThemeMarketplaceContent()
        }
    }
}

// ════════════════════════════════════════════════════════════════
//  Skill Marketplace (ClawHub)
// ════════════════════════════════════════════════════════════════

@Composable
private fun SkillMarketplaceContent(viewModel: MainViewModel) {
    val results by viewModel.marketplaceResults.collectAsState()
    val loading by viewModel.marketplaceLoading.collectAsState()
    val error by viewModel.marketplaceError.collectAsState()
    val selectedSkill by viewModel.selectedMarketSkill.collectAsState()
    val installProgress by viewModel.installProgress.collectAsState()

    var searchQuery by rememberSaveable { mutableStateOf("") }
    val keyboardController = LocalSoftwareKeyboardController.current

    LaunchedEffect(Unit) {
        viewModel.searchMarketplace("")
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 8.dp),
    ) {
        OutlinedTextField(
            value = searchQuery,
            onValueChange = { searchQuery = it },
            placeholder = { Text("Search skills on ClawHub...", style = mobileCallout) },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = mobileTextTertiary) },
            trailingIcon = {
                if (searchQuery.isNotBlank()) {
                    IconButton(onClick = {
                        searchQuery = ""
                        viewModel.searchMarketplace("")
                    }) {
                        Icon(Icons.Default.Clear, contentDescription = "Clear", tint = mobileTextTertiary, modifier = Modifier.size(18.dp))
                    }
                }
            },
            singleLine = true,
            shape = RoundedCornerShape(14.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = {
                if (searchQuery.isNotBlank()) {
                    viewModel.searchMarketplace(searchQuery.trim())
                    keyboardController?.hide()
                }
            }),
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(Modifier.height(8.dp))

        if (!error.isNullOrBlank()) {
            Surface(
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                color = mobileDangerSoft,
                shape = RoundedCornerShape(10.dp),
                border = BorderStroke(1.dp, mobileDanger.copy(alpha = 0.3f)),
            ) {
                Text(error!!, style = mobileCallout, color = mobileDanger, modifier = Modifier.padding(12.dp))
            }
        }

        if (loading) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = mobileAccent, modifier = Modifier.size(32.dp))
            }
        } else if (results.isEmpty() && searchQuery.isBlank()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Store, contentDescription = null, tint = mobileTextTertiary, modifier = Modifier.size(48.dp))
                    Spacer(Modifier.height(12.dp))
                    Text("ClawHub Marketplace", style = mobileHeadline, color = mobileText)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Search for community skills to extend your agent",
                        style = mobileCaption1,
                        color = mobileTextTertiary,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        } else if (results.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No skills found for \"$searchQuery\"", style = mobileBody, color = mobileTextSecondary)
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(bottom = 24.dp),
            ) {
                items(results, key = { it.slug }) { result ->
                    SkillMarketplaceCard(
                        result = result,
                        onClick = { viewModel.loadMarketSkillDetail(result.slug) },
                    )
                }
            }
        }
    }

    if (selectedSkill != null) {
        SkillDetailSheet(
            detail = selectedSkill!!,
            installProgress = installProgress,
            onInstall = { viewModel.installFromMarketplace(selectedSkill!!.skill.slug) },
            onDismiss = {
                viewModel.clearSelectedMarketSkill()
                viewModel.clearInstallProgress()
            },
        )
    }
}

@Composable
private fun SkillMarketplaceCard(
    result: ClawHubSearchResult,
    onClick: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = Color.White,
        border = BorderStroke(1.dp, mobileBorder),
        shadowElevation = 0.dp,
        onClick = onClick,
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(
                text = result.displayName.ifBlank { result.slug },
                style = mobileCallout.copy(fontWeight = FontWeight.SemiBold),
                color = mobileText,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (result.summary.isNotBlank()) {
                Spacer(Modifier.height(2.dp))
                Text(
                    text = result.summary,
                    style = mobileCaption1,
                    color = mobileTextSecondary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun SkillDetailSheet(
    detail: ClawHubSkillDetail,
    installProgress: String?,
    onInstall: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                detail.skill.displayName.ifBlank { detail.skill.slug },
                style = mobileHeadline,
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (detail.skill.summary.isNotBlank()) {
                    Text(detail.skill.summary, style = mobileCallout, color = mobileTextSecondary)
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    StatBadge(Icons.Default.Star, "${detail.skill.stats.stars}")
                    StatBadge(Icons.Default.Download, formatNumber(detail.skill.stats.downloads))
                    if (detail.latestVersion != null) {
                        StatBadge(Icons.Default.NewReleases, "v${detail.latestVersion.version}")
                    }
                }

                if (detail.owner.handle.isNotBlank()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Person, contentDescription = null, tint = mobileTextTertiary, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(detail.owner.displayName.ifBlank { detail.owner.handle }, style = mobileCaption1, color = mobileTextSecondary)
                    }
                }

                if (installProgress == "success") {
                    Surface(
                        color = mobileSuccessSoft,
                        shape = RoundedCornerShape(8.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            "Installed successfully!",
                            style = mobileCallout.copy(fontWeight = FontWeight.SemiBold),
                            color = mobileSuccess,
                            modifier = Modifier.padding(12.dp),
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        },
        confirmButton = {
            when (installProgress) {
                "downloading", "installing" -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = mobileAccent)
                        Spacer(Modifier.width(8.dp))
                        Text(
                            if (installProgress == "downloading") "Downloading..." else "Installing...",
                            style = mobileCallout,
                            color = mobileTextSecondary,
                        )
                    }
                }
                "success" -> {
                    TextButton(onClick = onDismiss) {
                        Text("Done", color = mobileAccent)
                    }
                }
                else -> {
                    TextButton(onClick = onInstall) {
                        Icon(Icons.Default.Download, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Install", color = mobileAccent)
                    }
                }
            }
        },
        dismissButton = {
            if (installProgress != "downloading" && installProgress != "installing") {
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        },
    )
}

@Composable
private fun StatBadge(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = mobileTextTertiary, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(3.dp))
        Text(text, style = mobileCaption1, color = mobileTextSecondary)
    }
}

// ════════════════════════════════════════════════════════════════
//  Model/Provider Marketplace (placeholder)
// ════════════════════════════════════════════════════════════════

@Composable
private fun ModelProviderMarketplaceContent() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.Storage, contentDescription = null, tint = mobileTextTertiary, modifier = Modifier.size(48.dp))
            Spacer(Modifier.height(12.dp))
            Text("Model & Provider Marketplace", style = mobileHeadline, color = mobileText)
            Spacer(Modifier.height(4.dp))
            Text(
                "Browse and add OpenAI, Anthropic, and other providers. Coming soon.",
                style = mobileCaption1,
                color = mobileTextTertiary,
                textAlign = TextAlign.Center,
            )
        }
    }
}

// ════════════════════════════════════════════════════════════════
//  Theme/Skin Marketplace (placeholder)
// ════════════════════════════════════════════════════════════════

@Composable
private fun ThemeMarketplaceContent() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.Palette, contentDescription = null, tint = mobileTextTertiary, modifier = Modifier.size(48.dp))
            Spacer(Modifier.height(12.dp))
            Text("Theme Marketplace", style = mobileHeadline, color = mobileText)
            Spacer(Modifier.height(4.dp))
            Text(
                "Browse themes from designers. Replace the cat avatar with custom styles. Coming soon.",
                style = mobileCaption1,
                color = mobileTextTertiary,
                textAlign = TextAlign.Center,
            )
        }
    }
}

private fun formatNumber(n: Int): String {
    if (n < 1000) return "$n"
    return NumberFormat.getNumberInstance(Locale.US).format(n)
}
