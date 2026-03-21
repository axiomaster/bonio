package ai.axiomaster.boji.remote.chat

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class VoskSpeechManager(private val context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var model: Model? = null
    @Volatile private var running = false
    @Volatile private var recordThread: Thread? = null
    private var currentListener: SpeechToTextManager.Listener? = null

    private val modelDir: File
        get() = File(context.filesDir, MODEL_DIR_NAME)

    val isModelReady: Boolean
        get() = modelDir.exists() && File(modelDir, "conf/model.conf").exists()

    fun prepareModelAsync(onReady: () -> Unit, onError: (Exception) -> Unit) {
        Thread {
            try {
                if (!isModelReady) {
                    extractModelFromAssets()
                }
                val m = Model(modelDir.absolutePath)
                model = m
                mainHandler.post(onReady)
            } catch (e: Exception) {
                Log.e(TAG, "Vosk model init failed", e)
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

        val m = model
        if (m == null) {
            Log.e(TAG, "Vosk model not loaded, preparing now...")
            prepareModelAsync(
                onReady = { startListening(listener) },
                onError = {
                    listener.onError(android.speech.SpeechRecognizer.ERROR_CLIENT)
                }
            )
            return
        }

        running = true
        recordThread = Thread({
            runRecognitionLoop(m, listener)
        }, "VoskRecordThread").apply { start() }
    }

    fun stopListening() {
        running = false
        recordThread?.join(2000)
        recordThread = null
    }

    fun cancelListening() {
        running = false
        recordThread?.join(2000)
        recordThread = null
        currentListener = null
    }

    fun destroy() {
        cancelListening()
        model?.close()
        model = null
    }

    @SuppressLint("MissingPermission")
    private fun runRecognitionLoop(m: Model, listener: SpeechToTextManager.Listener) {
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

        val recognizer = Recognizer(m, sampleRate.toFloat())
        try {
            audioRecord.startRecording()
            mainHandler.post { listener.onReadyForSpeech() }

            val buffer = ByteArray(bufSize)
            var deliveredFinal = false
            while (running) {
                val bytesRead = audioRecord.read(buffer, 0, buffer.size)
                if (bytesRead <= 0) continue

                if (recognizer.acceptWaveForm(buffer, bytesRead)) {
                    // VAD detected end of speech — deliver final result and stop
                    val text = parseText(recognizer.result)
                    if (text.isNotBlank()) {
                        deliveredFinal = true
                        running = false
                        mainHandler.post { listener.onFinalResult(text) }
                    }
                } else {
                    val partial = parsePartial(recognizer.partialResult)
                    if (partial.isNotBlank()) {
                        mainHandler.post { listener.onPartialResult(partial) }
                    }
                }
            }

            // User stopped manually (finger lifted) — flush remaining audio
            if (!deliveredFinal) {
                val finalText = parseText(recognizer.finalResult)
                if (finalText.isNotBlank()) {
                    mainHandler.post { listener.onFinalResult(finalText) }
                }
            }
            mainHandler.post { listener.onEndOfSpeech() }
        } catch (e: Exception) {
            Log.e(TAG, "Recognition loop error", e)
            mainHandler.post { listener.onError(android.speech.SpeechRecognizer.ERROR_CLIENT) }
        } finally {
            try {
                audioRecord.stop()
                audioRecord.release()
            } catch (_: Exception) {}
            recognizer.close()
        }
    }

    private fun parseText(json: String): String {
        return try {
            JSONObject(json).optString("text", "")
        } catch (_: Exception) { "" }
    }

    private fun parsePartial(json: String): String {
        return try {
            JSONObject(json).optString("partial", "")
        } catch (_: Exception) { "" }
    }

    private fun extractModelFromAssets() {
        val targetDir = modelDir
        if (targetDir.exists()) {
            targetDir.deleteRecursively()
        }
        targetDir.mkdirs()
        copyAssetsDir(ASSET_MODEL_DIR, targetDir)
        Log.d(TAG, "Vosk model extracted to ${targetDir.absolutePath}")
    }

    private fun copyAssetsDir(assetPath: String, targetDir: File) {
        val assetManager = context.assets
        val entries = assetManager.list(assetPath) ?: return
        if (entries.isEmpty()) {
            // It's a file
            try {
                assetManager.open(assetPath).use { input ->
                    FileOutputStream(File(targetDir.parentFile, File(assetPath).name)).use { output ->
                        input.copyTo(output)
                    }
                }
            } catch (e: IOException) {
                Log.e(TAG, "Failed to copy asset $assetPath", e)
            }
        } else {
            val subDir = File(targetDir, "")
            for (entry in entries) {
                val childAssetPath = "$assetPath/$entry"
                val childEntries = assetManager.list(childAssetPath)
                if (childEntries != null && childEntries.isNotEmpty()) {
                    val childDir = File(targetDir, entry)
                    childDir.mkdirs()
                    copyAssetsDirRecursive(childAssetPath, childDir)
                } else {
                    try {
                        assetManager.open(childAssetPath).use { input ->
                            FileOutputStream(File(targetDir, entry)).use { output ->
                                input.copyTo(output)
                            }
                        }
                    } catch (e: IOException) {
                        Log.e(TAG, "Failed to copy asset file $childAssetPath", e)
                    }
                }
            }
        }
    }

    private fun copyAssetsDirRecursive(assetPath: String, targetDir: File) {
        val assetManager = context.assets
        val entries = assetManager.list(assetPath) ?: return
        for (entry in entries) {
            val childAssetPath = "$assetPath/$entry"
            val childEntries = assetManager.list(childAssetPath)
            if (childEntries != null && childEntries.isNotEmpty()) {
                val childDir = File(targetDir, entry)
                childDir.mkdirs()
                copyAssetsDirRecursive(childAssetPath, childDir)
            } else {
                try {
                    assetManager.open(childAssetPath).use { input ->
                        FileOutputStream(File(targetDir, entry)).use { output ->
                            input.copyTo(output)
                        }
                    }
                } catch (e: IOException) {
                    Log.e(TAG, "Failed to copy asset file $childAssetPath", e)
                }
            }
        }
    }

    companion object {
        private const val TAG = "VoskSpeechManager"
        private const val ASSET_MODEL_DIR = "vosk-model-small-cn"
        private const val MODEL_DIR_NAME = "vosk-model-small-cn"
    }
}
