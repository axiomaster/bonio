package ai.axiomaster.bonio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.ui.screens.chat.*

@Composable
fun ServerTab(
  viewModel: MainViewModel,
  modifier: Modifier = Modifier
) {
  // Connection state
  val isConnected by viewModel.isConnected.collectAsState()
  val statusText by viewModel.statusText.collectAsState()
  val serverConfig by viewModel.serverConfig.collectAsState()
  val localEnabled by viewModel.localEnabled.collectAsState()
  val localEngineState by viewModel.localEngineState.collectAsState()

  var showModelConfig by remember { mutableStateOf(false) }

  val listState = rememberLazyListState()

  Box(modifier = modifier.fillMaxSize().background(mobileBackgroundGradient)) {
    LazyColumn(
      state = listState,
      modifier = Modifier.fillMaxSize().imePadding().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom)),
      contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
      verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {


      // Local Engine Card (embedded hiclaw on 127.0.0.1, auto-started and auto-connected)
      item {
        Card(
          modifier = Modifier.fillMaxWidth().border(1.dp, mobileBorder, RoundedCornerShape(16.dp)),
          shape = RoundedCornerShape(16.dp),
          colors = CardDefaults.cardColors(containerColor = Color.White)
        ) {
          Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("本地引擎", style = mobileHeadline, color = mobileAccent)
            Text(
              "Engine: $localEngineState",
              style = mobileCallout,
              color = if (localEngineState == ai.axiomaster.bonio.local.LocalEngineController.State.Running) mobileSuccess else mobileText
            )
            Text(
              "连接状态: $statusText",
              style = mobileCallout,
              color = if (isConnected) mobileSuccess else mobileText
            )

            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
              Text("启用本地引擎", style = mobileCallout, fontWeight = FontWeight.Medium)
              Switch(checked = localEnabled, onCheckedChange = { viewModel.setLocalEnabled(it) })
            }
          }
        }
      }

      // Model Configuration Card
      item {
        Card(
          modifier = Modifier.fillMaxWidth().border(1.dp, mobileBorder, RoundedCornerShape(16.dp)),
          shape = RoundedCornerShape(16.dp),
          colors = CardDefaults.cardColors(containerColor = Color.White)
        ) {
          Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Model Configuration", style = mobileHeadline, color = mobileAccent)
            
            val currentModel = serverConfig?.defaultModel ?: "Not Set"
            val models = serverConfig?.models ?: emptyList()
            val currentModelConfig = models.find { it.id == currentModel }
            
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Current Model: $currentModel", style = mobileBody, fontWeight = FontWeight.Medium)
                if (currentModelConfig != null) {
                  Text("Provider: ${currentModelConfig.provider}", style = mobileCaption1, color = mobileTextSecondary)
                }
            }

            Button(
              onClick = { showModelConfig = true },
              modifier = Modifier.fillMaxWidth().height(48.dp),
              shape = RoundedCornerShape(12.dp),
              colors = settingsPrimaryButtonColors(),
              enabled = isConnected
            ) {
              Text("Configure Models", style = mobileHeadline, color = Color.White)
            }
          }
        }
      }

      // Skills Card (collapsible)
      item {
        SkillsSectionCard(viewModel = viewModel, isConnected = isConnected)
      }

      // Themes Card (collapsible)
      item {
        ThemeSectionCard(viewModel = viewModel)
      }

    }

    // Full screen overlay for Model Configuration
    if (showModelConfig) {
      Box(
        modifier = Modifier
          .fillMaxSize()
          .background(mobileBackgroundGradient)
          .safeDrawingPadding()
      ) {
        ModelConfigScreen(
          viewModel = viewModel,
          onBack = { showModelConfig = false }
        )
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

@Composable
private fun settingsDangerButtonColors() = ButtonDefaults.buttonColors(
  containerColor = mobileDanger,
  contentColor = Color.White,
)
