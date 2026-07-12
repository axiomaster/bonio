package ai.axiomaster.boji.remote.node

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Rect
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.delay

class BoJiAccessibilityService : AccessibilityService() {
  private val recentEventText = ArrayDeque<String>()

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
    event ?: return
    val values = buildList {
      addAll(event.text.map(CharSequence::toString))
      event.contentDescription?.toString()?.let(::add)
    }.filter(String::isNotBlank)
    synchronized(recentEventText) {
      for (value in values) {
        recentEventText.addLast(value.take(500))
        while (recentEventText.size > 80) recentEventText.removeFirst()
      }
    }
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

  /** Inserts text into the active app editor and activates its send action. */
  suspend fun sendTextToActiveChat(text: String): Boolean {
    val root = externalApplicationRoot() ?: return false
    val editor = findFirstNode(root) { it.isEditable && it.isEnabled }
    root.recycle()
    if (editor == null || !setTextOnNode(editor, text)) {
      editor?.recycle()
      return false
    }
    editor.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
    editor.recycle()
    delay(250)

    val refreshedRoot = externalApplicationRoot() ?: return false
    val sendNode = findFirstNode(refreshedRoot) { node ->
      val label = listOf(node.text, node.contentDescription)
        .joinToString(" ") { it?.toString().orEmpty() }.trim()
      node.isEnabled && (label == "发送" || label.equals("send", ignoreCase = true))
    }
    refreshedRoot.recycle()
    var clickable = sendNode
    while (clickable != null && !clickable.isClickable) {
      val parent = clickable.parent
      clickable.recycle()
      clickable = parent
    }
    val sent = clickable?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
    clickable?.recycle()
    return sent
  }

  private fun findFirstNode(
    root: AccessibilityNodeInfo,
    predicate: (AccessibilityNodeInfo) -> Boolean,
  ): AccessibilityNodeInfo? {
    val queue = ArrayDeque<AccessibilityNodeInfo>()
    for (index in 0 until root.childCount) root.getChild(index)?.let(queue::add)
    while (queue.isNotEmpty()) {
      val node = queue.removeFirst()
      if (predicate(node)) {
        while (queue.isNotEmpty()) queue.removeFirst().recycle()
        return node
      }
      for (index in 0 until node.childCount) node.getChild(index)?.let(queue::add)
      node.recycle()
    }
    return null
  }

  /** Returns a compact, privacy-conscious UI tree snapshot for server-side screen understanding. */
  fun dumpActiveWindow(maxNodes: Int = 180, maxTextLength: Int = 240): String? {
    val window = windows
      .sortedByDescending { it.layer }
      .firstOrNull { candidate ->
        candidate.root?.let { root ->
          val isExternal = candidate.type == AccessibilityWindowInfo.TYPE_APPLICATION &&
            root.packageName?.toString() != packageName
          root.recycle()
          isExternal
        } == true
      }
    val root = window?.root ?: rootInActiveWindow ?: return null
    val nodes = JSONArray()
    val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
    queue.add(root to 0)
    try {
      while (queue.isNotEmpty() && nodes.length() < maxNodes) {
        val (node, depth) = queue.removeFirst()
        val bounds = Rect().also(node::getBoundsInScreen)
        val item = JSONObject()
          .put("depth", depth)
          .put("class", node.className?.toString()?.substringAfterLast('.').orEmpty())
          .put("text", node.text?.toString()?.take(maxTextLength).orEmpty())
          .put("description", node.contentDescription?.toString()?.take(maxTextLength).orEmpty())
          .put("view_id", node.viewIdResourceName.orEmpty())
          .put("bounds", "${bounds.left},${bounds.top},${bounds.right},${bounds.bottom}")
          .put("clickable", node.isClickable)
          .put("editable", node.isEditable)
        nodes.put(item)
        for (index in 0 until node.childCount) {
          node.getChild(index)?.let { queue.add(it to depth + 1) }
        }
        if (node !== root) node.recycle()
      }
      return JSONObject()
        .put("package", root.packageName?.toString().orEmpty())
        .put("window_title", window?.title?.toString().orEmpty())
        .put("recent_events", JSONArray(synchronized(recentEventText) { recentEventText.toList() }))
        .put("nodes", nodes)
        .toString()
    } finally {
      while (queue.isNotEmpty()) queue.removeFirst().first.recycle()
      root.recycle()
    }
  }

  private fun externalApplicationRoot(): AccessibilityNodeInfo? {
    return windows
      .sortedByDescending { it.layer }
      .firstNotNullOfOrNull { candidate ->
        if (candidate.type != AccessibilityWindowInfo.TYPE_APPLICATION) return@firstNotNullOfOrNull null
        candidate.root?.takeIf { it.packageName?.toString() != packageName }
      } ?: rootInActiveWindow
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
