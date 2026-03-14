package ai.axiomaster.BoJi

import ai.axiomaster.BoJi.ui.screens.MainScreen
import ai.axiomaster.BoJi.ui.theme.BoJiTheme
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier

class MainActivity : ComponentActivity() {

    companion object {
        private const val OVERLAY_PERMISSION_REQ_CODE = 1234
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        android.util.Log.d("BoJiApp", "MainActivity onCreate")
        enableEdgeToEdge()
        setContent {
            BoJiTheme {
                MainScreen(modifier = Modifier.fillMaxSize())
            }
        }
    }

    override fun onStart() {
        super.onStart()
        android.util.Log.d("BoJiApp", "MainActivity onStart - App in foreground")
        // App is in foreground, stop floating window and show full pet UI
        stopFloatingWindowService()
    }

    override fun onStop() {
        super.onStop()
        android.util.Log.d("BoJiApp", "MainActivity onStop - App in background")
        checkPermissionAndStartService()
    }

    private fun checkPermissionAndStartService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            // Need to guide user to settings if permission not granted
            // Usually we wouldn't auto-launch this onStop as it's disruptive,
            // but for MVP Phase 1 & 2.5 we leave it simple.
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivityForResult(intent, OVERLAY_PERMISSION_REQ_CODE)
        } else {
            startFloatingWindowService()
        }
    }

    private fun startFloatingWindowService() {
        val serviceIntent = Intent(this, FloatingWindowService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopFloatingWindowService() {
        val serviceIntent = Intent(this, FloatingWindowService::class.java)
        stopService(serviceIntent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == OVERLAY_PERMISSION_REQ_CODE) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(this)) {
                startFloatingWindowService()
            }
        }
    }
}