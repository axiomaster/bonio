package ai.axiomaster.bonio.input

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import android.util.Log
import android.view.inputmethod.InputMethodManager
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull

object ImeProxyManager {
    private const val TAG = "ImeProxyManager"
    const val BONIO_IME_ID = BonioProxyImeService.IME_ID

    fun isSecureSettingsGranted(context: Context): Boolean {
        return context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED
    }

    fun ensureImeEnabled(context: Context): Boolean {
        if (!isSecureSettingsGranted(context)) return false
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        val isAlreadyEnabled = imm?.enabledInputMethodList?.any { it.id == BONIO_IME_ID } == true
        if (isAlreadyEnabled) {
            Log.i(TAG, "ensureImeEnabled: $BONIO_IME_ID is already enabled")
            return true
        }

        val resolver = context.contentResolver
        try {
            val enabled = try {
                Settings.Secure.getString(resolver, Settings.Secure.ENABLED_INPUT_METHODS) ?: ""
            } catch (se: SecurityException) {
                ""
            }
            val newEnabled = if (enabled.isEmpty()) {
                BONIO_IME_ID
            } else if (!enabled.contains(BONIO_IME_ID)) {
                "$enabled:$BONIO_IME_ID"
            } else {
                enabled
            }
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_INPUT_METHODS, newEnabled)
            Log.i(TAG, "ensureImeEnabled: added $BONIO_IME_ID to enabled input methods")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "ensureImeEnabled failed", e)
            return false
        }
    }

    /**
     * Silently switches system IME to BonioProxyIME, triggers input focus,
     * writes text directly via InputConnection, sends it, and restores previous IME.
     *
     * @param focusTrigger Suspend lambda that triggers input focus (e.g. tapping the chat bar).
     * @param clickSendTrigger Optional lambda to click physical send button if remote app doesn't send on action.
     */
    suspend fun injectAndSend(
        context: Context,
        text: String,
        doSend: Boolean = true,
        focusTrigger: (suspend () -> Boolean)? = null,
        clickSendTrigger: (suspend () -> Boolean)? = null,
    ): Boolean {
        if (!isSecureSettingsGranted(context)) {
            Log.w(TAG, "injectAndSend: WRITE_SECURE_SETTINGS not granted, cannot use IME proxy")
            return false
        }

        val resolver = context.contentResolver
        val previousIme = Settings.Secure.getString(resolver, Settings.Secure.DEFAULT_INPUT_METHOD)
        Log.i(TAG, "injectAndSend: starting. previousIme=$previousIme textLength=${text.length}")

        ensureImeEnabled(context)

        val connectionReady = CompletableDeferred<android.view.inputmethod.InputConnection>()
        BonioProxyImeService.onInputConnectionReady = connectionReady

        try {
            // 1. Switch to Bonio Proxy IME (zero UI, no keyboard popup)
            val switched = Settings.Secure.putString(resolver, Settings.Secure.DEFAULT_INPUT_METHOD, BONIO_IME_ID)
            Log.i(TAG, "injectAndSend: switched default IME to $BONIO_IME_ID ok=$switched")

            // Wait briefly for system to switch active IME service
            delay(100)

            // 2. Trigger input field focus
            if (focusTrigger != null) {
                val focused = focusTrigger()
                Log.i(TAG, "injectAndSend: focusTrigger result=$focused")
            }

            // 3. Wait for InputConnection to bind to a real editor (up to 2000ms)
            var service = BonioProxyImeService.instance
            var ic = if (service?.isRealEditorConnected() == true) {
                service.currentInputConnection
            } else {
                withTimeoutOrNull(2000) { connectionReady.await() } ?: service?.currentInputConnection
            }
            service = BonioProxyImeService.instance

            if (ic == null || service == null) {
                Log.w(TAG, "injectAndSend: failed to obtain InputConnection via Proxy IME")
                return false
            }

            // Short delay for connection stabilization
            delay(60)

            // 4. Inject text and trigger send
            val injected = service.injectTextAndSend(
                text = text,
                doSend = doSend,
                useEnterKey = (clickSendTrigger == null)
            )
            Log.i(TAG, "injectAndSend: injectTextAndSend result=$injected")

            // 5. If clickSendTrigger provided, allow UI a moment to render send button then click it
            if (injected && doSend && clickSendTrigger != null) {
                delay(180)
                val sendClicked = clickSendTrigger()
                Log.i(TAG, "injectAndSend: clickSendTrigger result=$sendClicked")
                delay(200)
            }

            // Keep keyboard hidden when switching back
            try {
                service.requestHideSelf(0)
            } catch (_: Throwable) {}

            return injected
        } catch (e: Exception) {
            Log.e(TAG, "injectAndSend failed with exception", e)
            return false
        } finally {
            BonioProxyImeService.onInputConnectionReady = null
            // 6. Seamlessly restore user's original default IME
            if (!previousIme.isNullOrEmpty() && previousIme != BONIO_IME_ID) {
                try {
                    Settings.Secure.putString(resolver, Settings.Secure.DEFAULT_INPUT_METHOD, previousIme)
                    Log.i(TAG, "injectAndSend: restored default IME to $previousIme")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to restore previous IME: $previousIme", e)
                }
            }
        }
    }
}
