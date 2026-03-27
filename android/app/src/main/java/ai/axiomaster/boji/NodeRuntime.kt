package ai.axiomaster.boji

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import ai.axiomaster.boji.remote.chat.ChatController
import ai.axiomaster.boji.remote.gateway.DeviceAuthStore
import ai.axiomaster.boji.remote.gateway.DeviceIdentityStore
import ai.axiomaster.boji.remote.gateway.GatewayDiscovery
import ai.axiomaster.boji.remote.gateway.GatewayEndpoint
import ai.axiomaster.boji.remote.gateway.GatewaySession
import ai.axiomaster.boji.remote.gateway.probeGatewayTlsFingerprint
import ai.axiomaster.boji.remote.node.*
import ai.axiomaster.boji.remote.LocationMode
import ai.axiomaster.boji.remote.VoiceWakeMode
import ai.axiomaster.boji.remote.SecurePrefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

class NodeRuntime(context: Context) {
  private val appContext = context.applicationContext
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

  val prefs = SecurePrefs(appContext)
  private val deviceAuthStore = DeviceAuthStore(prefs)
  val canvas = CanvasController()
  val screenRecorder = ScreenRecordManager(appContext)
  private val json = Json { ignoreUnknownKeys = true }

  private val discovery = GatewayDiscovery(appContext, scope = scope)
  val gateways: StateFlow<List<GatewayEndpoint>> = discovery.gateways
  val discoveryStatusText: StateFlow<String> = discovery.statusText

  private val identityStore = DeviceIdentityStore(appContext)
  private var connectedEndpoint: GatewayEndpoint? = null

  private val cameraHandler = CameraHandlerImpl(appContext)
  private val locationHandler = LocationHandlerImpl(appContext)
  private val deviceHandler = DeviceHandlerImpl(appContext)
  private val notificationsHandler = NotificationsHandlerImpl(appContext)
  private val systemHandler = SystemHandler()
  private val photosHandler = PhotosHandler()
  private val contactsHandler = ContactsHandler()
  private val calendarHandler = CalendarHandler()
  private val motionHandler = MotionHandler()
  private val smsHandler = SmsHandler()
  private val debugHandler = DebugHandler()
  private val appUpdateHandler = AppUpdateHandler()

  private val screenHandler: ScreenHandler = ScreenHandler(
    screenRecorder = screenRecorder,
    setScreenRecordActive = { _screenRecordActive.value = it },
    invokeErrorFromThrowable = { invokeErrorFromThrowable(it) },
  )

  private val a2uiHandler: A2UIHandler = A2UIHandler(
    canvas = canvas,
    json = json,
    getNodeCanvasHostUrl = { nodeSession.currentCanvasHostUrl() },
    getOperatorCanvasHostUrl = { operatorSession.currentCanvasHostUrl() },
  )

  private val connectionManager: ConnectionManager = ConnectionManager(
    prefs = prefs,
    cameraEnabled = { cameraEnabled.value },
    locationMode = { locationMode.value },
    voiceWakeMode = { VoiceWakeMode.Off },
    motionActivityAvailable = { false },
    motionPedometerAvailable = { false },
    smsAvailable = { false },
    hasRecordAudioPermission = { hasRecordAudioPermission() },
    manualTls = { manualTls.value },
  )

  private val invokeDispatcher: InvokeDispatcher = InvokeDispatcher(
    canvas = canvas,
    cameraHandler = cameraHandler,
    locationHandler = locationHandler,
    deviceHandler = deviceHandler,
    notificationsHandler = notificationsHandler,
    systemHandler = systemHandler,
    photosHandler = photosHandler,
    contactsHandler = contactsHandler,
    calendarHandler = calendarHandler,
    motionHandler = motionHandler,
    screenHandler = screenHandler,
    smsHandler = smsHandler,
    a2uiHandler = a2uiHandler,
    debugHandler = debugHandler,
    appUpdateHandler = appUpdateHandler,
    isForeground = { _isForeground.value },
    cameraEnabled = { cameraEnabled.value },
    locationEnabled = { locationMode.value != LocationMode.Off },
    smsAvailable = { false },
    debugBuild = { true },
    refreshNodeCanvasCapability = { nodeSession.refreshNodeCanvasCapability() },
    onCanvasA2uiPush = {
      _canvasA2uiHydrated.value = true
      _canvasRehydratePending.value = false
      _canvasRehydrateErrorText.value = null
    },
    onCanvasA2uiReset = { _canvasA2uiHydrated.value = false },
    motionActivityAvailable = { false },
    motionPedometerAvailable = { false },
  )

