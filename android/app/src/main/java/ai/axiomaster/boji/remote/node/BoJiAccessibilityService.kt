package ai.axiomaster.boji.remote.node

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Rect
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import kotlinx.coroutines.delay

class BoJiAccessibilityService : AccessibilityService() {

  override fun onServiceConnected() {
    val info =
      AccessibilityServiceInfo().apply {
        eventTypes = AccessibilityEvent.TYPES_ALL_MASK
        feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        flags =
          AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
            AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        notificationTimeout = 100
      }
    serviceInfo = info
    instance = this
    Log.i(TAG, "BoJi Accessibility Service connected")
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent?) {
    // We don't need to process events actively; we query on-demand
  }

  override fun onInterrupt() {
    Log.w(TAG, "BoJi Accessibility Service interrupted")
  }

  override fun onDestroy() {
    instance = null
    super.onDestroy()
  }

  /**
   * Find the currently focused editable node (input field). Returns the node and its screen bounds, or null if no
   * input is focused.
   */
  @Suppress("DEPRECATION")
  fun findFocusedInput(): InputFieldInfo? {
    val root = rootInActiveWindow ?: return null
    val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
    root.recycle()
    if (focused == null) return null
    if (!focused.isEditable) {
      // Walk up to find an editable parent
      var node: AccessibilityNodeInfo? = focused
      while (node != null && !node.isEditable) {
        node = node.parent
      }
      if (node == null || !node.isEditable) return null
      val rect = Rect()
      node.getBoundsInScreen(rect)
      return InputFieldInfo(node, rect)
    }
    val rect = Rect()
    focused.getBoundsInScreen(rect)
    return InputFieldInfo(focused, rect)
  }

  /** Set text on a specific node using ACTION_SET_TEXT. */
  fun setTextOnNode(node: AccessibilityNodeInfo, text: String): Boolean {
    val args = Bundle()
    args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
    return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
  }

  /** Set text on the currently focused input field. */
  fun setTextOnFocusedInput(text: String): Boolean {
    val info = findFocusedInput() ?: return false
    return setTextOnNode(info.node, text)
  }

  /**
   * Append text character by character with a delay, updating the node text progressively. Returns the final text set,
   * or null on failure.
   */
  suspend fun typeTextProgressively(
    text: String,
    charDelayMs: Long = 80,
    onCharTyped: ((currentText: String, charIndex: Int) -> Unit)? = null,
  ): Boolean {
    val info = findFocusedInput() ?: return false
    val existingText = info.node.text?.toString() ?: ""

    for (i in text.indices) {
      val partial = existingText + text.substring(0, i + 1)
      val success = setTextOnNode(info.node, partial)
      if (!success) return false
      onCharTyped?.invoke(partial, i)
      delay(charDelayMs)
    }
    return true
  }

  data class InputFieldInfo(val node: AccessibilityNodeInfo, val bounds: Rect)

  companion object {
    private const val TAG = "BoJiA11y"

    @Volatile var instance: BoJiAccessibilityService? = null
      private set

    val isEnabled: Boolean
      get() = instance != null
  }
}
