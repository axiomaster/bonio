package ai.axiomaster.boji.remote.node

import ai.axiomaster.boji.ai.AgentManager
import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.remote.gateway.GatewaySession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.math.sqrt

class InputHandler {

  suspend fun handleInputType(paramsJson: String?): GatewaySession.InvokeResult {
    val a11y =
      BoJiAccessibilityService.instance
        ?: return GatewaySession.InvokeResult.error(
          code = "ACCESSIBILITY_NOT_ENABLED",
          message = "Enable BoJi Accessibility Service in device Settings",
        )

    val params = parseJsonParamsObject(paramsJson)
    val text =
      parseJsonString(params, "text")
        ?: return GatewaySession.InvokeResult.error(
          code = "INVALID_REQUEST",
          message = "text parameter required",
        )
    val animate = parseJsonBooleanFlag(params, "animate") ?: true
    val charDelay = (parseJsonInt(params, "charDelayMs") ?: 80).toLong().coerceIn(20, 500)

    val inputInfo =
      a11y.findFocusedInput()
        ?: return GatewaySession.InvokeResult.error(
          code = "NO_INPUT_FOCUSED",
          message = "No editable input field is focused",
        )

    val ctrl = AgentManager.avatarController

    if (animate) {
      withContext(Dispatchers.Main) {
        val fieldX = inputInfo.bounds.centerX().toFloat()
        val fieldY = (inputInfo.bounds.top - 100f).coerceAtLeast(0f)
        ctrl.runTo(fieldX, fieldY)
      }

      val targetX = inputInfo.bounds.centerX().toFloat()
      val targetY = (inputInfo.bounds.top - 100f).coerceAtLeast(0f)
      val dist =
        sqrt(
          ((ctrl.avatarState.value.position.x - targetX) * (ctrl.avatarState.value.position.x - targetX) +
              (ctrl.avatarState.value.position.y - targetY) * (ctrl.avatarState.value.position.y - targetY))
            .toDouble(),
        ).toFloat()
      val moveMs = ((dist / 1200f) * 1000f).toLong().coerceIn(100, 3000)
      delay(moveMs + 100)

      withContext(Dispatchers.Main) { ctrl.setActivity(AgentState.Working) }
    }

    val success = a11y.typeTextProgressively(text, charDelay)

    if (animate) {
      withContext(Dispatchers.Main) { ctrl.showTemporaryState(AgentState.Happy) }
    }

    return if (success) {
      GatewaySession.InvokeResult.ok("""{"typed":true,"length":${text.length}}""")
    } else {
      GatewaySession.InvokeResult.error(
        code = "TYPE_FAILED",
        message = "Failed to type text into input field",
      )
    }
  }

  suspend fun handleInputFind(@Suppress("UNUSED_PARAMETER") paramsJson: String?): GatewaySession.InvokeResult {
    val a11y =
      BoJiAccessibilityService.instance
        ?: return GatewaySession.InvokeResult.error(
          code = "ACCESSIBILITY_NOT_ENABLED",
          message = "Enable BoJi Accessibility Service in device Settings",
        )

    val info = a11y.findFocusedInput() ?: return GatewaySession.InvokeResult.ok("""{"found":false}""")

    val payload =
      buildJsonObject {
        put("found", true)
        put(
          "bounds",
          buildJsonObject {
            put("left", info.bounds.left)
            put("top", info.bounds.top)
            put("right", info.bounds.right)
            put("bottom", info.bounds.bottom)
          },
        )
        put("text", info.node.text?.toString() ?: "")
      }
        .toString()

    return GatewaySession.InvokeResult.ok(payload)
  }
}
