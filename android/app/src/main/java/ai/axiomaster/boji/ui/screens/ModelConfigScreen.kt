package ai.axiomaster.boji.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import ai.axiomaster.boji.MainViewModel
import ai.axiomaster.boji.remote.config.ModelConfig
import ai.axiomaster.boji.ui.screens.chat.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelConfigScreen(
    viewModel: MainViewModel,
    onBack: () -> Unit
) {
    val serverConfig by viewModel.serverConfig.collectAsState()
    val providers = serverConfig?.providers ?: emptyList()
    val models = serverConfig?.models ?: emptyList()
    val defaultModel = serverConfig?.defaultModel ?: ""

    var selectedProviderId by remember { mutableStateOf(providers.firstOrNull()?.id ?: "") }
    var modelId by remember { mutableStateOf("") }
    var baseUrl by remember { mutableStateOf("") }
    var apiKey by remember { mutableStateOf("") }
    var editingModelId by remember { mutableStateOf<String?>(null) }

    val selectedProvider = providers.find { it.id == selectedProviderId }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
    ) {
        TopAppBar(
            title = { Text("Model Configuration", style = mobileTitle2) },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.White)
        )

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                Text("Configure New Model", style = mobileHeadline, color = mobileAccent)
            }

            item {
                var expanded by remember { mutableStateOf(false) }
                ExposedDropdownMenuBox(
                    expanded = expanded,
                    onExpandedChange = { expanded = !expanded }
                ) {
                    OutlinedTextField(
                        value = selectedProvider?.displayName ?: "Select Provider",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Provider") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                        modifier = Modifier.fillMaxWidth().menuAnchor(),
                        colors = settingsTextFieldColors()
                    )
                    ExposedDropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false }
                    ) {
                        providers.forEach { provider ->
                            DropdownMenuItem(
                                text = { Text(provider.displayName) },
                                onClick = {
                                    selectedProviderId = provider.id
                                    baseUrl = provider.defaultBaseUrl
                                    expanded = false
                                }
                            )
                        }
                    }
                }
            }

            item {
                OutlinedTextField(
                    value = modelId,
                    onValueChange = { modelId = it },
                    label = { Text("Model ID (e.g. gpt-4)") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = settingsTextFieldColors()
                )
            }

            item {
                OutlinedTextField(
                    value = baseUrl,
                    onValueChange = { baseUrl = it },
                    label = { Text("Base URL (Optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = settingsTextFieldColors()
                )
            }

            if (selectedProvider?.requiresApiKey == true) {
                item {
                    OutlinedTextField(
                        value = apiKey,
                        onValueChange = { apiKey = it },
                        label = { Text("API Key") },
                        modifier = Modifier.fillMaxWidth(),
                        visualTransformation = PasswordVisualTransformation(),
                        colors = settingsTextFieldColors()
                    )
                }
            }

            item {
                Button(
                    onClick = {
                        val newModels = models.toMutableList()
                        val newConfig = ModelConfig(
                            id = modelId,
                            provider = selectedProviderId,
                            baseUrl = if (baseUrl.isBlank()) null else baseUrl,
                            modelId = modelId,
                            apiKey = if (apiKey.isBlank()) null else apiKey
                        )
                        
                        val index = newModels.indexOfFirst { it.id == modelId }
                        if (index >= 0) {
                            newModels[index] = newConfig
                        } else {
                            newModels.add(newConfig)
                        }
                        
                        viewModel.updateServerConfig(models = newModels)
                        // Reset form
                        modelId = ""
                        apiKey = ""
                        editingModelId = null
                    },
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = settingsPrimaryButtonColors(),
                    enabled = modelId.isNotBlank()
                ) {
                    Text(if (editingModelId != null) "Update Model" else "Add Model", color = Color.White)
                }
            }

            item { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp), color = mobileBorder) }

            item {
                Text("Existing Models", style = mobileHeadline, color = mobileText)
            }

            items(models) { model ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFFF8F9FA)),
                    border = if (model.id == defaultModel) BorderStroke(2.dp, mobileAccent) else null
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(model.id, style = mobileBody, fontWeight = FontWeight.Bold)
                                if (model.id == defaultModel) {
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Surface(
                                        color = mobileAccentSoft,
                                        shape = RoundedCornerShape(4.dp)
                                    ) {
                                        Text(
                                            "Default",
                                            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                                            style = mobileCaption2,
                                            color = mobileAccent
                                        )
                                    }
                                }
                            }
                            Text("Provider: ${model.provider}", style = mobileCaption1, color = mobileTextSecondary)
                        }
                        
                        Row {
                            IconButton(onClick = {
                                viewModel.updateServerConfig(defaultModel = model.id)
                            }) {
                                Icon(Icons.Default.Star, contentDescription = "Set Default", tint = if (model.id == defaultModel) mobileAccent else Color.Gray)
                            }
                            IconButton(onClick = {
                                val newModels = models.filter { it.id != model.id }
                                viewModel.updateServerConfig(models = newModels)
                            }) {
                                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = mobileDanger)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun settingsTextFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedContainerColor = Color.White,
    unfocusedContainerColor = Color.White,
    focusedBorderColor = mobileAccent,
    unfocusedBorderColor = mobileBorder,
    focusedTextColor = mobileText,
    unfocusedTextColor = mobileText,
    cursorColor = mobileAccent,
)

@Composable
private fun settingsPrimaryButtonColors() = ButtonDefaults.buttonColors(
    containerColor = mobileAccent,
    contentColor = Color.White,
)
