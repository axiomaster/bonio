package ai.axiomaster.bonio.remote.node

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Rect
import android.graphics.Path
import android.accessibilityservice.GestureDescription
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import org.json.JSONArray
import org.json.JSONObject
import android.graphics.Bitmap
import android.view.Display
import android.util.Base64
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.delay
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull

class BonioAccessibilityService : AccessibilityService() {
  private val recentEventText = ArrayDeque<String>()

  override fun onServiceConnected() {
    val info = serviceInfo ?: AccessibilityServiceInfo()
    info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK
    info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC or AccessibilityServiceInfo.FEEDBACK_SPOKEN
    info.flags = info.flags or
      AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
      AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
      AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
    info.notificationTimeout = 100
    serviceInfo = info
    instance = this
    ai.axiomaster.bonio.util.AppLogger.i(TAG, "Bonio Accessibility Service connected flags=${info.flags}")
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
    Log.w(TAG, "Bonio Accessibility Service interrupted")
  }

  override fun onDestroy() {
    instance = null
    super.onDestroy()
  }

  /**
   * Find the currently focused editable node (input field). Returns the node and its screen bounds, or null if no
   * input is focused. Searches across all active interactive windows.
   */
  @Suppress("DEPRECATION")
  fun findFocusedInput(): InputFieldInfo? {
    val roots = mutableListOf<AccessibilityNodeInfo>()
    rootInActiveWindow?.let(roots::add)
    for (w in windows) {
      val r = w.root
      if (r != null && roots.none { it == r }) {
        roots.add(r)
      } else {
        r?.recycle()
      }
    }

    try {
      for (root in roots) {
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focused != null) {
          if (!focused.isEditable) {
            var node: AccessibilityNodeInfo? = focused
            while (node != null && !node.isEditable) {
              val parent = node.parent
              node.recycle()
              node = parent
            }
            if (node != null && node.isEditable) {
              val rect = Rect()
              node.getBoundsInScreen(rect)
              return InputFieldInfo(node, rect)
            }
          } else {
            val rect = Rect()
            focused.getBoundsInScreen(rect)
            return InputFieldInfo(focused, rect)
          }
        }
      }
    } finally {
      for (r in roots) r.recycle()
    }
    return null
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
    val res = setTextOnNode(info.node, text)
    info.node.recycle()
    return res
  }

  /** Find the bottommost editable node in the active window (chat input field is always at bottom). */
  fun findBottommostEditor(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
    val queue = ArrayDeque<AccessibilityNodeInfo>()
    for (index in 0 until root.childCount) root.getChild(index)?.let(queue::add)
    var bottommost: AccessibilityNodeInfo? = null
    var maxBottom = -1
    val rect = Rect()
    while (queue.isNotEmpty()) {
      val node = queue.removeFirst()
      if (node.isEditable && node.isEnabled) {
        node.getBoundsInScreen(rect)
        if (rect.bottom > maxBottom) {
          maxBottom = rect.bottom
          bottommost?.recycle()
          bottommost = AccessibilityNodeInfo.obtain(node)
        }
      }
      for (index in 0 until node.childCount) node.getChild(index)?.let(queue::add)
      node.recycle()
    }
    return bottommost
  }

  /** Inserts text into the active app editor and activates its send action. */
  suspend fun sendTextToActiveChat(text: String): Boolean {
    val root = externalApplicationRoot()
    val editor = if (root != null) {
      val found = findBottommostEditor(root) ?: findFirstNode(root) { it.isEditable && it.isEnabled }
      root.recycle()
      found
    } else null

    val editorRect = Rect()
    var textInjected = false

    if (editor != null) {
      editor.getBoundsInScreen(editorRect)
      textInjected = setTextOnNode(editor, text)
      if (!textInjected) {
        editor.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        delay(100)
        textInjected = setTextOnNode(editor, text)
      }
      editor.recycle()
    }

    // Fallback: tap bottom input area if editor not found or injection failed
    if (!textInjected) {
      val dm = resources.displayMetrics
      val tapX = (dm.widthPixels * 0.35f)
      val tapY = (dm.heightPixels * 0.95f)
      ai.axiomaster.bonio.util.AppLogger.i(TAG, "sendTextToActiveChat: tapping input area fallback at ($tapX, $tapY)")
      val tapOk = tapScreenPoint(tapX, tapY)
      if (tapOk) {
        delay(350)
        val focused = findFocusedInput()
        if (focused != null) {
          textInjected = setTextOnNode(focused.node, text)
          editorRect.set(focused.bounds)
          focused.node.recycle()
        }
      }
    }

    if (!textInjected) {
      ai.axiomaster.bonio.util.AppLogger.w(TAG, "sendTextToActiveChat: failed to inject text")
      return false
    }

    // Allow UI a moment to update and render the send button (e.g. '+' switches to '发送')
    delay(250)

    // Re-check focused editor bounds after keyboard may have shifted layout
    val activeEditor = findFocusedInput()
    if (activeEditor != null) {
      if (activeEditor.bounds.centerY() > 0) {
        editorRect.set(activeEditor.bounds)
      }
      activeEditor.node.recycle()
    }

    val refreshedRoot = externalApplicationRoot()
    val sendNode = if (refreshedRoot != null) {
      val found = findFirstNode(refreshedRoot) { node ->
        val label = listOf(node.text, node.contentDescription, node.viewIdResourceName)
          .joinToString(" ") { it?.toString().orEmpty() }.trim()
        node.isEnabled && (
          label == "发送" || label.equals("send", ignoreCase = true) ||
          label.contains("发送") || label.contains("btn_send", ignoreCase = true) ||
          label.contains("send_button", ignoreCase = true)
        )
      }
      refreshedRoot.recycle()
      found
    } else null

    var sent = false
    if (sendNode != null) {
      val sendRect = Rect()
      sendNode.getBoundsInScreen(sendRect)

      var clickable: AccessibilityNodeInfo? = sendNode
      while (clickable != null && !clickable.isClickable) {
        val parent = clickable.parent
        clickable.recycle()
        clickable = parent
      }
      sent = clickable?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
      clickable?.recycle()

      if (!sent && sendRect.width() > 0 && sendRect.height() > 0) {
        ai.axiomaster.bonio.util.AppLogger.i(TAG, "sendTextToActiveChat: tapping sendNode bounds at (${sendRect.centerX()}, ${sendRect.centerY()})")
        sent = tapScreenPoint(sendRect.centerX().toFloat(), sendRect.centerY().toFloat())
      }
    }

    // Fallback: if send button node not found, tap right edge of editor row
    if (!sent) {
      val dm = resources.displayMetrics
      val fallbackX = if (editorRect.right > 0 && editorRect.right < dm.widthPixels) {
        (editorRect.right + dm.widthPixels) / 2f
      } else {
        dm.widthPixels * 0.92f
      }
      val fallbackY = if (editorRect.centerY() > 0) editorRect.centerY().toFloat() else (dm.heightPixels * 0.95f)
      ai.axiomaster.bonio.util.AppLogger.i(TAG, "sendTextToActiveChat: fallback tap send area at ($fallbackX, $fallbackY)")
      sent = tapScreenPoint(fallbackX, fallbackY)
    }

    ai.axiomaster.bonio.util.AppLogger.i(TAG, "sendTextToActiveChat: result=$sent")
    return sent
  }

  /** Writes text to the active app's reply field without sending it. */
  suspend fun fillActiveReplyField(text: String): Boolean {
    val root = externalApplicationRoot()
    val editor = if (root != null) {
      val found = findBottommostEditor(root) ?: findFirstNode(root) { it.isEditable && it.isEnabled }
      root.recycle()
      found
    } else null

    if (editor != null) {
      val rect = Rect()
      editor.getBoundsInScreen(rect)
      val accepted = setTextOnNode(editor, text)
      editor.recycle()
      if (accepted) {
        ai.axiomaster.bonio.util.AppLogger.i(TAG, "fillActiveReplyField: setTextOnNode succeeded directly")
        return true
      }

      // Tap editor then retry
      if (rect.width() > 0 && rect.height() > 0) {
        tapScreenPoint(rect.centerX().toFloat(), rect.centerY().toFloat())
        delay(300)
        val focused = findFocusedInput()
        if (focused != null) {
          val res = setTextOnNode(focused.node, text)
          focused.node.recycle()
          ai.axiomaster.bonio.util.AppLogger.i(TAG, "fillActiveReplyField: setTextOnFocusedInput result=$res")
          return res
        }
      }
    }

    // Dynamic tap bottom area fallback
    val dm = resources.displayMetrics
    val tapX = (dm.widthPixels * 0.35f)
    val tapY = (dm.heightPixels * 0.95f)
    ai.axiomaster.bonio.util.AppLogger.i(TAG, "fillActiveReplyField: fallback tap at ($tapX, $tapY)")
    tapScreenPoint(tapX, tapY)
    delay(300)
    val focused = findFocusedInput()
    if (focused != null) {
      val res = setTextOnNode(focused.node, text)
      focused.node.recycle()
      ai.axiomaster.bonio.util.AppLogger.i(TAG, "fillActiveReplyField: focused text result=$res")
      return res
    }
    return false
  }

  private suspend fun tapScreenPoint(x: Float, y: Float): Boolean {
    val path = Path().apply {
      moveTo(x, y)
    }
    val gestureOk = CompletableDeferred<Boolean>()
    dispatchGesture(
      GestureDescription.Builder()
        .addStroke(GestureDescription.StrokeDescription(path, 0, 50))
        .build(),
      object : GestureResultCallback() {
        override fun onCompleted(gestureDescription: GestureDescription?) {
          gestureOk.complete(true)
        }
        override fun onCancelled(gestureDescription: GestureDescription?) {
          gestureOk.complete(false)
        }
      },
      null,
    )
    return try {
      withTimeout(600) { gestureOk.await() }
    } catch (_: Throwable) {
      false
    }
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
  fun dumpActiveWindow(maxNodes: Int = 250, maxTextLength: Int = 240): String? {
    val currentWindows = windows.sortedByDescending { it.layer }
    ai.axiomaster.bonio.util.AppLogger.i(TAG, "dumpActiveWindow: total windows=${currentWindows.size}")

    data class WindowCandidate(
      val window: AccessibilityWindowInfo?,
      val root: AccessibilityNodeInfo,
      val isFromActive: Boolean
    )
    val candidates = mutableListOf<WindowCandidate>()

    for (w in currentWindows) {
      if (w.type == AccessibilityWindowInfo.TYPE_APPLICATION) {
        val r = w.root
        if (r != null) {
          if (r.packageName?.toString() != packageName) {
            candidates.add(WindowCandidate(w, r, false))
          } else {
            r.recycle()
          }
        }
      }
    }
    rootInActiveWindow?.let { r ->
      if (r.packageName?.toString() != packageName) {
        candidates.add(WindowCandidate(null, r, true))
      } else {
        r.recycle()
      }
    }

    if (candidates.isEmpty()) {
      ai.axiomaster.bonio.util.AppLogger.w(TAG, "dumpActiveWindow: no external application root found")
      return null
    }

    for ((idx, c) in candidates.withIndex()) {
      ai.axiomaster.bonio.util.AppLogger.i(
        TAG,
        "dumpActiveWindow candidate #$idx: pkg=${c.root.packageName} class=${c.root.className} childCount=${c.root.childCount} title=${c.window?.title} isFocused=${c.window?.isFocused} isActive=${c.window?.isActive} isFromActive=${c.isFromActive}"
      )
    }

    // Pick candidate: prefer childCount > 0 or has text, otherwise first candidate
    val chosen = candidates.firstOrNull { it.root.childCount > 0 || !it.root.text.isNullOrEmpty() }
      ?: candidates.first()

    val matchedWindow = chosen.window
    val root = chosen.root

    for (c in candidates) {
      if (c.root !== root) {
        c.root.recycle()
      }
    }

    ai.axiomaster.bonio.util.AppLogger.i(
      TAG,
      "dumpActiveWindow chosen: pkg=${root.packageName} windowTitle=${matchedWindow?.title} childCount=${root.childCount}"
    )

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
      ai.axiomaster.bonio.util.AppLogger.i(TAG, "dumpActiveWindow collected nodes=${nodes.length()}")
      return JSONObject()
        .put("package", root.packageName?.toString().orEmpty())
        .put("window_title", matchedWindow?.title?.toString().orEmpty())
        .put("recent_events", JSONArray(synchronized(recentEventText) { recentEventText.toList() }))
        .put("nodes", nodes)
        .toString()
    } finally {
      while (queue.isNotEmpty()) queue.removeFirst().first.recycle()
      root.recycle()
    }
  }

  private fun externalApplicationRoot(): AccessibilityNodeInfo? {
    val candidates = mutableListOf<AccessibilityNodeInfo>()
    for (candidate in windows.sortedByDescending { it.layer }) {
      if (candidate.type == AccessibilityWindowInfo.TYPE_APPLICATION) {
        val r = candidate.root
        if (r != null) {
          if (r.packageName?.toString() != packageName) {
            candidates.add(r)
          } else {
            r.recycle()
          }
        }
      }
    }
    rootInActiveWindow?.let { r ->
      if (r.packageName?.toString() != packageName) {
        candidates.add(r)
      } else {
        r.recycle()
      }
    }
    val chosen = candidates.firstOrNull { it.childCount > 0 || it.isEditable } ?: candidates.firstOrNull()
    for (c in candidates) {
      if (c !== chosen) c.recycle()
    }
    return chosen
  }

  private fun applicationRoot(targetPackage: String): AccessibilityNodeInfo? {
    return windows
      .sortedByDescending { it.layer }
      .firstNotNullOfOrNull { candidate ->
        if (candidate.type != AccessibilityWindowInfo.TYPE_APPLICATION) return@firstNotNullOfOrNull null
        candidate.root?.takeIf { it.packageName?.toString() == targetPackage }
      }
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

  /**
   * Captures a screenshot of the current default display silently via accessibility API.
   * Requires android:canTakeScreenshot="true" in service XML.
   */
  suspend fun takeScreenshotBitmap(): Bitmap? = withTimeoutOrNull(4000) {
    val deferred = CompletableDeferred<Bitmap?>()
    try {
      takeScreenshot(
        Display.DEFAULT_DISPLAY,
        mainExecutor,
        object : TakeScreenshotCallback {
          override fun onSuccess(screenshot: ScreenshotResult) {
            val hwBuffer = screenshot.hardwareBuffer
            val colorSpace = screenshot.colorSpace
            try {
              val hwBitmap = Bitmap.wrapHardwareBuffer(hwBuffer, colorSpace)
              val softBitmap = hwBitmap?.copy(Bitmap.Config.ARGB_8888, false)
              hwBitmap?.recycle()
              deferred.complete(softBitmap)
            } catch (e: Throwable) {
              Log.w(TAG, "Failed to copy screenshot bitmap: ${e.message}", e)
              deferred.complete(null)
            } finally {
              hwBuffer.close()
            }
          }

          override fun onFailure(errorCode: Int) {
            Log.w(TAG, "takeScreenshot onFailure errorCode=$errorCode")
            deferred.complete(null)
          }
        }
      )
    } catch (e: Throwable) {
      Log.w(TAG, "takeScreenshot exception: ${e.message}", e)
      deferred.complete(null)
    }
    deferred.await()
  }

  /**
   * Captures screen and returns scaled JPEG Base64 string.
   */
  suspend fun takeScreenshotBase64(maxEdge: Int = 1080, quality: Int = 80): String? {
    val bitmap = takeScreenshotBitmap() ?: return null
    return try {
      val width = bitmap.width
      val height = bitmap.height
      val longest = maxOf(width, height)
      val scaledBitmap = if (longest > maxEdge) {
        val scale = maxEdge.toFloat() / longest
        val newW = (width * scale).toInt().coerceAtLeast(1)
        val newH = (height * scale).toInt().coerceAtLeast(1)
        Bitmap.createScaledBitmap(bitmap, newW, newH, true)
      } else {
        bitmap
      }
      val out = ByteArrayOutputStream()
      scaledBitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), out)
      if (scaledBitmap != bitmap) {
        scaledBitmap.recycle()
      }
      Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    } catch (e: Throwable) {
      Log.e(TAG, "Failed to compress screenshot: ${e.message}", e)
      null
    } finally {
      bitmap.recycle()
    }
  }

  data class InputFieldInfo(val node: AccessibilityNodeInfo, val bounds: Rect)

  companion object {
    private const val TAG = "BonioA11y"

    @Volatile var instance: BonioAccessibilityService? = null
      private set

    val isEnabled: Boolean
      get() = instance != null
  }
}
