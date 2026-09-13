package ai.axiomaster.bonio.input

import android.inputmethodservice.InputMethodService
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Lightweight Proxy InputMethodService that never displays a software keyboard.
 * Directly communicates with the target application's editor via InputConnection.
 */
class BonioProxyImeService : InputMethodService() {

    companion object {
        private const val TAG = "BonioProxyIME"
        const val IME_ID = "ai.axiomaster.bonio/.input.BonioProxyImeService"

        @Volatile
        var instance: BonioProxyImeService? = null
            private set

        @Volatile
        var onInputConnectionReady: CompletableDeferred<InputConnection>? = null
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.i(TAG, "BonioProxyImeService created")
    }

    override fun onDestroy() {
        if (instance === this) {
            instance = null
        }
        Log.i(TAG, "BonioProxyImeService destroyed")
        super.onDestroy()
    }

    // Never show an on-screen keyboard view: prevents visual flicker and layout rearrangement
    override fun onEvaluateInputViewShown(): Boolean = false
    override fun onEvaluateFullscreenMode(): Boolean = false
    override fun onCreateInputView(): View? = null

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        val ic = currentInputConnection
        Log.i(TAG, "onStartInput: pkg=${attribute?.packageName} fieldId=${attribute?.fieldId} hasIc=${ic != null} restarting=$restarting")
        if (ic != null) {
            onInputConnectionReady?.complete(ic)
        }
    }

    override fun onFinishInput() {
        Log.i(TAG, "onFinishInput")
        super.onFinishInput()
    }

    suspend fun injectTextAndSend(text: String, doSend: Boolean = true): Boolean {
        var ic = currentInputConnection
        if (ic == null) {
            Log.i(TAG, "injectTextAndSend: waiting for InputConnection...")
            val deferred = CompletableDeferred<InputConnection>().also { onInputConnectionReady = it }
            ic = withTimeoutOrNull(2500) { deferred.await() }
            onInputConnectionReady = null
        }

        if (ic == null) {
            Log.w(TAG, "injectTextAndSend: InputConnection unavailable after waiting")
            return false
        }

        // Commit text directly into remote editor
        val committed = ic.commitText(text, 1)
        Log.i(TAG, "injectTextAndSend: commitText result=$committed textLength=${text.length}")
        if (!committed) {
            return false
        }

        if (doSend) {
            delay(150)
            // 1. Try standard IME action send
            val actionSent = ic.performEditorAction(EditorInfo.IME_ACTION_SEND)
            Log.i(TAG, "injectTextAndSend: performEditorAction(IME_ACTION_SEND) result=$actionSent")
            if (!actionSent) {
                // 2. Try IME action done or go
                val doneSent = ic.performEditorAction(EditorInfo.IME_ACTION_DONE) ||
                        ic.performEditorAction(EditorInfo.IME_ACTION_GO)
                Log.i(TAG, "injectTextAndSend: performEditorAction(DONE/GO) result=$doneSent")
            }
            // 3. Also send Enter keyevent (WeChat "回车键发送消息")
            sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
        }

        return true
    }
}
