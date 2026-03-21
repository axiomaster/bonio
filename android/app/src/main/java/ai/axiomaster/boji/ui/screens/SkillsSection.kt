package ai.axiomaster.boji.ui.screens

import ai.axiomaster.boji.MainViewModel
import ai.axiomaster.boji.remote.skills.SkillInfo
import ai.axiomaster.boji.ui.screens.chat.*
import androidx.compose.animation.animateContentSize
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
fun SkillsSectionCard(
    viewModel: MainViewModel,
    isConnected: Boolean,
    modifier: Modifier = Modifier,
) {
    val skills by viewModel.skills.collectAsState()
    val loading by viewModel.skillsLoading.collectAsState()
    val error by viewModel.skillsError.collectAsState()

    var expanded by rememberSaveable { mutableStateOf(false) }
    var showInstallDialog by remember { mutableStateOf(false) }
    var builtinExpanded by rememberSaveable { mutableStateOf(true) }
    var customExpanded by rememberSaveable { mutableStateOf(true) }

    LaunchedEffect(isConnected) {
        if (isConnected) viewModel.refreshSkills()
    }
    LaunchedEffect(expanded, isConnected) {
        if (expanded && isConnected) viewModel.refreshSkills()
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
                Text("Skills", style = mobileHeadline, color = mobileAccent)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val builtins = skills.filter { it.builtin }
                    val custom = skills.filter { !it.builtin }
                    Text(
                        "${skills.size} total",
                        style = mobileCaption1,
                        color = mobileTextSecondary,
                    )
                    Spacer(Modifier.width(8.dp))
                    IconButton(
                        onClick = { expanded = !expanded },
                    ) {
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

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    IconButton(onClick = { viewModel.refreshSkills() }, enabled = isConnected && !loading) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = mobileAccent)
                    }
                    IconButton(onClick = { showInstallDialog = true }, enabled = isConnected) {
                        Icon(Icons.Default.Add, contentDescription = "Install", tint = mobileAccent)
                    }
                }

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

                if (!isConnected) {
                    Text("Not connected to server", style = mobileBody, color = mobileTextSecondary)
                } else if (loading && skills.isEmpty()) {
                    Box(modifier = Modifier.fillMaxWidth().height(80.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = mobileAccent, modifier = Modifier.size(32.dp))
                    }
                } else if (skills.isEmpty()) {
                    Text("No skills found", style = mobileBody, color = mobileTextSecondary)
                } else {
                    val builtins = skills.filter { it.builtin }
                    val custom = skills.filter { !it.builtin }

                    LazyColumn(
                        modifier = Modifier.heightIn(max = 400.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        if (builtins.isNotEmpty()) {
                            item(key = "__hdr_b") {
                                CollapsibleSectionHeader("Built-in", builtins.size, builtinExpanded) { builtinExpanded = !builtinExpanded }
                            }
                            if (builtinExpanded) {
                                items(builtins, key = { "b_${it.id}" }) { skill ->
                                    SkillCard(skill, { viewModel.toggleSkill(skill.id, !skill.enabled) }, null, Modifier.padding(bottom = 8.dp))
                                }
                            }
                        }
                        if (custom.isNotEmpty()) {
                            item(key = "__hdr_c") {
                                CollapsibleSectionHeader("Installed", custom.size, customExpanded) { customExpanded = !customExpanded }
                            }
                            if (customExpanded) {
                                items(custom, key = { "c_${it.id}" }) { skill ->
                                    SkillCard(skill, { viewModel.toggleSkill(skill.id, !skill.enabled) }, { viewModel.removeSkill(skill.id) }, Modifier.padding(bottom = 8.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showInstallDialog) {
        InstallSkillDialog(
            onDismiss = { showInstallDialog = false },
            onInstall = { id, content ->
                viewModel.installSkill(id, content)
                showInstallDialog = false
            },
        )
    }
}

@Composable
fun CollapsibleSectionHeader(
    title: String,
    count: Int,
    expanded: Boolean,
    onToggle: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 6.dp),
        onClick = onToggle,
        color = Color.Transparent,
    ) {
        Row(modifier = Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = mobileCallout.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = mobileTextSecondary)
            Spacer(Modifier.width(6.dp))
            Surface(shape = RoundedCornerShape(10.dp), color = mobileSurface) {
                Text("$count", style = mobileCaption2.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = mobileTextTertiary, modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp))
            }
            Spacer(Modifier.weight(1f))
            Icon(
                if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                contentDescription = if (expanded) "Collapse" else "Expand",
                tint = mobileTextTertiary,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
fun SkillCard(
    skill: SkillInfo,
    onToggle: () -> Unit,
    onRemove: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier.fillMaxWidth().animateContentSize(),
        shape = RoundedCornerShape(14.dp),
        color = Color.White,
        border = BorderStroke(1.dp, if (skill.enabled) mobileAccent.copy(alpha = 0.15f) else mobileBorder),
        shadowElevation = if (skill.enabled) 1.dp else 0.dp,
        onClick = { expanded = !expanded },
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Extension, contentDescription = null, tint = if (skill.enabled) mobileAccent else mobileTextTertiary, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(skill.name.ifBlank { skill.id }, style = mobileCallout.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = mobileText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (skill.description.isNotBlank() && !expanded) {
                        Text(skill.description, style = mobileCaption1, color = mobileTextSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (onRemove != null) {
                    IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(36.dp)) {
                        Icon(Icons.Default.Delete, contentDescription = "Remove", tint = mobileDanger.copy(alpha = 0.7f), modifier = Modifier.size(18.dp))
                    }
                    Spacer(Modifier.width(4.dp))
                }
                Switch(
                    checked = skill.enabled,
                    onCheckedChange = { onToggle() },
                    colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = mobileAccent, uncheckedThumbColor = Color.White, uncheckedTrackColor = mobileSurfaceStrong),
                )
            }
            if (expanded && skill.description.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(skill.description, style = mobileCallout, color = mobileTextSecondary)
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Remove Skill") },
            text = { Text("Remove \"${skill.name.ifBlank { skill.id }}\"? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = { showDeleteConfirm = false; onRemove?.invoke() }) {
                    Text("Remove", color = mobileDanger)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
fun InstallSkillDialog(
    onDismiss: () -> Unit,
    onInstall: (id: String, content: String) -> Unit,
) {
    var skillId by remember { mutableStateOf("") }
    var skillContent by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Install Skill", style = mobileHeadline) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(value = skillId, onValueChange = { skillId = it }, label = { Text("Skill ID") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = skillContent, onValueChange = { skillContent = it }, label = { Text("SKILL.md Content") }, minLines = 4, maxLines = 8, modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            TextButton(onClick = { onInstall(skillId.trim(), skillContent.trim()) }, enabled = skillId.isNotBlank() && skillContent.isNotBlank()) {
                Text("Install", color = mobileAccent)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
