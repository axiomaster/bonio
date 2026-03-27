package ai.axiomaster.boji.avatar

import android.os.FileObserver
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.io.RandomAccessFile

/**
 * Watches for action events written by the phone-use-agent binary running on-device.
 * The agent writes JSON lines to [ACTION_EVENT_FILE] during GUI task execution.
 * Each line is a JSON object like: {"action":"tap","x":500,"y":300}
 */
class ActionEventWatcher(
    private val controller: AvatarController,
    private val scope: CoroutineScope,
) {
    companion object {
        private const val TAG = "ActionEventWatcher"
        const val ACTION_EVENT_FILE = "/data/local/tmp/.boji-agent-actions.jsonl"
    }

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private var fileObserver: FileObserver? = null
    private var lastReadPosition = 0L

    fun start() {
        val file = File(ACTION_EVENT_FILE)
        val parentDir = file.parentFile ?: return

        // Reset position tracking
        lastReadPosition = if (file.exists()) file.length() else 0L

        fileObserver = object : FileObserver(parentDir.path, MODIFY or CREATE) {
            override fun onEvent(event: Int, path: String?) {
                if (path == file.name) {
                    readNewLines(file)
                }
            }
        }
        fileObserver?.startWatching()
        Log.d(TAG, "Started watching $ACTION_EVENT_FILE")
    }

    fun stop() {
        fileObserver?.stopWatching()
        fileObserver = null
        Log.d(TAG, "Stopped watching")
    }

    private fun readNewLines(file: File) {
        try {
            if (!file.exists()) return
            val currentLength = file.length()
            if (currentLength <= lastReadPosition) {
                if (currentLength < lastReadPosition) lastReadPosition = 0L
                return
            }

            val raf = RandomAccessFile(file, "r")
            raf.seek(lastReadPosition)
            var line = raf.readLine()
            while (line != null) {
                processLine(line)
                line = raf.readLine()
            }
            lastReadPosition = raf.filePointer
            raf.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error reading action events: ${e.message}")
        }
    }

    private fun processLine(line: String) {
        val trimmed = line.trim()
        if (trimmed.isEmpty()) return
        try {
            val obj = json.parseToJsonElement(trimmed) as? JsonObject ?: return
            val action = obj["action"]?.jsonPrimitive?.contentOrNull ?: return
            val x = obj["x"]?.jsonPrimitive?.doubleOrNull?.toFloat()
            val y = obj["y"]?.jsonPrimitive?.doubleOrNull?.toFloat()

            Log.d(TAG, "Action event: $action at ($x, $y)")
            scope.launch(Dispatchers.Main) {
                controller.performAction(action, x, y)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse action line: $trimmed")
        }
    }
}
