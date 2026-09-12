package ai.axiomaster.bonio.ui.screens

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import ai.axiomaster.bonio.BuildConfig
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.remote.LocationMode

@Composable
fun SettingsTab(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    // Connection states
    val isConnected by viewModel.isConnected.collectAsState()
    val statusText by viewModel.statusText.collectAsState()
    val manualHost by viewModel.manualHost.collectAsState()
    val manualPort by viewModel.manualPort.collectAsState()
    val manualTls by viewModel.manualTls.collectAsState()
    val gatewayToken by viewModel.gatewayToken.collectAsState()
    val localEnabled by viewModel.localEnabled.collectAsState()
    val localEngineState by viewModel.localEngineState.collectAsState()

    var hostInput by remember(manualHost) { mutableStateOf(manualHost) }
    var portInput by remember(manualPort) { mutableStateOf(manualPort.toString()) }
    var tokenInput by remember(gatewayToken) { mutableStateOf(gatewayToken) }
    var tlsInput by remember(manualTls) { mutableStateOf(manualTls) }

    // Floating window state
    val showAvatarOverlay by viewModel.showAvatarOverlay.collectAsState()
    var overlayPermissionGranted by remember {
        mutableStateOf(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(context) else true)
    }

    // Permission states
    val cameraEnabled by viewModel.cameraEnabled.collectAsState()
    val locationMode by viewModel.locationMode.collectAsState()

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { perms ->
        val cameraOk = perms[Manifest.permission.CAMERA] == true
        viewModel.setCameraEnabled(cameraOk)
    }

    val locationPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { perms ->
        val fineOk = perms[Manifest.permission.ACCESS_FINE_LOCATION] == true
        val coarseOk = perms[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (fineOk || coarseOk) {
            viewModel.setLocationMode(LocationMode.WhileUsing)
        } else {
            viewModel.setLocationMode(LocationMode.Off)
        }
    }

    var micPermissionGranted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
    }
    val audioPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        micPermissionGranted = granted
    }

    val screenRecordActive by viewModel.screenRecordActive.collectAsState()
    var screenAwarenessEnabled by remember { mutableStateOf(true) }

    val instanceId by viewModel.instanceId.collectAsState()
    val deviceModel = remember {
        listOfNotNull(Build.MANUFACTURER, Build.MODEL).joinToString(" ").trim().ifEmpty { "Android" }
    }
    val appVersion = remember {
        BuildConfig.VERSION_NAME.trim().ifEmpty { "1.0.0" }
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFFFAFAFA))
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 32.dp)
    ) {
        // ── 1. Gateway Connection Section ──
        item { SectionHeader(title = "Gateway Connection") }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White,
                border = BorderStroke(1.dp, Color(0xFFE5E6EB))
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = "Status: $statusText",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (isConnected) Color(0xFF2ECC71) else Color(0xFF333333)
                    )

                    OutlinedTextField(
                        value = hostInput,
                        onValueChange = {
                            hostInput = it
                            viewModel.setManualHost(it)
                        },
                        placeholder = { Text("Gateway Host (e.g. 192.168.1.100)", fontSize = 13.sp) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(8.dp)
                    )

                    OutlinedTextField(
                        value = portInput,
                        onValueChange = {
                            portInput = it
                            it.toIntOrNull()?.let { p -> viewModel.setManualPort(p) }
                        },
                        placeholder = { Text("Port (e.g. 10724)", fontSize = 13.sp) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(8.dp)
                    )

                    OutlinedTextField(
                        value = tokenInput,
                        onValueChange = {
                            tokenInput = it
                            viewModel.setGatewayToken(it)
                        },
                        placeholder = { Text("Token (optional)", fontSize = 13.sp) },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(8.dp)
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Enable TLS", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color(0xFF333333))
                        Switch(
                            checked = tlsInput,
                            onCheckedChange = {
                                tlsInput = it
                                viewModel.setManualTls(it)
                            },
                            colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = Color(0xFF0A59F7))
                        )
                    }

                    Button(
                        onClick = {
                            if (isConnected) {
                                viewModel.disconnect()
                            } else {
                                viewModel.connectManual()
                            }
                        },
                        modifier = Modifier.fillMaxWidth().height(44.dp),
                        shape = RoundedCornerShape(10.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (isConnected) Color(0xFFE53935) else Color(0xFF0A59F7)
                        )
                    ) {
                        Text(
                            text = if (isConnected) "Disconnect" else "Connect",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }

                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)

                    Row(
                        modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text("启用本地引擎 (Embedded)", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color(0xFF333333))
                            Text("Engine: $localEngineState", fontSize = 11.sp, color = if (localEngineState.name == "Running") Color(0xFF2ECC71) else Color(0xFF999999))
                        }
                        Switch(
                            checked = localEnabled,
                            onCheckedChange = { viewModel.setLocalEnabled(it) },
                            colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = Color(0xFF0A59F7))
                        )
                    }
                }
            }
        }

        // ── 2. Floating Window Section ──
        item { SectionHeader(title = "Floating Window") }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White,
                border = BorderStroke(1.dp, Color(0xFFE5E6EB))
            ) {
                ToggleRow(
                    title = "Enable Avatar Overlay",
                    subtitle = "Floating desktop pet and Magic Cue companion",
                    isOn = showAvatarOverlay,
                    onToggle = { enable ->
                        if (enable && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
                            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                            context.startActivity(intent)
                        } else {
                            viewModel.setShowAvatarOverlay(enable)
                        }
                    }
                )
            }
        }

        // ── 3. System Permissions Section ──
        item { SectionHeader(title = "System Permissions") }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White,
                border = BorderStroke(1.dp, Color(0xFFE5E6EB))
            ) {
                Column {
                    ToggleRow(
                        title = "Location",
                        subtitle = "GPS location sharing",
                        isOn = locationMode != LocationMode.Off,
                        onToggle = { enable ->
                            if (enable) {
                                val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                                if (fine) viewModel.setLocationMode(LocationMode.WhileUsing)
                                else locationPermissionLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                            } else {
                                viewModel.setLocationMode(LocationMode.Off)
                            }
                        }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    ToggleRow(
                        title = "Voice Wake",
                        subtitle = "Wake word listening",
                        isOn = micPermissionGranted,
                        onToggle = { enable ->
                            if (enable) audioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                            else micPermissionGranted = false
                        }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    ToggleRow(
                        title = "Camera Access",
                        subtitle = "Allow remote photo/video",
                        isOn = cameraEnabled,
                        onToggle = { enable ->
                            if (enable) permissionLauncher.launch(arrayOf(Manifest.permission.CAMERA))
                            else viewModel.setCameraEnabled(false)
                        }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    ToggleRow(
                        title = "Screen Recording",
                        subtitle = "Allow remote screen view",
                        isOn = screenRecordActive,
                        onToggle = { /* Managed dynamically by screen recording session */ }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    ToggleRow(
                        title = "Screen Awareness",
                        subtitle = "Allow on-demand reading of the current page",
                        isOn = screenAwarenessEnabled,
                        onToggle = { screenAwarenessEnabled = it }
                    )
                }
            }
        }

        // ── 4. Device Information Section ──
        item { SectionHeader(title = "Device Information") }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White,
                border = BorderStroke(1.dp, Color(0xFFE5E6EB))
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    InfoRow(label = "Device", value = deviceModel)
                    InfoRow(label = "Instance ID", value = instanceId.take(12) + "...")
                    InfoRow(label = "Version", value = appVersion)
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        fontSize = 13.sp,
        fontWeight = FontWeight.Medium,
        color = Color(0xFF0A59F7),
        modifier = Modifier.padding(top = 10.dp, bottom = 4.dp)
    )
}

@Composable
private fun ToggleRow(
    title: String,
    subtitle: String,
    isOn: Boolean,
    onToggle: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color(0xFF333333))
            Text(subtitle, fontSize = 12.sp, color = Color(0xFF999999), modifier = Modifier.padding(top = 2.dp))
        }
        Switch(
            checked = isOn,
            onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = Color(0xFF0A59F7))
        )
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 13.sp, color = Color(0xFF999999))
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Color(0xFF333333))
    }
}