  private val _isConnected = MutableStateFlow(false)
  val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()
  private val _nodeConnected = MutableStateFlow(false)
  val nodeConnected: StateFlow<Boolean> = _nodeConnected.asStateFlow()

  private val _statusText = MutableStateFlow("Offline")
  val statusText: StateFlow<String> = _statusText.asStateFlow()

  private val _pendingGatewayTrust = MutableStateFlow<GatewayTrustPrompt?>(null)
  val pendingGatewayTrust: StateFlow<GatewayTrustPrompt?> = _pendingGatewayTrust.asStateFlow()

  private val _mainSessionKey = MutableStateFlow("main")
  val mainSessionKey: StateFlow<String> = _mainSessionKey.asStateFlow()

  private val _cameraHud = MutableStateFlow<CameraHudState?>(null)
  val cameraHud: StateFlow<CameraHudState?> = _cameraHud.asStateFlow()

  private val _screenRecordActive = MutableStateFlow(false)
  val screenRecordActive: StateFlow<Boolean> = _screenRecordActive.asStateFlow()

  private val _canvasA2uiHydrated = MutableStateFlow(false)
  val canvasA2uiHydrated: StateFlow<Boolean> = _canvasA2uiHydrated.asStateFlow()
  private val _canvasRehydratePending = MutableStateFlow(false)
  val canvasRehydratePending: StateFlow<Boolean> = _canvasRehydratePending.asStateFlow()
  private val _canvasRehydrateErrorText = MutableStateFlow<String?>(null)
  val canvasRehydrateErrorText: StateFlow<String?> = _canvasRehydrateErrorText.asStateFlow()

  private val _serverName = MutableStateFlow<String?>(null)
  val serverName: StateFlow<String?> = _serverName.asStateFlow()
  private val _remoteAddress = MutableStateFlow<String?>(null)
  val remoteAddress: StateFlow<String?> = _remoteAddress.asStateFlow()
  private val _seamColorArgb = MutableStateFlow(DEFAULT_SEAM_COLOR_ARGB)
  val seamColorArgb: StateFlow<Long> = _seamColorArgb.asStateFlow()

  private val _isForeground = MutableStateFlow(true)
  val isForeground: StateFlow<Boolean> = _isForeground.asStateFlow()

  private var operatorConnected = false
  private var operatorStatusText: String = "Offline"
  private var nodeStatusText: String = "Offline"

  data class GatewayTrustPrompt(val endpoint: GatewayEndpoint, val fingerprintSha256: String)

  private val operatorSession =
    GatewaySession(
      scope = scope,
      identityStore = identityStore,
      deviceAuthStore = deviceAuthStore,
      onConnected = { name, remote, mainSessionKey ->
        operatorConnected = true
        operatorStatusText = "Connected"
        _serverName.value = name
        _remoteAddress.value = remote
        applyMainSessionKey(mainSessionKey)
        chat.refresh()
        updateStatus()
        Log.i("BoJi", "Operator connected: $name ($remote)")
        scope.launch { refreshBrandingFromGateway() }
      },
      onDisconnected = { message ->
        operatorConnected = false
        operatorStatusText = message
        _serverName.value = null
        _remoteAddress.value = null
        if (!isCanonicalMainSessionKey(_mainSessionKey.value)) _mainSessionKey.value = "main"
        chat.applyMainSessionKey(resolveMainSessionKey())
        chat.onDisconnected(message)
        updateStatus()
      },
      onEvent = { event, payloadJson ->
        if (event == "agent.action.step" && payloadJson != null) {
          handleAgentActionStep(payloadJson)
        }
        chat.handleGatewayEvent(event, payloadJson)
      },
    )

