package ai.axiomaster.boji.avatar

import ai.axiomaster.boji.ai.AgentManager
import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.remote.chat.SystemTtsManager
import android.media.RingtoneManager
import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

/**
 * Unified executor for server-driven `avatar.command` events.
 * The server sends structured commands; this class dispatches to
 * AvatarController / AgentStateManager / TTS without any business logic.
 */
class AvatarCommandExecutor(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    var ttsManager: SystemTtsManager? = null

    private val json = Json { ignoreUnknownKeys = true }

    fun execute(payloadJson: String?) {
        if (payloadJson.isNullOrBlank()) return
        try {
            val obj = json.parseToJsonElement(payloadJson) as? JsonObject ?: return
            val action = obj["action"]?.jsonPrimitive?.content ?: return
            val params = obj["params"] as? JsonObject
            executeAction(action, params)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to execute avatar.command: ${e.message}")
        }
    }

    private fun executeAction(action: String, params: JsonObject?) {
        scope.launch(Dispatchers.Main) {
            when (action) {
                "setState" -> executeSetState(params)
                "moveTo" -> executeMoveTo(params)
                "setBubble" -> executeSetBubble(params)
                "clearBubble" -> executeClearBubble()
                "tts" -> executeTts(params)
                "stopTts" -> executeStopTts()
                "playSound" -> executePlaySound(params)
                "setColorFilter" -> executeSetColorFilter(params)
                "setPosition" -> executeSetPosition(params)
                "cancelMovement" -> executeCancelMovement()
                "performAction" -> executePerformAction(params)
                "sequence" -> executeSequence(params)
                else -> Log.w(TAG, "Unknown avatar.command action: $action")
            }
        }
    }

    private fun executeSetState(params: JsonObject?) {
        val stateName = params?.get("state")?.jsonPrimitive?.content ?: return
        val state = parseAgentState(stateName) ?: return
        val temporary = try { params["temporary"]?.jsonPrimitive?.boolean ?: false } catch (_: Exception) { false }
        val ctrl = AgentManager.avatarController
        if (temporary) {
            ctrl.showTemporaryState(state)
        } else {
            ctrl.setActivity(state)
        }
    }

    private suspend fun executeMoveTo(params: JsonObject?) {
        val x = params?.get("x")?.jsonPrimitive?.content?.toFloatOrNull() ?: return
        val y = params["y"]?.jsonPrimitive?.content?.toFloatOrNull() ?: return
        val mode = params["mode"]?.jsonPrimitive?.content ?: "walk"
        val ctrl = AgentManager.avatarController

        when (mode) {
            "walk" -> ctrl.walkTo(x, y)
            "run" -> ctrl.runTo(x, y)
            "portal" -> {
                val screenW = ctrl.getScreenWidth().toFloat()
                val currentPos = ctrl.avatarState.value.position
                val exitX = -200f
                ctrl.runTo(exitX, currentPos.y)
                val dist1 = (currentPos.x - exitX).coerceAtLeast(1f)
                val dur1 = ((dist1 / 1200f) * 1000f).toLong().coerceIn(100, 3000)
                delay(dur1 + 80)
                ctrl.cancelMovement()
                ctrl.setPosition(screenW + 200f, y)
                delay(30)
                ctrl.runTo(x, y)
                val dist2 = (screenW + 200f - x).coerceAtLeast(1f)
                val dur2 = ((dist2 / 1200f) * 1000f).toLong().coerceIn(100, 3000)
                delay(dur2 + 80)
            }
            else -> ctrl.walkTo(x, y)
        }
    }

    private fun executeSetBubble(params: JsonObject?) {
        val text = params?.get("text")?.jsonPrimitive?.content ?: return
        val bgColor = try { params["bgColor"]?.jsonPrimitive?.long?.toInt() } catch (_: Exception) { null }
        val textColor = try { params["textColor"]?.jsonPrimitive?.long?.toInt() } catch (_: Exception) { null }
        val countdown = params["countdown"]?.jsonPrimitive?.content

        if (bgColor != null) {
            AgentManager.stateManager.setBubble(text, bgColor, textColor ?: android.graphics.Color.WHITE)
        } else {
            AgentManager.stateManager.setBubble(text)
        }
        if (countdown != null) {
            AgentManager.stateManager.setBubbleCountdown(countdown)
        }
    }

    private fun executeClearBubble() {
        AgentManager.stateManager.clearBubble()
    }

    private fun executeTts(params: JsonObject?) {
        val text = params?.get("text")?.jsonPrimitive?.content ?: return
        ttsManager?.speak(text)
    }

    private fun executeStopTts() {
        ttsManager?.stop()
    }

    private fun executePlaySound(params: JsonObject?) {
        val type = params?.get("type")?.jsonPrimitive?.content ?: "notification"
        try {
            val uriType = when (type) {
                "alarm" -> RingtoneManager.TYPE_ALARM
                else -> RingtoneManager.TYPE_NOTIFICATION
            }
            val uri = RingtoneManager.getDefaultUri(uriType)
            val ringtone = RingtoneManager.getRingtone(context, uri)
            ringtone?.play()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to play sound: ${e.message}")
        }
    }

    private fun executeSetColorFilter(params: JsonObject?) {
        val color = try { params?.get("color")?.jsonPrimitive?.long?.toInt() } catch (_: Exception) { null }
        AgentManager.stateManager.setAvatarColorFilter(color)
    }

    private fun executeSetPosition(params: JsonObject?) {
        val x = params?.get("x")?.jsonPrimitive?.content?.toFloatOrNull() ?: return
        val y = params["y"]?.jsonPrimitive?.content?.toFloatOrNull() ?: return
        AgentManager.avatarController.setPosition(x, y)
    }

    private fun executeCancelMovement() {
        AgentManager.avatarController.cancelMovement()
    }

    private fun executePerformAction(params: JsonObject?) {
        val actionType = params?.get("type")?.jsonPrimitive?.content ?: return
        val x = params["x"]?.jsonPrimitive?.content?.toFloatOrNull()
        val y = params["y"]?.jsonPrimitive?.content?.toFloatOrNull()
        AgentManager.avatarController.performAction(actionType, x, y)
    }

    private suspend fun executeSequence(params: JsonObject?) {
        val steps = params?.get("steps") as? JsonArray ?: return
        for (step in steps) {
            val stepObj = step as? JsonObject ?: continue
            val action = stepObj["action"]?.jsonPrimitive?.content ?: continue
            val stepParams = stepObj["params"] as? JsonObject
            val delayMs = try { stepObj["delayMs"]?.jsonPrimitive?.long ?: 0L } catch (_: Exception) { 0L }

            withContext(Dispatchers.Main) {
                when (action) {
                    "setState" -> executeSetState(stepParams)
                    "moveTo" -> executeMoveTo(stepParams)
                    "setBubble" -> executeSetBubble(stepParams)
                    "clearBubble" -> executeClearBubble()
                    "tts" -> executeTts(stepParams)
                    "stopTts" -> executeStopTts()
                    "playSound" -> executePlaySound(stepParams)
                    "setColorFilter" -> executeSetColorFilter(stepParams)
                    "setPosition" -> executeSetPosition(stepParams)
                    "cancelMovement" -> executeCancelMovement()
                    "performAction" -> executePerformAction(stepParams)
                }
            }

            if (delayMs > 0) {
                delay(delayMs)
            }
        }
    }

    companion object {
        private const val TAG = "AvatarCmdExec"

        fun parseAgentState(name: String): AgentState? = when (name.lowercase()) {
            "idle" -> AgentState.Idle
            "listening" -> AgentState.Listening
            "thinking" -> AgentState.Thinking
            "speaking" -> AgentState.Speaking
            "working" -> AgentState.Working
            "watching" -> AgentState.Watching
            "sleeping" -> AgentState.Sleeping
            "bored" -> AgentState.Bored
            "happy" -> AgentState.Happy
            "confused" -> AgentState.Confused
            "angry" -> AgentState.Angry
            else -> null
        }
    }
}
