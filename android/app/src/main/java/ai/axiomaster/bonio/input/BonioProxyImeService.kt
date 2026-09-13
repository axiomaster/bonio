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
        var currentAttribute: EditorInfo? = null
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
            currentAttribute = null
        }
        Log.i(TAG, "BonioProxyImeService destroyed")
        super.onDestroy()
    }

    // Never show an on-screen keyboard view: prevents visual flicker and layout rearrangement
    override fun onEvaluateInputViewShown(): Boolean = false
    override fun onEvaluateFullscreenMode(): Boolean = false
    override fun onCreateInputView(): View? = null

    fun isRealEditorConnected(): Boolean {
        val attr = currentAttribute
        val ic = currentInputConnection
        return ic != null && attr != null && attr.inputType != EditorInfo.TYPE_NULL
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        currentAttribute = attribute
        val ic = currentInputConnection
        val isRealEditor = attribute != null && attribute.inputType != EditorInfo.TYPE_NULL
        Log.i(TAG, "onStartInput: pkg=${attribute?.packageName} fieldId=${attribute?.fieldId} inputType=${attribute?.inputType} isRealEditor=$isRealEditor hasIc=${ic != null} restarting=$restarting")
        if (ic != null && isRealEditor) {
            onInputConnectionReady?.complete(ic)
        }
    }

    override fun onFinishInput() {
        Log.i(TAG, "onFinishInput")
        currentAttribute = null
        super.onFinishInput()
    }

    data class InjectionResult(
        val committed: Boolean,
        val sentViaAction: Boolean
    )

    suspend fun injectTextAndSend(text: String, doSend: Boolean = true, useEnterKey: Boolean = false): InjectionResult {
        var ic = currentInputConnection
        if (ic == null || !isRealEditorConnected()) {
            Log.i(TAG, "injectTextAndSend: waiting for real editor InputConnection...")
            val deferred = CompletableDeferred<InputConnection>().also { onInputConnectionReady = it }
            ic = withTimeoutOrNull(2000) { deferred.await() }
            onInputConnectionReady = null
        }

        if (ic == null) {
            ic = currentInputConnection
        }

        if (ic == null) {
            Log.w(TAG, "injectTextAndSend: InputConnection unavailable after waiting")
            return InjectionResult(committed = false, sentViaAction = false)
        }

        // Commit text directly into remote editor
        val committed = ic.commitText(text, 1)
        Log.i(TAG, "injectTextAndSend: commitText result=$committed textLength=${text.length}")
        if (!committed) {
            return InjectionResult(committed = false, sentViaAction = false)
        }

        var actionSent = false
        if (doSend) {
            delay(100)
            // 1. Try standard IME action send
            actionSent = ic.performEditorAction(EditorInfo.IME_ACTION_SEND)
            Log.i(TAG, "injectTextAndSend: performEditorAction(IME_ACTION_SEND) result=$actionSent")
            if (!actionSent) {
                // 2. Try IME action done or go
                val doneSent = ic.performEditorAction(EditorInfo.IME_ACTION_DONE) ||
                        ic.performEditorAction(EditorInfo.IME_ACTION_GO)
                Log.i(TAG, "injectTextAndSend: performEditorAction(DONE/GO) result=$doneSent")
                if (doneSent) actionSent = true
            }
            if (!actionSent && useEnterKey) {
                sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
            }
        }

        return InjectionResult(committed = true, sentViaAction = actionSent)
    }
}
