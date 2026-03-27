package ai.axiomaster.boji

import ai.axiomaster.boji.ui.theme.BoJiTheme
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.activity.enableEdgeToEdge

import android.provider.Settings
import ai.axiomaster.boji.ui.screens.MainScreen

class MainActivity : ComponentActivity() {
    private val viewModel: MainViewModel by viewModels()
    private lateinit var permissionRequester: PermissionRequester
    private lateinit var screenCaptureRequester: ScreenCaptureRequester
    
    companion object {
        private const val OVERLAY_PERMISSION_REQ_CODE = 1234
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        permissionRequester = PermissionRequester(this)
        screenCaptureRequester = ScreenCaptureRequester(this)
        
        viewModel.screenRecorder.attachScreenCaptureRequester(screenCaptureRequester)
        viewModel.screenRecorder.attachPermissionRequester(permissionRequester)

        checkOverlayPermission()

        setContent {
            BoJiTheme {
                MainScreen(viewModel = viewModel)
            }
        }

        window.decorView.post { NodeForegroundService.start(this) }
    }

    override fun onResume() {
        super.onResume()
        android.util.Log.d("BoJiApp", "MainActivity onResume")
        ensureFloatingWindowRunning()
    }

    private fun ensureFloatingWindowRunning() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(this)) {
            startFloatingWindowService()
        }
    }

    private fun startFloatingWindowService() {
        android.util.Log.d("BoJiApp", "MainActivity starting FloatingWindowService")
        val serviceIntent = Intent(this, FloatingWindowService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            // Show a simple dialog or just jump to settings.
            // For a "Desktop Assistant", this is critical.
            android.app.AlertDialog.Builder(this)
                .setTitle("Overlay Permission Required")
                .setMessage("BoJi needs 'Display over other apps' permission to function as a floating virtual assistant. Please authorize it in the next screen.")
                .setPositiveButton("Authorize") { _, _ ->
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivityForResult(intent, OVERLAY_PERMISSION_REQ_CODE)
                }
                .setNegativeButton("Later", null)
                .show()
        }
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