  private val nodeSession =
    GatewaySession(
      scope = scope,
      identityStore = identityStore,
      deviceAuthStore = deviceAuthStore,
      onConnected = { _, _, _ ->
        _nodeConnected.value = true
        nodeStatusText = "Connected"
        _canvasA2uiHydrated.value = false
        updateStatus()
        maybeNavigateToA2uiOnConnect()
      },
      onDisconnected = { message ->
        _nodeConnected.value = false
        nodeStatusText = message
        _canvasA2uiHydrated.value = false
        updateStatus()
        canvas.navigate("")
      },
      onEvent = { _, _ -> },
      onInvoke = { req -> invokeDispatcher.handleInvoke(req.command, req.paramsJson) },
      onTlsFingerprint = { id, fp -> prefs.saveGatewayTlsFingerprint(id, fp) }
    )

  val chat: ChatController =
    ChatController(
      scope = scope,
      session = operatorSession,
      json = json,
      supportsChatSubscribe = false,
    )

  val serverConfigRepository: ai.axiomaster.boji.remote.config.ConfigRepository =
    ai.axiomaster.boji.remote.config.ConfigRepository(operatorSession)

  val skillRepository: ai.axiomaster.boji.remote.skills.SkillRepository =
    ai.axiomaster.boji.remote.skills.SkillRepository(operatorSession)

  init {
    scope.launch { prefs.loadGatewayToken() }
    scope.launch {
      combine(canvasDebugStatusEnabled, statusText, serverName, remoteAddress) { d, s, sv, r ->
        Quad(d, s, sv, r)
      }.distinctUntilChanged().collect { (d, s, sv, r) ->
        canvas.setDebugStatusEnabled(d)
        if (d) canvas.setDebugStatus(s, sv ?: r)
      }
    }
  }

  private fun applyMainSessionKey(candidate: String?) {
    val trimmed = normalizeMainKey(candidate) ?: return
    if (isCanonicalMainSessionKey(_mainSessionKey.value)) return
    if (_mainSessionKey.value == trimmed) return
    _mainSessionKey.value = trimmed
    chat.applyMainSessionKey(trimmed)
  }

  private fun updateStatus() {
    _isConnected.value = operatorConnected
    val op = operatorStatusText.trim()
    _statusText.value = if (operatorConnected) (if (_nodeConnected.value) "Connected" else "Connected (node offline)") else (if (op != "Offline") op else nodeStatusText)
  }

  private fun resolveMainSessionKey(): String = _mainSessionKey.value.ifEmpty { "main" }

  private fun maybeNavigateToA2uiOnConnect() {
    val url = a2uiHandler.resolveA2uiHostUrl() ?: return
    if (canvas.currentUrl().isNullOrEmpty()) canvas.navigate(url)
  }

  fun setForeground(v: Boolean) { _isForeground.value = v }
  fun connect(endpoint: GatewayEndpoint) {
    val tls = connectionManager.resolveTlsParams(endpoint)
    if (tls?.required == true && tls.expectedFingerprint.isNullOrBlank()) {
      _statusText.value = "Verify gateway TLS fingerprint…"
      scope.launch {
        val fp = probeGatewayTlsFingerprint(endpoint.host, endpoint.port) ?: run {
          _statusText.value = "Failed: can't read TLS fingerprint"
          return@launch
        }
        _pendingGatewayTrust.value = GatewayTrustPrompt(endpoint, fp)
      }
      return
    }
    connectedEndpoint = endpoint
    val token = prefs.loadGatewayToken()
    val pwd = prefs.loadGatewayPassword()
    operatorSession.connect(endpoint, token, pwd, connectionManager.buildOperatorConnectOptions(), tls)
    nodeSession.connect(endpoint, token, pwd, connectionManager.buildNodeConnectOptions(), tls)
  }

  fun disconnect() {
    connectedEndpoint = null
    operatorSession.disconnect()
    nodeSession.disconnect()
  }

  fun acceptGatewayTrustPrompt() {
    val p = _pendingGatewayTrust.value ?: return
    _pendingGatewayTrust.value = null
    prefs.saveGatewayTlsFingerprint(p.endpoint.stableId, p.fingerprintSha256)
    connect(p.endpoint)
  }

  fun declineGatewayTrustPrompt() {
    _pendingGatewayTrust.value = null
    _statusText.value = "Offline"
  }

