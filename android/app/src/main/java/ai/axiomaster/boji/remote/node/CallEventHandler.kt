package ai.axiomaster.boji.remote.node

import android.util.Log
import ai.axiomaster.boji.ai.AgentManager
import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.remote.chat.ChatController
import ai.axiomaster.boji.remote.chat.SpeechToTextManager
import ai.axiomaster.boji.remote.chat.SystemTtsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

class CallEventHandler(
    private val scope: CoroutineScope,
    private val sendEvent: suspend (event: String, payloadJson: String) -> Unit,
) {
    private val json = Json { ignoreUnknownKeys = true }

    var ttsManager: SystemTtsManager? = null
    var sttManager: SpeechToTextManager? = null
    var chatController: ChatController? = null
    var telephonyHandler: TelephonyHandler? = null

    private var isCallSttActive = false
    private var callSttSessionId = 0
    private var lastTtsText: String = ""

    fun handleEvent(event: String, payloadJson: String?): Boolean {
        return when (event) {
            "call.tts" -> {
                handleCallTts(payloadJson)
                true
            }
            "call.stt.start" -> {
                handleSttStart(payloadJson)
                true
            }
            "call.stt.stop" -> {
                handleSttStop()
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
            Log.i(TAG, "Call TTS: $text")

            lastTtsText = text
            AgentManager.avatarController.setActivity(AgentState.Speaking)
            AgentManager.stateManager.setBubble(text)

            val tts = ttsManager
            if (tts != null) {
                tts.onSpeakingDone = {
                    Log.i(TAG, "Call TTS playback finished, notifying server")
                    scope.launch {
                        sendEvent("call.tts.done", "{}")
                    }
                }
                tts.speak(text)
            } else {
                scope.launch {
                    delay(2000)
                    sendEvent("call.tts.done", "{}")
                }
            }

            addChatMessage(text)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse call.tts: ${e.message}")
        }
    }

    private fun handleSttStart(payloadJson: String?) {
        val stt = sttManager ?: run {
            Log.w(TAG, "No STT manager available for call.stt.start")
            return
        }

        if (isCallSttActive) {
            Log.d(TAG, "Call STT already active, ignoring start")
            return
        }

        isCallSttActive = true
        val mySession = ++callSttSessionId
        Log.i(TAG, "Call STT started (session $mySession)")

        AgentManager.avatarController.setActivity(AgentState.Listening)

        stt.startListening(object : SpeechToTextManager.Listener {
            override fun onPartialResult(text: String) {
                if (callSttSessionId != mySession) return
                AgentManager.stateManager.setBubble("🎤 $text")
            }

            override fun onFinalResult(text: String) {
                if (callSttSessionId != mySession) return
                Log.i(TAG, "Call STT final result: $text")
                isCallSttActive = false
                AgentManager.stateManager.clearBubble()

                addChatMessage("\u7528\u6237\u8bed\u97f3: $text", role = "user")

                scope.launch {
                    sendEvent("stt.final_result",
                        """{"text":"$text","context":"call","lastTts":"$lastTtsText"}""")
                }
            }

            override fun onError(errorCode: Int) {
                if (callSttSessionId != mySession) return
                Log.w(TAG, "Call STT error: $errorCode")
                isCallSttActive = false
            }

            override fun onReadyForSpeech() {}

            override fun onEndOfSpeech() {
                if (callSttSessionId != mySession) return
                isCallSttActive = false
            }
        })
    }

    private fun handleSttStop() {
        if (isCallSttActive) {
            isCallSttActive = false
            ++callSttSessionId
            sttManager?.cancelListening()
            Log.i(TAG, "Call STT stopped")
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
