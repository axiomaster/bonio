package ai.axiomaster.boji.remote.chat

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.util.Base64
import android.util.Log
import java.io.File

class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null
    private var startTimeMs: Long = 0

    fun startRecording(): Boolean {
        try {
            outputFile = File.createTempFile("voice_record_", ".m4a", context.cacheDir)
            
            recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioChannels(1)
                setAudioSamplingRate(44100)
                setAudioEncodingBitRate(96000)
                setOutputFile(outputFile?.absolutePath)
                prepare()
                start()
            }
            startTimeMs = System.currentTimeMillis()
            return true
        } catch (e: Exception) {
            Log.e("VoiceRecorder", "Failed to start recording", e)
            cleanup()
            return false
        }
    }

    fun stopRecording(): VoiceResult? {
        if (recorder == null) return null
        
        try {
            recorder?.stop()
        } catch (e: Exception) {
            Log.e("VoiceRecorder", "Failed to stop recording cleanly", e)
        }
        
        recorder?.release()
        recorder = null
        
        val durationMs = System.currentTimeMillis() - startTimeMs
        
        val file = outputFile
        if (file == null || !file.exists()) {
            return null
        }
        
        val bytes = file.readBytes()
        val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        
        return VoiceResult(
            durationMs = durationMs,
            base64 = base64,
            mimeType = "audio/mp4"
        )
    }

    fun cancelRecording() {
        try {
            recorder?.stop()
        } catch (e: Exception) {
            // Ignored
        }
        cleanup()
    }

    private fun cleanup() {
        recorder?.release()
        recorder = null
        try {
            outputFile?.delete()
        } catch (e: Exception) {
            // Ignored
        }
        outputFile = null
    }
}

data class VoiceResult(
    val durationMs: Long,
    val base64: String,
    val mimeType: String
)
