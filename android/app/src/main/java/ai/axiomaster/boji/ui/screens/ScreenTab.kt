package ai.axiomaster.boji.ui.screens

import android.annotation.SuppressLint
import android.webkit.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import ai.axiomaster.boji.MainViewModel

@Composable
fun ScreenTab(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val canvasUrl by viewModel.canvasCurrentUrl.collectAsState()
    val canvasA2uiHydrated by viewModel.canvasA2uiHydrated.collectAsState()
    val canvasRehydratePending by viewModel.canvasRehydratePending.collectAsState()
    
    Box(modifier = modifier.fillMaxSize()) {
        CanvasWebView(viewModel = viewModel, modifier = Modifier.fillMaxSize())

        if (canvasUrl.isNullOrBlank() || !canvasA2uiHydrated) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("No Screen Active", style = MaterialTheme.typography.headlineSmall)
                    Spacer(modifier = Modifier.height(16.dp))
                    Button(
                        onClick = { viewModel.requestCanvasRehydrate(source = "screen_tab_cta") },
                        enabled = !canvasRehydratePending
                    ) {
                        if (canvasRehydratePending) {
                            CircularProgressIndicator(modifier = Modifier.size(24.dp))
                        } else {
                            Icon(Icons.Default.Refresh, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Restore Screen")
                        }
                    }
                }
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun CanvasWebView(viewModel: MainViewModel, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val isDebuggable = (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    val webViewRef = remember { mutableStateOf<WebView?>(null) }

    DisposableEffect(viewModel) {
        onDispose {
            val webView = webViewRef.value ?: return@onDispose
            viewModel.canvas.detach(webView)
            webView.removeJavascriptInterface(CanvasA2UIActionBridge.interfaceName)
            webView.stopLoading()
            webView.destroy()
            webViewRef.value = null
        }
    }

    AndroidView(
        modifier = modifier,
        factory = {
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
                    WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, false)
                }
                
                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String?) {
                        viewModel.canvas.onPageFinished()
                    }
                }

                val bridge = CanvasA2UIActionBridge { payload -> viewModel.handleCanvasA2UIActionFromWebView(payload) }
                addJavascriptInterface(bridge, CanvasA2UIActionBridge.interfaceName)
                viewModel.canvas.attach(this)
                webViewRef.value = this
            }
        }
    )
}

private class CanvasA2UIActionBridge(private val onMessage: (String) -> Unit) {
    @JavascriptInterface
    fun postMessage(payload: String?) {
        val msg = payload?.trim().orEmpty()
        if (msg.isEmpty()) return
        onMessage(msg)
    }

    companion object {
        const val interfaceName: String = "bojiCanvasA2UIAction"
    }
}
