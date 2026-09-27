package ai.axiomaster.bonio.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.avatar.CustomSkinManager
import ai.axiomaster.bonio.i18n.LocalAppStrings
import ai.axiomaster.bonio.local.LocalEngineController
import ai.axiomaster.bonio.remote.gateway.GatewayEndpoint
import ai.axiomaster.bonio.ui.theme.LocalAppColors

/**
 * Server connection settings — reachable from Settings (not a bottom tab).
 * Covers: connection status, local engine, discovered gateways, manual
 * gateway connect with optional TLS + pairing token.
 */
@Composable
fun ServerTab(
  viewModel: MainViewModel,
  onBack: () -> Unit = {},
  modifier: Modifier = Modifier
) {
  val strings = LocalAppStrings.current
  val colors = LocalAppColors.current
  val isConnected by viewModel.isConnected.collectAsState()
  val statusText by viewModel.statusText.collectAsState()
  val remoteAddress by viewModel.remoteAddress.collectAsState()
  val gateways by viewModel.gateways.collectAsState()
  val discoveryText by viewModel.discoveryStatusText.collectAsState()
  val manualTls by viewModel.manualTls.collectAsState()
  val gatewayToken by viewModel.gatewayToken.collectAsState()
  val localEnabled by viewModel.localEnabled.collectAsState()
  val localEngineState by viewModel.localEngineState.collectAsState()
  val pendingTrust by viewModel.pendingGatewayTrust.collectAsState()

  var host by rememberSaveable { mutableStateOf("") }
  var port by rememberSaveable { mutableStateOf("10724") }

  Column(modifier = modifier.fillMaxSize().background(colors.background)) {
    // ── Header (non-tab destination: own back bar) ──
    Row(
      modifier = Modifier
        .windowInsetsPadding(WindowInsets.statusBars)
        .fillMaxWidth()
        .height(48.dp)
        .padding(horizontal = 8.dp),
      verticalAlignment = Alignment.CenterVertically
    ) {
      Icon(
        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
        contentDescription = strings.actionBack,
        tint = colors.textPrimary,
        modifier = Modifier
          .clickable { onBack() }
          .padding(10.dp)
          .size(22.dp)
      )
      Text(
        text = strings.serverConnectionSection,
        fontSize = 17.sp,
        fontWeight = FontWeight.SemiBold,
        color = colors.textPrimary
      )
    }

    Column(
      modifier = Modifier
        .fillMaxSize()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 16.dp),
      verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
      // ── Status card ──
      Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = colors.cardBackground,
        border = BorderStroke(1.dp, colors.border)
      ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
          Text(
            text = if (isConnected) strings.statusConnected else strings.statusOffline,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = if (isConnected) Color(0xFF2ECC71) else Color(0xFFF39C12)
          )
          Text(text = statusText, fontSize = 12.sp, color = colors.textSecondary)
          if (isConnected) {
            val addr = remoteAddress
            if (!addr.isNullOrBlank()) {
              Text(text = addr, fontSize = 12.sp, color = colors.textSecondary)
            }
          }
          if (isConnected) {
            OutlinedButton(
              onClick = { viewModel.disconnect() },
              modifier = Modifier.fillMaxWidth(),
              shape = RoundedCornerShape(8.dp)
            ) {
              Text(strings.serverDisconnectAction, color = Color(0xFFD93025))
            }
          }
        }
      }

      // ── Local engine card ──
      Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = colors.cardBackground,
        border = BorderStroke(1.dp, colors.border)
      ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
          Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
          ) {
            Column(modifier = Modifier.weight(1f).padding(end = 16.dp)) {
              Text(
                text = strings.serverLocalEngine,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = colors.textPrimary
              )
              Text(
                text = strings.serverLocalEngineHint,
                fontSize = 12.sp,
                color = colors.textSecondary,
                modifier = Modifier.padding(top = 2.dp)
              )
            }
            Switch(checked = localEnabled, onCheckedChange = { viewModel.setLocalEnabled(it) })
          }
          Text(
            text = "Engine: $localEngineState",
            fontSize = 12.sp,
            color = if (localEngineState == LocalEngineController.State.Running) Color(0xFF2ECC71) else colors.textSecondary
          )
        }
      }

      // ── Discovered gateways ──
      Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = colors.cardBackground,
        border = BorderStroke(1.dp, colors.border)
      ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
          Text(
            text = strings.serverDiscoveredGateways,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textPrimary
          )
          if (gateways.isEmpty()) {
            Text(
              text = discoveryText,
              fontSize = 12.sp,
              color = colors.textSecondary,
              modifier = Modifier.padding(vertical = 6.dp)
            )
          } else {
            gateways.forEach { gw ->
              Row(
                modifier = Modifier
                  .fillMaxWidth()
                  .clickable { viewModel.connect(gw) }
                  .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
              ) {
                Column(modifier = Modifier.weight(1f)) {
                  Text(
                    text = gw.name,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = colors.textPrimary
                  )
                  Text(
                    text = "${gw.host}:${gw.port}" + if (gw.tlsEnabled) "  ·  TLS" else "",
                    fontSize = 12.sp,
                    color = colors.textSecondary
                  )
                }
                Text(
                  text = strings.serverConnectAction,
                  fontSize = 13.sp,
                  color = colors.accent,
                  fontWeight = FontWeight.Medium
                )
              }
              HorizontalDivider(color = colors.divider, thickness = 0.5.dp)
            }
          }
        }
      }

      // ── Manual gateway ──
      Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = colors.cardBackground,
        border = BorderStroke(1.dp, colors.border)
      ) {
        Column(
          modifier = Modifier.padding(16.dp),
          verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
          Text(
            text = strings.serverAddManual,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textPrimary
          )
          OutlinedTextField(
            value = host,
            onValueChange = { host = it },
            placeholder = { Text(strings.serverHostHint, fontSize = 13.sp) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp)
          )
          OutlinedTextField(
            value = port,
            onValueChange = { port = it.filter { c -> c.isDigit() }.take(5) },
            placeholder = { Text(strings.serverPortHint, fontSize = 13.sp) },
            singleLine = true,
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp)
          )
          Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
          ) {
            Text(strings.serverTlsLabel, fontSize = 14.sp, color = colors.textPrimary)
            Switch(checked = manualTls, onCheckedChange = { viewModel.setManualTls(it) })
          }
          var token by remember(gatewayToken) { mutableStateOf(gatewayToken) }
          OutlinedTextField(
            value = token,
            onValueChange = { token = it },
            placeholder = { Text(strings.serverTokenHint, fontSize = 13.sp) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp)
          )
          Button(
            onClick = {
              viewModel.setManualHost(host.trim())
              viewModel.setManualPort(port.toIntOrNull() ?: 10724)
              if (token.isNotBlank()) viewModel.setGatewayToken(token.trim())
              val endpoint = GatewayEndpoint.manual(host.trim(), port.toIntOrNull() ?: 10724)
              viewModel.connect(endpoint)
            },
            enabled = host.isNotBlank() && (port.toIntOrNull() ?: 0) in 1..65535,
            modifier = Modifier.fillMaxWidth().height(44.dp),
            shape = RoundedCornerShape(10.dp)
          ) {
            Text(strings.serverConnectAction, color = Color.White, fontWeight = FontWeight.Medium)
          }
        }
      }

      Spacer(modifier = Modifier.height(16.dp))
    }
  }

  // ── TLS trust prompt ──
  pendingTrust?.let { prompt ->
    AlertDialog(
      onDismissRequest = { viewModel.declineGatewayTrustPrompt() },
      title = { Text(strings.serverTrustTitle) },
      text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          Text(strings.serverTrustText, fontSize = 14.sp)
          Text(
            text = prompt.fingerprintSha256,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textPrimary
          )
          Text(
            text = prompt.endpoint.name,
            fontSize = 12.sp,
            color = colors.textSecondary
          )
        }
      },
      confirmButton = {
        TextButton(onClick = { viewModel.acceptGatewayTrustPrompt() }) {
          Text(strings.serverTrustAccept, color = colors.accent, fontWeight = FontWeight.Medium)
        }
      },
      dismissButton = {
        TextButton(onClick = { viewModel.declineGatewayTrustPrompt() }) {
          Text(strings.serverDisconnectAction, color = colors.textSecondary)
        }
      }
    )
  }
}
