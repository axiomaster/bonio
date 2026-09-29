package ai.axiomaster.bonio

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.CompletableDeferred

/**
 * Transparent helper activity that requests MediaProjection consent on behalf of
 * the floating-window service.
 *
 * The main activity's ActivityResultLauncher is unregistered whenever it is not
 * started, so a double-tap on the floating avatar while the app is backgrounded
 * used to fail with "Attempting to launch an unregistered ActivityResultLauncher".
 * This activity can be started from the service (the app holds SYSTEM_ALERT_WINDOW,
 * so background activity starts are permitted) and reports the result back through
 * [pending].
 */
class ScreenCaptureConsentActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val launcher =
      registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val data = result.data
        completePending(
          if (result.resultCode == Activity.RESULT_OK && data != null) {
            ScreenCaptureRequester.CaptureResult(result.resultCode, data)
          } else {
            null
          },
        )
      }

    val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    try {
      launcher.launch(mgr.createScreenCaptureIntent())
    } catch (_: Throwable) {
      completePending(null)
    }
  }

  private fun completePending(result: ScreenCaptureRequester.CaptureResult?) {
    pending?.complete(result)
    pending = null
    finish()
    @Suppress("DEPRECATION")
    overridePendingTransition(0, 0)
  }

  override fun onDestroy() {
    // Torn down without a result (e.g. user dismissed) — do not leave awaiters hanging.
    if (!isChangingConfigurations) {
      pending?.let { if (!it.isCompleted) it.complete(null) }
      pending = null
    }
    super.onDestroy()
  }

  companion object {
    @Volatile private var pending: CompletableDeferred<ScreenCaptureRequester.CaptureResult?>? = null

    /** Starts the consent activity and awaits the user's decision. */
    fun request(context: Context): CompletableDeferred<ScreenCaptureRequester.CaptureResult?> {
      val deferred = CompletableDeferred<ScreenCaptureRequester.CaptureResult?>()
      pending = deferred
      val intent =
        Intent(context, ScreenCaptureConsentActivity::class.java).apply {
          flags =
            Intent.FLAG_ACTIVITY_NEW_TASK or
              Intent.FLAG_ACTIVITY_NO_ANIMATION or
              Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
        }
      context.startActivity(intent)
      return deferred
    }
  }
}
