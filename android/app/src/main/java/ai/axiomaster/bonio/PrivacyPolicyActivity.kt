package ai.axiomaster.bonio

import android.annotation.SuppressLint
import android.app.Activity
import android.os.Bundle
import android.view.KeyEvent
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * In-app privacy policy viewer. Store review requires the privacy policy to be
 * readable inside the app and consistent with the published policy page, so
 * this renders the same PRIVACY.md that is submitted to the app store.
 */
class PrivacyPolicyActivity : Activity() {
    private lateinit var webView: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this)
        setContentView(webView)
        webView.settings.javaScriptEnabled = true
        webView.webViewClient = WebViewClient()
        webView.loadUrl(PRIVACY_POLICY_URL)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && ::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    companion object {
        const val PRIVACY_POLICY_URL = "https://github.com/axiomaster/bonio/blob/main/PRIVACY.md"
    }
}
