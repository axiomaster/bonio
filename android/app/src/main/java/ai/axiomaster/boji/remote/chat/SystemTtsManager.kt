package ai.axiomaster.boji.remote.chat

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale
import java.util.UUID

class SystemTtsManager(private val context: Context) {
    private var tts: TextToSpeech? = null
    private var isInitialized = false

    var onSpeakingDone: (() -> Unit)? = null

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                isInitialized = true
                tts?.language = Locale.getDefault()
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}

                    override fun onDone(utteranceId: String?) {
                        onSpeakingDone?.invoke()
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        onSpeakingDone?.invoke()
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        onSpeakingDone?.invoke()
                    }
                })
            } else {
                Log.e("SystemTtsManager", "TTS Initialization failed")
            }
        }
    }

    fun speak(text: String) {
        if (!isInitialized) return
        val utteranceId = UUID.randomUUID().toString()
        val params = Bundle()
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
    }

    fun stop() {
        if (isInitialized) {
            tts?.stop()
        }
    }

    fun release() {
        onSpeakingDone = null
        tts?.stop()
        tts?.shutdown()
        tts = null
        isInitialized = false
    }
}
