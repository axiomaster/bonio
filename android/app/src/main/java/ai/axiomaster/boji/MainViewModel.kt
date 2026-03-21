package ai.axiomaster.boji

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import ai.axiomaster.boji.ai.AgentManager
import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.remote.gateway.GatewayEndpoint
import ai.axiomaster.boji.remote.chat.OutgoingAttachment
import ai.axiomaster.boji.remote.chat.SpeechToTextManager
import ai.axiomaster.boji.remote.node.CanvasController
import ai.axiomaster.boji.remote.node.ScreenRecordManager
import ai.axiomaster.boji.remote.LocationMode
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class MainViewModel(app: Application) : AndroidViewModel(app) {
  private val runtime: NodeRuntime = (app as BoJiApp).runtime

  val canvas: CanvasController = runtime.canvas
  val canvasCurrentUrl: StateFlow<String?> = runtime.canvas.currentUrl
  val canvasA2uiHydrated: StateFlow<Boolean> = runtime.canvasA2uiHydrated
  val canvasRehydratePending: StateFlow<Boolean> = runtime.canvasRehydratePending
  val canvasRehydrateErrorText: StateFlow<String?> = runtime.canvasRehydrateErrorText
  val screenRecorder: ScreenRecordManager = runtime.screenRecorder

  val gateways: StateFlow<List<GatewayEndpoint>> = runtime.gateways
  val discoveryStatusText: StateFlow<String> = runtime.discoveryStatusText

  val isConnected: StateFlow<Boolean> = runtime.isConnected
  val isNodeConnected: StateFlow<Boolean> = runtime.nodeConnected
  val statusText: StateFlow<String> = runtime.statusText
  val serverName: StateFlow<String?> = runtime.serverName
  val remoteAddress: StateFlow<String?> = runtime.remoteAddress
  val pendingGatewayTrust: StateFlow<NodeRuntime.GatewayTrustPrompt?> = runtime.pendingGatewayTrust
  val isForeground: StateFlow<Boolean> = runtime.isForeground
  val seamColorArgb: StateFlow<Long> = runtime.seamColorArgb
  val mainSessionKey: StateFlow<String> = runtime.mainSessionKey

  val cameraHud: StateFlow<CameraHudState?> = runtime.cameraHud
  val screenRecordActive: StateFlow<Boolean> = runtime.screenRecordActive

  val instanceId: StateFlow<String> = runtime.instanceId
  val displayName: StateFlow<String> = runtime.displayName
  val cameraEnabled: StateFlow<Boolean> = runtime.cameraEnabled
  val locationMode: StateFlow<LocationMode> = runtime.locationMode
  val manualEnabled: StateFlow<Boolean> = runtime.manualEnabled
  val manualHost: StateFlow<String> = runtime.manualHost
  val manualPort: StateFlow<Int> = runtime.manualPort
  val manualTls: StateFlow<Boolean> = runtime.manualTls
  val gatewayToken: StateFlow<String> = runtime.gatewayToken
  val locationPreciseEnabled: StateFlow<Boolean> = runtime.locationPreciseEnabled
  val preventSleep: StateFlow<Boolean> = runtime.preventSleep
  val canvasDebugStatusEnabled: StateFlow<Boolean> = runtime.canvasDebugStatusEnabled

  val chatSessionKey: StateFlow<String> = runtime.chat.sessionKey
  val chatSessionId: StateFlow<String?> = runtime.chat.sessionId
  val chatMessages = runtime.chat.messages
  val chatError: StateFlow<String?> = runtime.chat.errorText
  val chatHealthOk: StateFlow<Boolean> = runtime.chat.healthOk
  val chatThinkingLevel: StateFlow<String> = runtime.chat.thinkingLevel
  val chatStreamingAssistantText: StateFlow<String?> = runtime.chat.streamingAssistantText
  val chatPendingToolCalls = runtime.chat.pendingToolCalls
  val chatSessions = runtime.chat.sessions
  val pendingRunCount: StateFlow<Int> = runtime.chat.pendingRunCount

  private val _serverConfig = kotlinx.coroutines.flow.MutableStateFlow<ai.axiomaster.boji.remote.config.ServerConfig?>(null)
  val serverConfig: StateFlow<ai.axiomaster.boji.remote.config.ServerConfig?> = _serverConfig

  private val ttsManager = ai.axiomaster.boji.remote.chat.SystemTtsManager(app)
  private val _isSpeakerEnabled = MutableStateFlow(true)
  val isSpeakerEnabled: StateFlow<Boolean> = _isSpeakerEnabled

  private val themeRepository = ai.axiomaster.boji.remote.theme.ThemeRepository(app)
  private val _installedThemes = MutableStateFlow<List<ai.axiomaster.boji.remote.theme.ThemeInfo>>(emptyList())
  val installedThemes: StateFlow<List<ai.axiomaster.boji.remote.theme.ThemeInfo>> = _installedThemes

  private val sttManager = SpeechToTextManager(app)
  private val _partialSttText = MutableStateFlow<String?>(null)
  val partialSttText: StateFlow<String?> = _partialSttText

  init {
      runtime.chat.onAssistantSpoke = { text: String ->
          if (_isSpeakerEnabled.value) {
              AgentManager.stateManager.transitionTo(AgentState.Speaking)
              AgentManager.stateManager.setBubble(text)
              ttsManager.speak(text)
          }
      }

      ttsManager.onSpeakingDone = {
          viewModelScope.launch(Dispatchers.Main) {
              if (AgentManager.stateManager.currentState.value == AgentState.Speaking) {
                  AgentManager.stateManager.transitionTo(AgentState.Idle)
              }
          }
      }

      sttManager.warmUpVosk()

      viewModelScope.launch {
          isConnected.collect { connected ->
              if (connected) {
                  refreshServerConfig()
              }
          }
      }
  }

  fun startVoiceInput() {
      _partialSttText.value = null
      sttManager.startListening(object : SpeechToTextManager.Listener {
          override fun onPartialResult(text: String) {
              _partialSttText.value = text
          }

          override fun onFinalResult(text: String) {
              _partialSttText.value = null
              AgentManager.stateManager.transitionTo(AgentState.Thinking)
              sendChat(message = text, thinking = chatThinkingLevel.value, attachments = emptyList())
          }

          override fun onError(errorCode: Int) {
              Log.w("MainViewModel", "STT error $errorCode")
              _partialSttText.value = null
              AgentManager.stateManager.transitionTo(AgentState.Idle)
          }

          override fun onReadyForSpeech() {
              AgentManager.stateManager.transitionTo(AgentState.Listening)
          }

          override fun onEndOfSpeech() {}
      })
  }

  fun stopVoiceInput() {
      sttManager.stopListening()
  }

  fun cancelVoiceInput() {
      sttManager.cancelListening()
      _partialSttText.value = null
      AgentManager.stateManager.transitionTo(AgentState.Idle)
  }

  fun setSpeakerEnabled(enabled: Boolean) {
      _isSpeakerEnabled.value = enabled
      if (!enabled) {
          ttsManager.stop()
          if (AgentManager.stateManager.currentState.value == AgentState.Speaking) {
              AgentManager.stateManager.transitionTo(AgentState.Idle)
          }
      }
  }

  override fun onCleared() {
      super.onCleared()
      sttManager.destroy()
      ttsManager.release()
  }

  fun setForeground(value: Boolean) {
    runtime.setForeground(value)
  }

  fun setDisplayName(value: String) {
    runtime.setDisplayName(value)
  }

  fun setCameraEnabled(value: Boolean) {
    runtime.setCameraEnabled(value)
  }

  fun setLocationMode(mode: LocationMode) {
    runtime.setLocationMode(mode)
  }

  fun setLocationPreciseEnabled(value: Boolean) {
    runtime.setLocationPreciseEnabled(value)
  }

  fun setPreventSleep(value: Boolean) {
    runtime.setPreventSleep(value)
  }

  fun setCanvasDebugStatusEnabled(value: Boolean) {
    runtime.setCanvasDebugStatusEnabled(value)
  }

  fun setManualEnabled(value: Boolean) {
    runtime.setManualEnabled(value)
  }

  fun setManualHost(value: String) {
    runtime.setManualHost(value)
  }

  fun setManualPort(value: Int) {
    runtime.setManualPort(value)
  }

  fun setManualTls(value: Boolean) {
    runtime.setManualTls(value)
  }

  fun setGatewayToken(value: String) {
    runtime.setGatewayToken(value)
  }

  fun setGatewayPassword(value: String) {
    runtime.setGatewayPassword(value)
  }

  fun connect(endpoint: GatewayEndpoint) {
    runtime.connect(endpoint)
  }

  fun disconnect() {
    runtime.disconnect()
  }

  fun acceptGatewayTrustPrompt() {
    runtime.acceptGatewayTrustPrompt()
  }

  fun declineGatewayTrustPrompt() {
    runtime.declineGatewayTrustPrompt()
  }

  fun requestCanvasRehydrate(source: String) {
    runtime.requestCanvasRehydrate(source)
  }

  fun handleCanvasA2UIActionFromWebView(payloadJson: String) {
    runtime.handleCanvasA2UIActionFromWebView(payloadJson)
  }

  fun loadChat(sessionKey: String) {
    runtime.chat.load(sessionKey)
  }

  fun refreshChat() {
    runtime.chat.refresh()
  }

  fun refreshChatSessions(limit: Int? = null) {
    runtime.chat.refreshSessions(limit = limit)
  }

  fun setChatThinkingLevel(level: String) {
    runtime.chat.setThinkingLevel(level)
  }

  fun switchChatSession(sessionKey: String) {
    runtime.chat.switchSession(sessionKey)
  }

  fun abortChat() {
    runtime.chat.abort()
  }

  fun sendChat(message: String, thinking: String, attachments: List<OutgoingAttachment>) {
    runtime.chat.sendMessage(message = message, thinkingLevel = thinking, attachments = attachments)
  }

  fun refreshServerConfig() {
    viewModelScope.launch {
      runtime.serverConfigRepository.getConfig().onSuccess {
        _serverConfig.value = it
      }
    }
  }

  fun updateServerConfig(defaultModel: String? = null, models: List<ai.axiomaster.boji.remote.config.ModelConfig>? = null) {
    viewModelScope.launch {
      runtime.serverConfigRepository.setConfig(defaultModel, models).onSuccess {
        refreshServerConfig()
      }
    }
  }

  // ── Skills ──

  private val _skills = MutableStateFlow<List<ai.axiomaster.boji.remote.skills.SkillInfo>>(emptyList())
  val skills: StateFlow<List<ai.axiomaster.boji.remote.skills.SkillInfo>> = _skills

  private val _skillsLoading = MutableStateFlow(false)
  val skillsLoading: StateFlow<Boolean> = _skillsLoading

  private val _skillsError = MutableStateFlow<String?>(null)
  val skillsError: StateFlow<String?> = _skillsError

  fun refreshSkills() {
    viewModelScope.launch {
      _skillsLoading.value = true
      _skillsError.value = null
      Log.d("MainViewModel", "refreshSkills: isConnected=${isConnected.value}")
      runtime.skillRepository.listSkills()
        .onSuccess {
          Log.d("MainViewModel", "refreshSkills: got ${it.size} skills")
          _skills.value = it
        }
        .onFailure {
          Log.e("MainViewModel", "refreshSkills failed: ${it.message}", it)
          _skillsError.value = it.message ?: "Failed to load skills"
        }
      _skillsLoading.value = false
    }
  }

  fun toggleSkill(id: String, enable: Boolean) {
    viewModelScope.launch {
      val result = if (enable) runtime.skillRepository.enableSkill(id)
                   else runtime.skillRepository.disableSkill(id)
      result.onSuccess { refreshSkills() }
          .onFailure { _skillsError.value = it.message }
    }
  }

  fun removeSkill(id: String) {
    viewModelScope.launch {
      runtime.skillRepository.removeSkill(id)
        .onSuccess { refreshSkills() }
        .onFailure { _skillsError.value = it.message }
    }
  }

  fun installSkill(id: String, content: String) {
    viewModelScope.launch {
      runtime.skillRepository.installSkill(id, content)
        .onSuccess { refreshSkills() }
        .onFailure { _skillsError.value = it.message }
    }
  }

  // ── Marketplace (ClawHub) ──

  private val clawHubClient = ai.axiomaster.boji.remote.skills.ClawHubClient()

  private val _marketplaceResults = MutableStateFlow<List<ai.axiomaster.boji.remote.skills.ClawHubSearchResult>>(emptyList())
  val marketplaceResults: StateFlow<List<ai.axiomaster.boji.remote.skills.ClawHubSearchResult>> = _marketplaceResults

  private val _marketplaceLoading = MutableStateFlow(false)
  val marketplaceLoading: StateFlow<Boolean> = _marketplaceLoading

  private val _marketplaceError = MutableStateFlow<String?>(null)
  val marketplaceError: StateFlow<String?> = _marketplaceError

  private val _selectedMarketSkill = MutableStateFlow<ai.axiomaster.boji.remote.skills.ClawHubSkillDetail?>(null)
  val selectedMarketSkill: StateFlow<ai.axiomaster.boji.remote.skills.ClawHubSkillDetail?> = _selectedMarketSkill

  private val _installProgress = MutableStateFlow<String?>(null)
  val installProgress: StateFlow<String?> = _installProgress

  fun searchMarketplace(query: String) {
    viewModelScope.launch {
      _marketplaceLoading.value = true
      _marketplaceError.value = null
      clawHubClient.search(query)
        .onSuccess { _marketplaceResults.value = it }
        .onFailure { _marketplaceError.value = it.message ?: "Search failed" }
      _marketplaceLoading.value = false
    }
  }

  fun loadMarketSkillDetail(slug: String) {
    viewModelScope.launch {
      _selectedMarketSkill.value = null
      clawHubClient.getSkillDetail(slug)
        .onSuccess { _selectedMarketSkill.value = it }
        .onFailure { _marketplaceError.value = it.message }
    }
  }

  fun clearSelectedMarketSkill() {
    _selectedMarketSkill.value = null
  }

  fun installFromMarketplace(slug: String) {
    viewModelScope.launch {
      val detail = _selectedMarketSkill.value
      val version = detail?.latestVersion?.version
        ?: detail?.skill?.tags?.get("latest")
        ?: "latest"

      _installProgress.value = "downloading"
      clawHubClient.downloadSkillContent(slug, version)
        .onSuccess { content ->
          _installProgress.value = "installing"
          runtime.skillRepository.installSkill(slug, content)
            .onSuccess {
              _installProgress.value = "success"
              refreshSkills()
            }
            .onFailure {
              _installProgress.value = null
              _marketplaceError.value = "Install failed: ${it.message}"
            }
        }
        .onFailure {
          _installProgress.value = null
          _marketplaceError.value = it.message
        }
    }
  }

  fun clearInstallProgress() {
    _installProgress.value = null
  }

  fun refreshInstalledThemes() {
    viewModelScope.launch {
      themeRepository.listInstalledThemes().also { _installedThemes.value = it }
    }
  }

  fun getThemeAssetPath(state: AgentState): String {
    val theme = _installedThemes.value.firstOrNull()
    val stateKey = when (state) {
      AgentState.Idle -> "idle"
      AgentState.Listening -> "listening"
      AgentState.Thinking -> "thinking"
      AgentState.Speaking -> "speaking"
      AgentState.Working -> "working"
    }
    return theme?.assetPathForState(stateKey) ?: fallbackAssetPath(state)
  }

  private fun fallbackAssetPath(state: AgentState) = when (state) {
    AgentState.Idle -> "cat-idle.lottie"
    AgentState.Listening -> "cat-listening.lottie"
    AgentState.Thinking -> "cat-thinking.lottie"
    AgentState.Speaking -> "cat-speaking.lottie"
    AgentState.Working -> "cat-working.lottie"
  }
}
