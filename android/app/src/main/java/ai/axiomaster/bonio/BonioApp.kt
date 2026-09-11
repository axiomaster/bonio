package ai.axiomaster.bonio

import android.app.Application
import android.os.StrictMode
import ai.axiomaster.bonio.local.LocalEngineController

class BonioApp : Application() {
  val runtime: NodeRuntime by lazy { NodeRuntime(this) }
  val localEngine: LocalEngineController by lazy { LocalEngineController(this, runtime.prefs) }

  override fun onCreate() {
    super.onCreate()
    if (BuildConfig.DEBUG) {
      StrictMode.setThreadPolicy(
        StrictMode.ThreadPolicy.Builder()
          .detectAll()
          .penaltyLog()
          .build(),
      )
      StrictMode.setVmPolicy(
        StrictMode.VmPolicy.Builder()
          .detectAll()
          .penaltyLog()
          .build(),
      )
    }
    // Auto-start the embedded engine and connect to it. The gateway sessions
    // retry with backoff, so connecting before the port is open is fine.
    if (runtime.prefs.localEnabled.value) {
      localEngine.ensureStarted()
      runtime.connectLocal()
    }
  }
}