  private fun hasRecordAudioPermission(): Boolean = ContextCompat.checkSelfPermission(appContext, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

  private suspend fun refreshBrandingFromGateway() {
    try {
      val res = operatorSession.request("config.get", null) // Pass null for params if server expects no params or {}
      Log.d("BoJi", "Branding refresh response: $res")
      val root = json.parseToJsonElement(res).asObjectOrNull() ?: return
      
      // Handle potential legacy wrapper or direct flattened structure
      val config = root["config"].asObjectOrNull() ?: root
      val sessionCfg = config["session"].asObjectOrNull()
      
      val mainKey = normalizeMainKey(sessionCfg?.get("mainKey").asStringOrNull())
      if (mainKey != null) {
          applyMainSessionKey(mainKey)
      }
      
      val ui = config["ui"].asObjectOrNull()
      val color = parseHexColorArgb(ui?.get("seamColor").asStringOrNull())
      _seamColorArgb.value = color ?: DEFAULT_SEAM_COLOR_ARGB
      
      Log.i("BoJi", "Branding refreshed. MainKey: $mainKey")
    } catch (e: Throwable) {
      Log.w("BoJi", "Failed to refresh branding: ${e.message}")
    }
  }

  // Delegate methods
  fun setDisplayName(v: String) = prefs.setDisplayName(v)
  fun setCameraEnabled(v: Boolean) = prefs.setCameraEnabled(v)
  fun setLocationMode(m: LocationMode) = prefs.setLocationMode(m)
  fun setManualEnabled(v: Boolean) = prefs.setManualEnabled(v)
  fun setManualHost(v: String) = prefs.setManualHost(v)
  fun setManualPort(v: Int) = prefs.setManualPort(v)
  fun setManualTls(v: Boolean) = prefs.setManualTls(v)
  fun setGatewayToken(v: String) = prefs.setGatewayToken(v)
  fun setGatewayPassword(v: String) = prefs.setGatewayPassword(v)
  fun setLocationPreciseEnabled(v: Boolean) = prefs.setLocationPreciseEnabled(v)
  fun setPreventSleep(v: Boolean) = prefs.setPreventSleep(v)
  fun setCanvasDebugStatusEnabled(v: Boolean) = prefs.setCanvasDebugStatusEnabled(v)

  val instanceId: StateFlow<String> = prefs.instanceId
  val displayName: StateFlow<String> = prefs.displayName
  val cameraEnabled: StateFlow<Boolean> = prefs.cameraEnabled
  val locationMode: StateFlow<LocationMode> = prefs.locationMode
  val manualEnabled: StateFlow<Boolean> = prefs.manualEnabled
  val manualHost: StateFlow<String> = prefs.manualHost
  val manualPort: StateFlow<Int> = prefs.manualPort
  val manualTls: StateFlow<Boolean> = prefs.manualTls
  val gatewayToken: StateFlow<String> = prefs.gatewayToken
  val locationPreciseEnabled: StateFlow<Boolean> = prefs.locationPreciseEnabled
  val preventSleep: StateFlow<Boolean> = prefs.preventSleep
  val canvasDebugStatusEnabled: StateFlow<Boolean> = prefs.canvasDebugStatusEnabled

  fun requestCanvasRehydrate(source: String) {
    if (_canvasRehydratePending.value) return
    _canvasRehydratePending.value = true
    _canvasRehydrateErrorText.value = null
    scope.launch {
      try {
        val params = buildJsonObject {
          put("source", JsonPrimitive(source))
        }
        operatorSession.sendNodeEvent("canvas.rehydrate", params.toString())
      } catch (err: Throwable) {
        _canvasRehydratePending.value = false
        _canvasRehydrateErrorText.value = err.message
      }
    }
  }

  fun handleCanvasA2UIActionFromWebView(payload: String) {
      // Basic implementation for now
  }

  private fun handleAgentActionStep(payloadJson: String) {
    try {
      val obj = json.parseToJsonElement(payloadJson).asObjectOrNull() ?: return
      val action = parseJsonString(obj, "action") ?: return
      val x = parseJsonDouble(obj, "x")?.toFloat()
      val y = parseJsonDouble(obj, "y")?.toFloat()

      Log.d("BoJi", "agent.action.step: $action at ($x, $y)")
      scope.launch(Dispatchers.Main) {
        ai.axiomaster.boji.ai.AgentManager.avatarController.performAction(action, x, y)
      }
    } catch (e: Exception) {
      Log.w("BoJi", "Failed to handle agent.action.step: ${e.message}")
    }
  }
}
