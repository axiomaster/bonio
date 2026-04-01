package ai.axiomaster.boji.remote.chat

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.k2fsa.sherpa.onnx.*

class SherpaOnnxSpeechManager(private val context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var recognizer: OnlineRecognizer? = null
    @Volatile private var running = false
    @Volatile private var cancelled = false
    @Volatile private var recordThread: Thread? = null
    private var currentListener: SpeechToTextManager.Listener? = null

    val isModelReady: Boolean
        get() = recognizer != null

    fun prepareModelAsync(onReady: () -> Unit, onError: (Exception) -> Unit) {
        Thread {
            try {
                val config = OnlineRecognizerConfig(
                    modelConfig = OnlineModelConfig(
                        paraformer = OnlineParaformerModelConfig(
                            encoder = "$MODEL_DIR/encoder.int8.onnx",
                            decoder = "$MODEL_DIR/decoder.int8.onnx",
                        ),
                        tokens = "$MODEL_DIR/tokens.txt",
                        modelType = "paraformer",
                    ),
                    enableEndpoint = true,
                    endpointConfig = EndpointConfig(
                        rule1 = EndpointRule(false, 2.4f, 0.0f),
                        rule2 = EndpointRule(true, 1.4f, 0.0f),
                        rule3 = EndpointRule(false, 0.0f, 20.0f),
                    ),
                )
                val r = OnlineRecognizer(
                    assetManager = context.assets,
                    config = config,
                )
                recognizer = r
                Log.d(TAG, "Sherpa-ONNX model loaded successfully")
                mainHandler.post(onReady)
            } catch (e: Exception) {
                Log.e(TAG, "Sherpa-ONNX model init failed", e)
                mainHandler.post { onError(e) }
            }
        }.start()
    }

    @SuppressLint("MissingPermission")
    fun startListening(listener: SpeechToTextManager.Listener) {
        if (running) {
            stopListening()
        }
        currentListener = listener

        val r = recognizer
        if (r == null) {
            Log.w(TAG, "Recognizer not ready, preparing now...")
            prepareModelAsync(
                onReady = { startListening(listener) },
                onError = {
                    listener.onError(android.speech.SpeechRecognizer.ERROR_CLIENT)
                }
            )
            return
        }

        running = true
        cancelled = false
        recordThread = Thread({
            runRecognitionLoop(r, listener)
        }, "SherpaOnnxRecordThread").apply { start() }
    }

    fun stopListening() {
        running = false
        recordThread?.join(2000)
        recordThread = null
    }

    fun cancelListening() {
        cancelled = true
        running = false
        recordThread?.join(2000)
        recordThread = null
        currentListener = null
    }

    fun destroy() {
        cancelListening()
        recognizer?.release()
        recognizer = null
    }

    @SuppressLint("MissingPermission")
    private fun runRecognitionLoop(r: OnlineRecognizer, listener: SpeechToTextManager.Listener) {
        val sampleRate = 16000
        val bufSize = maxOf(
            AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            ),
            4096
        )

        val audioRecord: AudioRecord
        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufSize
            )
            if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord failed to initialize")
                mainHandler.post { listener.onError(android.speech.SpeechRecognizer.ERROR_AUDIO) }
                return
            }
        } catch (e: Exception) {
            Log.e(TAG, "AudioRecord creation failed", e)
            mainHandler.post { listener.onError(android.speech.SpeechRecognizer.ERROR_AUDIO) }
            return
        }

        val stream = r.createStream()
        try {
            audioRecord.startRecording()
            mainHandler.post { listener.onReadyForSpeech() }

            val buffer = ShortArray(bufSize)
            var lastPartial = ""
            var deliveredFinal = false

            while (running) {
                val samplesRead = audioRecord.read(buffer, 0, buffer.size)
                if (samplesRead <= 0) continue

                val samples = FloatArray(samplesRead)
                for (i in 0 until samplesRead) {
                    samples[i] = buffer[i] / 32768.0f
                }
                stream.acceptWaveform(samples, sampleRate)

                while (r.isReady(stream)) {
                    r.decode(stream)
                }

                val partial = r.getResult(stream).text
                if (partial.isNotBlank() && partial != lastPartial) {
                    lastPartial = partial
                    mainHandler.post { listener.onPartialResult(partial) }
                }

                if (r.isEndpoint(stream)) {
                    val finalText = r.getResult(stream).text
                    if (finalText.isNotBlank()) {
                        deliveredFinal = true
                        running = false
                        mainHandler.post { listener.onFinalResult(finalText) }
                    }
                    r.reset(stream)
                    lastPartial = ""
                }
            }

            if (!cancelled) {
                if (!deliveredFinal) {
                    val finalText = r.getResult(stream).text
                    if (finalText.isNotBlank()) {
                        mainHandler.post { listener.onFinalResult(finalText) }
                    }
                }
                mainHandler.post { listener.onEndOfSpeech() }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Recognition loop error", e)
            mainHandler.post { listener.onError(android.speech.SpeechRecognizer.ERROR_CLIENT) }
        } finally {
            try {
                audioRecord.stop()
                audioRecord.release()
            } catch (_: Exception) {}
            stream.release()
        }
    }

    companion object {
        private const val TAG = "SherpaOnnxSpeechManager"
        private const val MODEL_DIR = "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
    }
}
