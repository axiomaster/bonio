package ai.axiomaster.bonio.remote.chat

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import java.util.Locale

/**
 * Speech-to-text using the platform SpeechRecognizer only. The offline
 * Sherpa-ONNX fallback (≈255MB models + runtime) is cut from v1 to slim the
 * APK; on devices without a system recognizer voice input degrades to an
 * error callback and the caller resets to idle.
 */
class SpeechToTextManager(private val context: Context) {

    interface Listener {
        fun onPartialResult(text: String)
        fun onFinalResult(text: String)
        fun onError(errorCode: Int)
        fun onReadyForSpeech()
        fun onEndOfSpeech()
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var currentListener: Listener? = null
    @Volatile
    private var listening = false

    fun startListening(listener: Listener) {
        mainHandler.post { startListeningOnMain(listener) }
    }

    private var startTimeoutRunnable: Runnable? = null

    private fun startListeningOnMain(listener: Listener) {
        if (listening) {
            stopListeningOnMain()
        }
        destroyRecognizer()
        currentListener = listener

        recognizer = createRecognizer()
        if (recognizer == null) {
            Log.e(TAG, "SpeechRecognizer unavailable on this device")
            listener.onError(SpeechRecognizer.ERROR_CLIENT)
            return
        }

        var gotCallback = false

        recognizer!!.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                Log.d(TAG, "onReadyForSpeech")
                gotCallback = true
                cancelStartTimeout()
                listening = true
                currentListener?.onReadyForSpeech()
            }

            override fun onBeginningOfSpeech() {
                Log.d(TAG, "onBeginningOfSpeech")
                gotCallback = true
                cancelStartTimeout()
            }

            override fun onRmsChanged(rmsdB: Float) {}

            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {
                Log.d(TAG, "onEndOfSpeech")
                currentListener?.onEndOfSpeech()
            }

            override fun onError(error: Int) {
                Log.w(TAG, "SpeechRecognizer error: $error")
                gotCallback = true
                cancelStartTimeout()
                listening = false
                destroyRecognizer()
                currentListener?.onError(error)
            }

            override fun onResults(results: Bundle?) {
                listening = false
                val texts = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val finalText = texts?.firstOrNull() ?: ""
                Log.d(TAG, "onResults: '$finalText'")
                destroyRecognizer()
                if (finalText.isNotBlank()) {
                    currentListener?.onFinalResult(finalText)
                } else {
                    currentListener?.onError(SpeechRecognizer.ERROR_NO_MATCH)
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val texts = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val partial = texts?.firstOrNull() ?: return
                if (partial.isNotBlank()) {
                    currentListener?.onPartialResult(partial)
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        Log.d(TAG, "startListening (system STT)")
        recognizer!!.startListening(intent)

        startTimeoutRunnable = Runnable {
            if (!gotCallback) {
                Log.w(TAG, "SpeechRecognizer start timeout — no callback received")
                listening = false
                destroyRecognizer()
                listener.onError(SpeechRecognizer.ERROR_CLIENT)
            }
        }
        mainHandler.postDelayed(startTimeoutRunnable!!, 1500L)
    }

    private fun cancelStartTimeout() {
        startTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        startTimeoutRunnable = null
    }

    fun stopListening() {
        mainHandler.post { stopListeningOnMain() }
    }

    private fun stopListeningOnMain() {
        cancelStartTimeout()
        listening = false
        try {
            recognizer?.stopListening()
        } catch (e: Exception) {
            Log.w(TAG, "stopListening error", e)
        }
        destroyRecognizer()
    }

    fun cancelListening() {
        mainHandler.post { cancelListeningOnMain() }
    }

    private fun cancelListeningOnMain() {
        cancelStartTimeout()
        listening = false
        try {
            recognizer?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "cancelListening error", e)
        }
        destroyRecognizer()
        currentListener = null
    }

    fun isListening(): Boolean = listening

    fun destroy() {
        mainHandler.post { cancelListeningOnMain() }
    }

    /**
     * No-op: the offline model warm-up was removed with the Sherpa-ONNX cut.
     * Kept for source compatibility with existing call sites.
     */
    fun warmUp() {}

    private fun destroyRecognizer() {
        try {
            recognizer?.destroy()
        } catch (e: Exception) {
            Log.w(TAG, "destroyRecognizer error", e)
        }
        recognizer = null
    }

    private fun createRecognizer(): SpeechRecognizer? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
                Log.d(TAG, "Using on-device recognizer")
                return SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            }
        }
        if (SpeechRecognizer.isRecognitionAvailable(context)) {
            Log.d(TAG, "Using default recognizer")
            return SpeechRecognizer.createSpeechRecognizer(context)
        }
        Log.e(TAG, "No speech recognizer available")
        return null
    }

    companion object {
        private const val TAG = "SpeechToTextManager"
    }
}
