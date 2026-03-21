package ai.axiomaster.boji.remote.chat

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

    private val voskManager = VoskSpeechManager(context)
    @Volatile
    private var usingVosk = false

    fun startListening(listener: Listener) {
        mainHandler.post {
            if (systemSttAvailable == false) {
                Log.d(TAG, "System STT known unavailable, using Vosk directly")
                startVoskListening(listener)
            } else {
                startListeningOnMain(listener)
            }
        }
    }

    private var startTimeoutRunnable: Runnable? = null

    private fun startVoskListening(listener: Listener) {
        currentListener = listener
        usingVosk = true
        listening = true
        val wrappedListener = object : Listener {
            override fun onPartialResult(text: String) { listener.onPartialResult(text) }
            override fun onFinalResult(text: String) {
                listening = false
                usingVosk = false
                listener.onFinalResult(text)
            }
            override fun onError(errorCode: Int) {
                listening = false
                usingVosk = false
                listener.onError(errorCode)
            }
            override fun onReadyForSpeech() { listener.onReadyForSpeech() }
            override fun onEndOfSpeech() {
                listening = false
                usingVosk = false
                listener.onEndOfSpeech()
            }
        }
        voskManager.startListening(wrappedListener)
    }

    private fun startListeningOnMain(listener: Listener) {
        if (listening) {
            stopListeningOnMain()
        }
        destroyRecognizer()
        currentListener = listener
        usingVosk = false

        recognizer = createRecognizer()
        if (recognizer == null) {
            Log.e(TAG, "SpeechRecognizer unavailable on this device, switching to Vosk")
            systemSttAvailable = false
            startVoskListening(listener)
            return
        }

        var gotCallback = false

        recognizer!!.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                Log.d(TAG, "onReadyForSpeech")
                gotCallback = true
                cancelStartTimeout()
                systemSttAvailable = true
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

                // System STT failed — fall back to Vosk for this and all future calls
                if (systemSttAvailable != true) {
                    Log.w(TAG, "System STT probe failed (error=$error), switching to Vosk fallback")
                    systemSttAvailable = false
                    startVoskListening(listener)
                } else {
                    currentListener?.onError(error)
                }
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
                Log.w(TAG, "SpeechRecognizer start timeout — no callback received, falling back to Vosk")
                listening = false
                destroyRecognizer()
                systemSttAvailable = false
                startVoskListening(listener)
            }
        }
        mainHandler.postDelayed(startTimeoutRunnable!!, 1000L)
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
        if (usingVosk) {
            voskManager.stopListening()
        } else {
            listening = false
            try {
                recognizer?.stopListening()
            } catch (e: Exception) {
                Log.w(TAG, "stopListening error", e)
            }
            destroyRecognizer()
        }
    }

    fun cancelListening() {
        mainHandler.post { cancelListeningOnMain() }
    }

    private fun cancelListeningOnMain() {
        cancelStartTimeout()
        listening = false
        if (usingVosk) {
            voskManager.cancelListening()
        } else {
            try {
                recognizer?.cancel()
            } catch (e: Exception) {
                Log.w(TAG, "cancelListening error", e)
            }
            destroyRecognizer()
        }
        usingVosk = false
        currentListener = null
    }

    fun isListening(): Boolean = listening

    fun destroy() {
        mainHandler.post {
            cancelListeningOnMain()
            voskManager.destroy()
        }
    }

    /**
     * Pre-initialize the Vosk model in background so first voice input is fast.
     */
    fun warmUpVosk() {
        voskManager.prepareModelAsync(
            onReady = { Log.d(TAG, "Vosk model warmed up successfully") },
            onError = { Log.w(TAG, "Vosk model warm-up failed", it) }
        )
    }

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
        @Volatile
        private var systemSttAvailable: Boolean? = null  // null = not yet probed; shared across instances
    }
}
