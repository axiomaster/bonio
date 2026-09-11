package ai.axiomaster.bonio.local

import android.content.Context
import android.util.Log
import ai.axiomaster.bonio.remote.SecurePrefs
import java.io.File
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Supervises the embedded hiclaw gateway engine (bundled as jniLibs/arm64-v8a/libhiclaw.so
 * and extracted to nativeLibraryDir by useLegacyPackaging).
 *
 * The engine is spawned as a child process bound to 127.0.0.1 and reached over the
 * regular gateway protocol, so it can later be replaced by a native backend without
 * touching the app-side code (see docs/design/arch/android-port-arch-20260911.md).
 */
class LocalEngineController(context: Context, private val prefs: SecurePrefs) {
  private val appContext = context.applicationContext
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

  enum class State { Stopped, Starting, Running, Failed }

  private val _state = MutableStateFlow(State.Stopped)
  val state: StateFlow<State> = _state

  private val processRef = AtomicReference<Process?>(null)
  private var superviseJob: Job? = null

  @Volatile private var stopping = false
  private var restartCount = 0

  val gatewayPort: Int get() = prefs.localPort.value

  fun ensureStarted() {
    if (_state.value == State.Running || _state.value == State.Starting) return
    stopping = false
    restartCount = 0
    scope.launch { startInternal() }
  }

  fun stop() {
    stopping = true
    superviseJob?.cancel()
    processRef.getAndSet(null)?.destroy()
    _state.value = State.Stopped
  }

  private suspend fun startInternal() {
    _state.value = State.Starting
    try {
      ensureConfig()

      val port = prefs.localPort.value
      if (isPortOpen(port)) {
        // Likely an engine left over from a previous app run — reuse it.
        Log.i(TAG, "port $port already open, reusing existing engine")
        _state.value = State.Running
        return
      }

      val binary = File(appContext.applicationInfo.nativeLibraryDir, "libhiclaw.so")
      if (!binary.exists()) {
        Log.e(TAG, "engine binary missing at ${binary.absolutePath}")
        _state.value = State.Failed
        return
      }

      val process = ProcessBuilder(
        binary.absolutePath,
        // Global options must come before the subcommand (CLI11).
        "--config-dir", engineDir.absolutePath,
        "--log-level", "info",
        "gateway",
        "--port", port.toString(),
      ).apply {
        // memo storage lives under $HOME/.bonio on the server side.
        environment()["HOME"] = engineDir.absolutePath
      }.start()
      processRef.set(process)
      pumpLogs(process)

      val deadline = System.currentTimeMillis() + READY_TIMEOUT_MS
      var ready = false
      while (System.currentTimeMillis() < deadline) {
        if (isPortOpen(port)) {
          ready = true
          break
        }
        if (stopping || !process.isAlive) break
        delay(PROBE_INTERVAL_MS)
      }

      if (!ready) {
        Log.e(TAG, "engine did not become ready within ${READY_TIMEOUT_MS}ms")
        process.destroy()
        _state.value = State.Failed
        return
      }

      Log.i(TAG, "engine ready on 127.0.0.1:$port")
      _state.value = State.Running
      restartCount = 0
      supervise(process)
    } catch (e: Exception) {
      Log.e(TAG, "failed to start engine", e)
      _state.value = State.Failed
    }
  }

  private fun supervise(process: Process) {
    superviseJob?.cancel()
    superviseJob = scope.launch {
      val exit = runCatching { process.waitFor() }.getOrDefault(-1)
      if (stopping || _state.value != State.Running) return@launch
      Log.w(TAG, "engine exited unexpectedly with code $exit")
      processRef.set(null)
      _state.value = State.Stopped
      restartCount += 1
      if (restartCount <= MAX_RESTARTS) {
        delay(RESTART_BACKOFF_MS)
        if (!stopping) startInternal()
      } else {
        Log.e(TAG, "engine restart limit reached, giving up")
        _state.value = State.Failed
      }
    }
  }

  private fun ensureConfig() {
    val configFile = File(engineDir, "hiclaw.json")
    var pairing = prefs.loadLocalToken()
    val json = if (configFile.exists()) {
      runCatching { JSONObject(configFile.readText()) }.getOrDefault(JSONObject())
    } else {
      JSONObject()
    }
    val gateway = json.optJSONObject("gateway") ?: JSONObject().also { json.put("gateway", it) }
    val port = prefs.localPort.value
    if (!gateway.optBoolean("enabled", false)) gateway.put("enabled", true)
    if (gateway.optString("host") != "127.0.0.1") gateway.put("host", "127.0.0.1")
    if (gateway.optInt("port", -1) != port) gateway.put("port", port)
    if (pairing.isNullOrEmpty()) {
      pairing = newPairingCode()
      prefs.saveLocalToken(pairing)
    }
    if (gateway.optString("pairing_code") != pairing) gateway.put("pairing_code", pairing)
    configFile.writeText(json.toString(2))
  }

  private fun newPairingCode(): String {
    val bytes = ByteArray(16)
    SecureRandom().nextBytes(bytes)
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
  }

  private fun isPortOpen(port: Int): Boolean = try {
    Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 250) }
    true
  } catch (_: Exception) {
    false
  }

  private fun pumpLogs(process: Process) {
    scope.launch { pumpStream(process.inputStream) }
    scope.launch { pumpStream(process.errorStream) }
  }

  private suspend fun pumpStream(stream: InputStream) {
    val buffer = ByteArray(4096)
    stream.use { input ->
      while (!stopping) {
        val n = runCatching { input.read(buffer) }.getOrDefault(-1)
        if (n < 0) break
        appendLog(buffer, n)
      }
    }
  }

  private fun appendLog(buffer: ByteArray, n: Int) {
    try {
      if (engineLogFile.length() > MAX_LOG_BYTES) engineLogFile.writeText("")
      engineLogFile.appendText(String(buffer, 0, n))
    } catch (_: Exception) {
      // Logging must never take the engine down.
    }
  }

  private val engineDir: File
    get() = File(appContext.filesDir, "hiclaw").apply { mkdirs() }

  private val engineLogFile: File
    get() = File(engineDir, "engine.log")

  companion object {
    private const val TAG = "LocalEngine"
    private const val READY_TIMEOUT_MS = 15_000L
    private const val PROBE_INTERVAL_MS = 300L
    private const val MAX_RESTARTS = 3
    private const val RESTART_BACKOFF_MS = 2_000L
    private const val MAX_LOG_BYTES = 512L * 1024
  }
}
