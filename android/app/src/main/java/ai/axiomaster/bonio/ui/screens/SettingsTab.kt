package ai.axiomaster.bonio.ui.screens

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import ai.axiomaster.bonio.BuildConfig
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.i18n.AppLanguage
import ai.axiomaster.bonio.i18n.LocalAppStrings
import ai.axiomaster.bonio.remote.LocationMode
import ai.axiomaster.bonio.ui.theme.LocalAppColors
import ai.axiomaster.bonio.ui.theme.ThemeMode

@Composable
fun SettingsTab(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val strings = LocalAppStrings.current
    val colors = LocalAppColors.current
    val clipboardManager = LocalClipboardManager.current

    // App Theme state
    val currentThemeMode by viewModel.themeMode.collectAsState()

    // App Language state
    val currentLanguage by viewModel.appLanguage.collectAsState()

    // Connection states
    val isConnected by viewModel.isConnected.collectAsState()

    // Voice & Audio
    val isSpeakerEnabled by viewModel.isSpeakerEnabled.collectAsState()

    // Floating window state
    val showAvatarOverlay by viewModel.showAvatarOverlay.collectAsState()

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

    val screenRecordEnabled by viewModel.screenRecordEnabled.collectAsState()
    val mediaProjectionManager = remember {
        context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }
    val screenCaptureLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == android.app.Activity.RESULT_OK && result.data != null) {
            viewModel.onScreenCaptureAuthorized(result.resultCode, result.data!!)
            Toast.makeText(context, strings.screenRecordGrantedToast, Toast.LENGTH_SHORT).show()
        } else {
            viewModel.onScreenCaptureRevoked()
            Toast.makeText(context, strings.screenRecordDeniedToast, Toast.LENGTH_SHORT).show()
        }
    }
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
            .background(colors.background)
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 32.dp)
    ) {
        // ── 1. Theme Setting Section ──
        item { SectionHeader(title = strings.themeSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = colors.cardBackground,
                border = BorderStroke(1.dp, colors.border)
            ) {
                Column {
                    ThemeOptionRow(
                        title = strings.themeSystem,
                        isSelected = currentThemeMode == ThemeMode.SYSTEM,
                        onClick = { viewModel.setThemeMode(ThemeMode.SYSTEM) }
                    )
                    HorizontalDivider(color = colors.divider, thickness = 0.5.dp)
                    ThemeOptionRow(
                        title = strings.themeLight,
                        isSelected = currentThemeMode == ThemeMode.LIGHT,
                        onClick = { viewModel.setThemeMode(ThemeMode.LIGHT) }
                    )
                    HorizontalDivider(color = colors.divider, thickness = 0.5.dp)
                    ThemeOptionRow(
                        title = strings.themeDark,
                        isSelected = currentThemeMode == ThemeMode.DARK,
                        onClick = { viewModel.setThemeMode(ThemeMode.DARK) }
                    )
                }
            }
        }

        // ── 2. Language Setting Section ──
        item { SectionHeader(title = strings.languageSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = colors.cardBackground,
                border = BorderStroke(1.dp, colors.border)
            ) {
                Column {
                    LanguageOptionRow(
                        title = strings.languageChinese,
                        isSelected = currentLanguage == AppLanguage.ZH,
                        onClick = { viewModel.setAppLanguage(AppLanguage.ZH) }
                    )
                    HorizontalDivider(color = colors.divider, thickness = 0.5.dp)
                    LanguageOptionRow(
                        title = strings.languageEnglish,
                        isSelected = currentLanguage == AppLanguage.EN,
                        onClick = { viewModel.setAppLanguage(AppLanguage.EN) }
                    )
                }
            }
        }

        // ── 3. Voice & Audio Section ──
        item { SectionHeader(title = strings.voiceSettingsSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = colors.cardBackground,
                border = BorderStroke(1.dp, colors.border)
            ) {
                ToggleRow(
                    title = strings.ttsSettingTitle,
                    subtitle = strings.ttsSettingDesc,
                    isOn = isSpeakerEnabled,
                    onToggle = { viewModel.setSpeakerEnabled(it) }
                )
            }
        }

        // ── 4. Floating Window Section ──
        item { SectionHeader(title = if (currentLanguage == AppLanguage.ZH) "悬浮窗口" else "Floating Window") }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = colors.cardBackground,
                border = BorderStroke(1.dp, colors.border)
            ) {
                ToggleRow(
                    title = if (currentLanguage == AppLanguage.ZH) "启用桌面宠物悬浮窗" else "Enable Avatar Overlay",
                    subtitle = if (currentLanguage == AppLanguage.ZH) "常驻桌面互动与交互" else "Floating desktop pet and companion",
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

        // ── 5. System Permissions Section ──
        item { SectionHeader(title = strings.permissionsSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = colors.cardBackground,
                border = BorderStroke(1.dp, colors.border)
            ) {
                Column {
                    ToggleRow(
                        title = strings.permLocationTitle,
                        subtitle = strings.permLocationDesc,
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
                    HorizontalDivider(color = colors.divider, thickness = 0.5.dp)
                    ToggleRow(
                        title = strings.permMicTitle,
                        subtitle = strings.permMicDesc,
                        isOn = micPermissionGranted,
                        onToggle = { enable ->
                            if (enable) audioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                            else micPermissionGranted = false
                        }
                    )
                    HorizontalDivider(color = colors.divider, thickness = 0.5.dp)
                    ToggleRow(
                        title = strings.permCameraTitle,
                        subtitle = strings.permCameraDesc,
                        isOn = cameraEnabled,
                        onToggle = { enable ->
                            if (enable) permissionLauncher.launch(arrayOf(Manifest.permission.CAMERA))
                            else viewModel.setCameraEnabled(false)
                        }
                    )
                    HorizontalDivider(color = colors.divider, thickness = 0.5.dp)
                    ToggleRow(
                        title = strings.permScreenRecordTitle,
                        subtitle = strings.permScreenRecordDesc,
                        isOn = screenRecordEnabled,
                        onToggle = { enable ->
                            if (enable) {
                                val intent = mediaProjectionManager.createScreenCaptureIntent()
                                screenCaptureLauncher.launch(intent)
                            } else {
                                viewModel.onScreenCaptureRevoked()
                            }
                        }
                    )
                    HorizontalDivider(color = colors.divider, thickness = 0.5.dp)
                    ToggleRow(
                        title = strings.permScreenAwarenessTitle,
                        subtitle = strings.permScreenAwarenessDesc,
                        isOn = screenAwarenessEnabled,
                        onToggle = { screenAwarenessEnabled = it }
                    )
                }
            }
        }

        // ── 6. About & Device Information Section ──
        item { SectionHeader(title = strings.aboutSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = colors.cardBackground,
                border = BorderStroke(1.dp, colors.border)
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    InfoRow(
                        label = strings.gatewayStatus,
                        value = if (isConnected) strings.statusConnected else strings.statusOffline,
                        valueColor = if (isConnected) Color(0xFF2ECC71) else Color(0xFFF39C12)
                    )
                    InfoRow(
                        label = if (currentLanguage == AppLanguage.ZH) "设备型号" else "Device",
                        value = deviceModel
                    )
                    InfoRow(
                        label = strings.appVersion,
                        value = appVersion
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(strings.deviceId, fontSize = 13.sp, color = colors.textSecondary)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.clickable {
                                clipboardManager.setText(AnnotatedString(instanceId))
                                Toast.makeText(context, strings.copySuccess, Toast.LENGTH_SHORT).show()
                            }
                        ) {
                            Text(
                                text = if (instanceId.length > 16) instanceId.take(16) + "..." else instanceId,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                color = colors.textPrimary
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Icon(
                                imageVector = Icons.Default.ContentCopy,
                                contentDescription = "Copy",
                                tint = colors.accent,
                                modifier = Modifier.size(14.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ThemeOptionRow(
    title: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val colors = LocalAppColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = title,
            fontSize = 15.sp,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isSelected) colors.accent else colors.textPrimary
        )
        if (isSelected) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = "Selected",
                tint = colors.accent,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
private fun LanguageOptionRow(
    title: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val colors = LocalAppColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = title,
            fontSize = 15.sp,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isSelected) colors.accent else colors.textPrimary
        )
        if (isSelected) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = "Selected",
                tint = colors.accent,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    val colors = LocalAppColors.current
    Text(
        text = title,
        fontSize = 13.sp,
        fontWeight = FontWeight.Medium,
        color = colors.accent,
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
    val colors = LocalAppColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onToggle(!isOn) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
            Text(subtitle, fontSize = 12.sp, color = colors.textSecondary, modifier = Modifier.padding(top = 2.dp))
        }
        Switch(
            checked = isOn,
            onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = colors.accent,
                uncheckedThumbColor = colors.surfaceVariant,
                uncheckedTrackColor = colors.border
            )
        )
    }
}

@Composable
private fun InfoRow(
    label: String,
    value: String,
    valueColor: Color? = null
) {
    val colors = LocalAppColors.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 13.sp, color = colors.textSecondary)
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = valueColor ?: colors.textPrimary)
    }
}
