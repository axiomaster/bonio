package ai.axiomaster.boji.ui.screens

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import ai.axiomaster.boji.BuildConfig
import ai.axiomaster.boji.MainViewModel
import ai.axiomaster.boji.remote.LocationMode
import ai.axiomaster.boji.remote.node.DeviceNotificationListenerService
import ai.axiomaster.boji.ui.screens.chat.*

@Composable
fun SettingsTab(
  viewModel: MainViewModel,
  modifier: Modifier = Modifier
) {
  val context = LocalContext.current
  val lifecycleOwner = LocalLifecycleOwner.current

  // Node settings state
  val instanceId by viewModel.instanceId.collectAsState()
  val displayName by viewModel.displayName.collectAsState()
  val cameraEnabled by viewModel.cameraEnabled.collectAsState()
  val locationMode by viewModel.locationMode.collectAsState()
  val locationPreciseEnabled by viewModel.locationPreciseEnabled.collectAsState()
  val preventSleep by viewModel.preventSleep.collectAsState()
  val canvasDebugStatusEnabled by viewModel.canvasDebugStatusEnabled.collectAsState()

  val listState = rememberLazyListState()
  val deviceModel = remember {
    listOfNotNull(Build.MANUFACTURER, Build.MODEL)
      .joinToString(" ")
      .trim()
      .ifEmpty { "Android" }
  }
  val appVersion = remember {
    val versionName = BuildConfig.VERSION_NAME.trim().ifEmpty { "dev" }
    if (BuildConfig.DEBUG && !versionName.contains("dev", ignoreCase = true)) {
      "$versionName-dev"
    } else {
      versionName
    }
  }

  val listItemColors = ListItemDefaults.colors(
    containerColor = Color.Transparent,
    headlineColor = mobileText,
    supportingColor = mobileTextSecondary,
    trailingIconColor = mobileTextSecondary,
    leadingIconColor = mobileTextSecondary,
  )

  // Permission Launchers
  val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { perms ->
    val cameraOk = perms[Manifest.permission.CAMERA] == true
    viewModel.setCameraEnabled(cameraOk)
  }

  var pendingLocationMode by remember { mutableStateOf<LocationMode?>(null) }
  var pendingPreciseToggle by remember { mutableStateOf(false) }

  val locationPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { perms ->
    val fineOk = perms[Manifest.permission.ACCESS_FINE_LOCATION] == true
    val coarseOk = perms[Manifest.permission.ACCESS_COARSE_LOCATION] == true
    val granted = fineOk || coarseOk
    val requestedMode = pendingLocationMode
    pendingLocationMode = null

    if (pendingPreciseToggle) {
      pendingPreciseToggle = false
      viewModel.setLocationPreciseEnabled(fineOk)
      return@rememberLauncherForActivityResult
    }

    if (!granted) {
      viewModel.setLocationMode(LocationMode.Off)
      return@rememberLauncherForActivityResult
    }

    if (requestedMode != null) {
      viewModel.setLocationMode(requestedMode)
      if (requestedMode == LocationMode.Always && Build.VERSION.SDK_INT >= 29) {
        val backgroundOk = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!backgroundOk) openAppSettings(context)
      }
    }
  }

  var micPermissionGranted by remember {
    mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
  }
  val audioPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    micPermissionGranted = granted
  }

  val smsPermissionAvailable = remember { context.packageManager?.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) == true }
  val photosPermission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE

  var notificationsPermissionGranted by remember { mutableStateOf(hasNotificationsPermission(context)) }
  val notificationsPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    notificationsPermissionGranted = granted
  }

  var notificationListenerEnabled by remember { mutableStateOf(isNotificationListenerEnabled(context)) }
  var photosPermissionGranted by remember {
    mutableStateOf(ContextCompat.checkSelfPermission(context, photosPermission) == PackageManager.PERMISSION_GRANTED)
  }
  val photosPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    photosPermissionGranted = granted
  }

  var contactsPermissionGranted by remember {
    mutableStateOf(
      ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED &&
      ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CONTACTS) == PackageManager.PERMISSION_GRANTED
    )
  }
  val contactsPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { perms ->
    contactsPermissionGranted = perms[Manifest.permission.READ_CONTACTS] == true && perms[Manifest.permission.WRITE_CONTACTS] == true
  }

  var calendarPermissionGranted by remember {
    mutableStateOf(
      ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
      ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
    )
  }
  val calendarPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { perms ->
    calendarPermissionGranted = perms[Manifest.permission.READ_CALENDAR] == true && perms[Manifest.permission.WRITE_CALENDAR] == true
  }

  var motionPermissionGranted by remember {
    mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED)
  }
  val motionPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    motionPermissionGranted = granted
  }

  var appUpdateInstallEnabled by remember { mutableStateOf(canInstallUnknownApps(context)) }

  var smsPermissionGranted by remember {
    mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED)
  }
  val smsPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    smsPermissionGranted = granted
  }

  var overlayPermissionGranted by remember {
    mutableStateOf(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(context) else true)
  }

  DisposableEffect(lifecycleOwner, context) {
    val observer = LifecycleEventObserver { _, event ->
      if (event == Lifecycle.Event.ON_RESUME) {
        micPermissionGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        notificationsPermissionGranted = hasNotificationsPermission(context)
        notificationListenerEnabled = isNotificationListenerEnabled(context)
        photosPermissionGranted = ContextCompat.checkSelfPermission(context, photosPermission) == PackageManager.PERMISSION_GRANTED
        contactsPermissionGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED &&
                                     ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CONTACTS) == PackageManager.PERMISSION_GRANTED
        calendarPermissionGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
                                     ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
        motionPermissionGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        appUpdateInstallEnabled = canInstallUnknownApps(context)
        smsPermissionGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
        overlayPermissionGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(context) else true
      }
    }
    lifecycleOwner.lifecycle.addObserver(observer)
    onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
  }

  fun setCameraEnabledChecked(checked: Boolean) {
    if (!checked) {
      viewModel.setCameraEnabled(false)
      return
    }
    val cameraOk = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    if (cameraOk) {
      viewModel.setCameraEnabled(true)
    } else {
      permissionLauncher.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
    }
  }

  fun requestLocationPermissions(targetMode: LocationMode) {
    val fineOk = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    val coarseOk = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    if (fineOk || coarseOk) {
      viewModel.setLocationMode(targetMode)
      if (targetMode == LocationMode.Always && Build.VERSION.SDK_INT >= 29) {
        val backgroundOk = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!backgroundOk) openAppSettings(context)
      }
    } else {
      pendingLocationMode = targetMode
      locationPermissionLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
    }
  }

  fun setPreciseLocationChecked(checked: Boolean) {
    if (!checked) {
      viewModel.setLocationPreciseEnabled(false)
      return
    }
    val fineOk = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    if (fineOk) {
      viewModel.setLocationPreciseEnabled(true)
    } else {
      pendingPreciseToggle = true
      locationPermissionLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION))
    }
  }

  Box(modifier = modifier.fillMaxSize().background(mobileBackgroundGradient)) {
    LazyColumn(
      state = listState,
      modifier = Modifier.fillMaxSize().imePadding().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom)),
      contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
      verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
      item {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
          Text("SETTINGS", style = mobileCaption1.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.sp), color = mobileAccent)
          Text("Device Configuration", style = mobileTitle2, color = mobileText)
          Text("Manage capabilities, permissions, and diagnostics.", style = mobileCallout, color = mobileTextSecondary)
        }
      }

      item { HorizontalDivider(color = mobileBorder) }

      // FLOATING WINDOW
      item { CategoryHeader("FLOATING WINDOW") }
      item {
        PermissionRow(
          title = "Overlay Permission",
          description = if (overlayPermissionGranted) "Granted. BoJi can run as a desktop assistant." else "BoJi needs to 'Display over other apps' to be a virtual assistant.",
          buttonLabel = if (overlayPermissionGranted) "Manage" else "Grant",
          onClick = {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
              Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
            } else {
              Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
            }
            context.startActivity(intent)
          },
          colors = listItemColors
        )
      }

      item { HorizontalDivider(color = mobileBorder) }

      // NODE
      item { CategoryHeader("NODE") }
      item {
        OutlinedTextField(
          value = displayName,
          onValueChange = viewModel::setDisplayName,
          label = { Text("Name", style = mobileCaption1, color = mobileTextSecondary) },
          modifier = Modifier.fillMaxWidth(),
          textStyle = mobileBody.copy(color = mobileText),
          colors = settingsTextFieldColors(),
        )
      }
      item { Text("Instance ID: $instanceId", style = mobileCallout.copy(fontFamily = FontFamily.Monospace), color = mobileTextSecondary) }
      item { Text("Device: $deviceModel", style = mobileCallout, color = mobileTextSecondary) }
      item { Text("Version: $appVersion", style = mobileCallout, color = mobileTextSecondary) }

      item { HorizontalDivider(color = mobileBorder) }

      // VOICE
      item { CategoryHeader("VOICE") }
      item {
        PermissionRow(
          title = "Microphone permission",
          description = if (micPermissionGranted) "Granted. Use the Voice tab mic button." else "Required for Voice tab transcription.",
          buttonLabel = if (micPermissionGranted) "Manage" else "Grant",
          onClick = { if (micPermissionGranted) openAppSettings(context) else audioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
          colors = listItemColors
        )
      }

      item { HorizontalDivider(color = mobileBorder) }

      // CAMERA
      item { CategoryHeader("CAMERA") }
      item {
        SwitchRow(
          title = "Allow Camera",
          description = "Allows the gateway to request photos or short video clips.",
          checked = cameraEnabled,
          onCheckedChange = ::setCameraEnabledChecked,
          colors = listItemColors
        )
      }

      item { HorizontalDivider(color = mobileBorder) }

      // MESSAGING
      item { CategoryHeader("MESSAGING") }
      item {
        PermissionRow(
          title = "SMS Permission",
          description = if (smsPermissionAvailable) "Allow the gateway to send SMS." else "SMS requires telephony hardware.",
          buttonLabel = if (smsPermissionAvailable) (if (smsPermissionGranted) "Manage" else "Grant") else "Unavailable",
          enabled = smsPermissionAvailable,
          onClick = { if (smsPermissionGranted) openAppSettings(context) else smsPermissionLauncher.launch(Manifest.permission.SEND_SMS) },
          colors = listItemColors
        )
      }

      item { HorizontalDivider(color = mobileBorder) }

      // NOTIFICATIONS
      item { CategoryHeader("NOTIFICATIONS") }
      item {
        PermissionRow(
          title = "System Notifications",
          description = "Required for `system.notify` and foreground service alerts.",
          buttonLabel = if (notificationsPermissionGranted) "Manage" else "Grant",
          onClick = {
            if (notificationsPermissionGranted || Build.VERSION.SDK_INT < 33) openAppSettings(context)
            else notificationsPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
          },
          colors = listItemColors
        )
      }
      item {
        PermissionRow(
          title = "Notification Listener Access",
          description = "Required for `notifications.list` and `notifications.actions`.",
          buttonLabel = if (notificationListenerEnabled) "Manage" else "Enable",
          onClick = { openNotificationListenerSettings(context) },
          colors = listItemColors
        )
      }

      item { HorizontalDivider(color = mobileBorder) }

      // DATA ACCESS
      item { CategoryHeader("DATA ACCESS") }
      item {
        PermissionRow(
          title = "Photos Permission",
          description = "Required for `photos.latest`.",
          buttonLabel = if (photosPermissionGranted) "Manage" else "Grant",
          onClick = { if (photosPermissionGranted) openAppSettings(context) else photosPermissionLauncher.launch(photosPermission) },
          colors = listItemColors
        )
      }
      item {
        PermissionRow(
          title = "Contacts Permission",
          description = "Required for `contacts.search` and `contacts.add`.",
          buttonLabel = if (contactsPermissionGranted) "Manage" else "Grant",
          onClick = {
            if (contactsPermissionGranted) openAppSettings(context)
            else contactsPermissionLauncher.launch(arrayOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS))
          },
          colors = listItemColors
        )
      }
      item {
        PermissionRow(
          title = "Calendar Permission",
          description = "Required for `calendar.events` and `calendar.add`.",
          buttonLabel = if (calendarPermissionGranted) "Manage" else "Grant",
          onClick = {
            if (calendarPermissionGranted) openAppSettings(context)
            else calendarPermissionLauncher.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR))
          },
          colors = listItemColors
        )
      }
      item {
        PermissionRow(
          title = "Motion Permission",
          description = "Required for `motion.activity` and `motion.pedometer`.",
          buttonLabel = if (motionPermissionGranted) "Manage" else "Grant",
          onClick = { if (motionPermissionGranted) openAppSettings(context) else motionPermissionLauncher.launch(Manifest.permission.ACTIVITY_RECOGNITION) },
          colors = listItemColors
        )
      }

      item { HorizontalDivider(color = mobileBorder) }

      // SYSTEM
      item { CategoryHeader("SYSTEM") }
      item {
        PermissionRow(
          title = "Install App Updates",
          description = "Enable install access for `app.update` package installs.",
          buttonLabel = if (appUpdateInstallEnabled) "Manage" else "Enable",
          onClick = { openUnknownAppSourcesSettings(context) },
          colors = listItemColors
        )
      }

      item { HorizontalDivider(color = mobileBorder) }

      // LOCATION
      item { CategoryHeader("LOCATION") }
      item {
        Column(modifier = Modifier.settingsRowModifier()) {
          LocationOption("Off", "Disable location sharing.", locationMode == LocationMode.Off, { viewModel.setLocationMode(LocationMode.Off) }, listItemColors)
          HorizontalDivider(color = mobileBorder)
          LocationOption("While Using", "Only while BoJi is open.", locationMode == LocationMode.WhileUsing, { requestLocationPermissions(LocationMode.WhileUsing) }, listItemColors)
          HorizontalDivider(color = mobileBorder)
          LocationOption("Always", "Allow background location.", locationMode == LocationMode.Always, { requestLocationPermissions(LocationMode.Always) }, listItemColors)
          HorizontalDivider(color = mobileBorder)
          SwitchRow(
            title = "Precise Location",
            description = "Use precise GPS when available.",
            checked = locationPreciseEnabled,
            onCheckedChange = ::setPreciseLocationChecked,
            enabled = locationMode != LocationMode.Off,
            colors = listItemColors
          )
        }
      }

      item { HorizontalDivider(color = mobileBorder) }

      // SCREEN
      item { CategoryHeader("SCREEN") }
      item {
        SwitchRow(
          title = "Prevent Sleep",
          description = "Keeps the screen awake while BoJi is open.",
          checked = preventSleep,
          onCheckedChange = viewModel::setPreventSleep,
          colors = listItemColors
        )
      }

      item { HorizontalDivider(color = mobileBorder) }

      // DEBUG
      item { CategoryHeader("DEBUG") }
      item {
        SwitchRow(
          title = "Debug Canvas Status",
          description = "Show status text in the canvas.",
          checked = canvasDebugStatusEnabled,
          onCheckedChange = viewModel::setCanvasDebugStatusEnabled,
          colors = listItemColors
        )
      }

      item { Spacer(modifier = Modifier.height(24.dp)) }
    }
  }
}

