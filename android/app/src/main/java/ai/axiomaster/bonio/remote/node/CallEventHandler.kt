package ai.axiomaster.bonio.remote.node

import android.util.Log
import ai.axiomaster.bonio.ai.AgentManager
import ai.axiomaster.bonio.remote.chat.ChatController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

class CallEventHandler(
    private val scope: CoroutineScope,
    private val sendEvent: suspend (event: String, payloadJson: String) -> Unit,
) {
    private val json = Json { ignoreUnknownKeys = true }

    var chatController: ChatController? = null
    var telephonyHandler: TelephonyHandler? = null

    fun handleEvent(event: String, payloadJson: String?): Boolean {
        return when (event) {
            "call.tts" -> {
                handleCallTts(payloadJson)
                true
            }
            "call.stt.start" -> {
                Log.i(TAG, "call.stt.start ignored (voice input removed)")
                true
            }
            "call.stt.stop" -> {
                Log.i(TAG, "call.stt.stop ignored (voice input removed)")
                true
            }
            "call.action" -> {
                handleCallAction(payloadJson)
                true
            }
            "chat.local_message" -> {
                handleLocalChatMessage(payloadJson)
                true
            }
            else -> false
        }
    }

    fun onLocalCallEnded() {
        Log.i(TAG, "Local call ended, notifying server")
        scope.launch {
            sendEvent("telephony.call_ended", "{}")
        }
    }

    private fun handleCallTts(payloadJson: String?) {
        if (payloadJson == null) return
        try {
            val obj = json.parseToJsonElement(payloadJson) as? JsonObject ?: return
            val text = obj["text"]?.jsonPrimitive?.content ?: return
            Log.i(TAG, "Call TTS (speech output removed, bubble only): $text")

            AgentManager.stateManager.setBubble(text)

            // Voice is removed: acknowledge immediately so the server's call
            // flow (which waits for call.tts.done) keeps progressing.
            scope.launch {
                sendEvent("call.tts.done", "{}")
            }

            addChatMessage(text)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse call.tts: ${e.message}")
        }
    }

    private fun handleCallAction(payloadJson: String?) {
        if (payloadJson == null) return
        try {
            val obj = json.parseToJsonElement(payloadJson) as? JsonObject ?: return
            val action = obj["action"]?.jsonPrimitive?.content ?: return
            Log.i(TAG, "Call action received: $action")

            val handler = telephonyHandler
            if (handler == null) {
                Log.w(TAG, "No TelephonyHandler available for call.action")
                return
            }

            scope.launch(Dispatchers.Main) {
                when (action) {
                    "answer" -> handler.handleAnswer(null)
                    "reject" -> handler.handleReject(null)
                    else -> Log.w(TAG, "Unknown call action: $action")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse call.action: ${e.message}")
        }
    }

    private fun handleLocalChatMessage(payloadJson: String?) {
        if (payloadJson == null) return
        try {
            val obj = json.parseToJsonElement(payloadJson) as? JsonObject ?: return
            val text = obj["text"]?.jsonPrimitive?.content ?: return
            val role = obj["role"]?.jsonPrimitive?.content ?: "assistant"
            addChatMessage(text, role = role)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse chat.local_message: ${e.message}")
        }
    }

    private fun addChatMessage(text: String, role: String = "assistant") {
        val chat = chatController ?: return
        chat.addLocalMessage(role, text)
    }

    companion object {
        private const val TAG = "CallEventHandler"
        private const val RUN_SPEED = 1200f
    }
}