@Composable
private fun CategoryHeader(text: String) {
  Text(text, style = mobileCaption1.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.sp), color = mobileAccent)
}

@Composable
private fun PermissionRow(title: String, description: String, buttonLabel: String, onClick: () -> Unit, colors: ListItemColors, enabled: Boolean = true) {
  ListItem(
    modifier = Modifier.settingsRowModifier(),
    colors = colors,
    headlineContent = { Text(title, style = mobileHeadline) },
    supportingContent = { Text(description, style = mobileCallout) },
    trailingContent = {
      Button(onClick = onClick, enabled = enabled, colors = settingsPrimaryButtonColors(), shape = RoundedCornerShape(14.dp)) {
        Text(buttonLabel, style = mobileCallout.copy(fontWeight = FontWeight.Bold))
      }
    }
  )
}

@Composable
private fun SwitchRow(title: String, description: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit, colors: ListItemColors, enabled: Boolean = true) {
  ListItem(
    modifier = Modifier.settingsRowModifier(),
    colors = colors,
    headlineContent = { Text(title, style = mobileHeadline) },
    supportingContent = { Text(description, style = mobileCallout) },
    trailingContent = { Switch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled) }
  )
}

@Composable
private fun LocationOption(title: String, description: String, selected: Boolean, onClick: () -> Unit, colors: ListItemColors) {
  ListItem(
    modifier = Modifier.fillMaxWidth(),
    colors = colors,
    headlineContent = { Text(title, style = mobileHeadline) },
    supportingContent = { Text(description, style = mobileCallout) },
    trailingContent = { RadioButton(selected = selected, onClick = onClick) }
  )
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

private fun Modifier.settingsRowModifier() = this
  .fillMaxWidth()
  .border(width = 1.dp, color = mobileBorder, shape = RoundedCornerShape(14.dp))
  .background(Color.White, RoundedCornerShape(14.dp))

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

private fun openAppSettings(context: Context) {
  val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
  context.startActivity(intent)
}

private fun openNotificationListenerSettings(context: Context) {
  val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
  runCatching { context.startActivity(intent) }.getOrElse { openAppSettings(context) }
}

private fun openUnknownAppSourcesSettings(context: Context) {
  val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, "package:${context.packageName}".toUri())
  runCatching { context.startActivity(intent) }.getOrElse { openAppSettings(context) }
}

private fun hasNotificationsPermission(context: Context): Boolean {
  if (Build.VERSION.SDK_INT < 33) return true
  return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
}

private fun isNotificationListenerEnabled(context: Context): Boolean {
  return DeviceNotificationListenerService.isAccessEnabled(context)
}

private fun canInstallUnknownApps(context: Context): Boolean {
  return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
    context.packageManager.canRequestPackageInstalls()
  } else {
    true
  }
}
