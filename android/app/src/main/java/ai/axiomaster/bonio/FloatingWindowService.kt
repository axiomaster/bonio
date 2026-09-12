package ai.axiomaster.bonio

import ai.axiomaster.bonio.ai.AgentManager
import ai.axiomaster.bonio.ai.AgentState
import ai.axiomaster.bonio.avatar.AvatarController
import ai.axiomaster.bonio.avatar.AvatarState
import ai.axiomaster.bonio.avatar.CloneManager
import ai.axiomaster.bonio.avatar.MotionState
import ai.axiomaster.bonio.avatar.ThemeManager
import ai.axiomaster.bonio.avatar.ActionEventWatcher
import ai.axiomaster.bonio.remote.chat.SpeechToTextManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.PorterDuff
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.util.Log
import android.view.ViewGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.LinearLayout
import androidx.cardview.widget.CardView
import androidx.core.content.ContextCompat
import com.airbnb.lottie.LottieAnimationView
import com.airbnb.lottie.LottieDrawable
import ai.axiomaster.bonio.remote.chat.OutgoingAttachment
import ai.axiomaster.bonio.remote.cue.MagicCue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

class FloatingWindowService : Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var floatingView: View
    private lateinit var layoutParams: WindowManager.LayoutParams

    private lateinit var pixelAvatarView: ai.axiomaster.bonio.avatar.PixelAvatarView
    private lateinit var bubbleContainer: CardView
    private lateinit var bubbleLabel: TextView
    private lateinit var textBubble: TextView
    private lateinit var textBubbleScroll: ScrollView
    private lateinit var floatingRoot: LinearLayout

    private val avatarController: AvatarController get() = AgentManager.avatarController
    private val stateManager get() = AgentManager.stateManager
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var themeManager: ThemeManager
    private var actionEventWatcher: ActionEventWatcher? = null

    private var sttManager: SpeechToTextManager? = null
    private var callTtsManager: ai.axiomaster.bonio.remote.chat.SystemTtsManager? = null
    private var isVoiceActive = false
    private var voiceSessionId = 0
    private var screenSuggestionPending = false
    private var actionableSuggestion: String? = null
    private var magicCuePending = false
    private var actionableCues: List<ai.axiomaster.bonio.remote.cue.MagicCue> = emptyList()
    private var cueEpoch = 0
    private var pendingAccessibilityPrompt = false

    private fun openAccessibilitySettings() {
        pendingAccessibilityPrompt = false
        avatarController.clearBubble()
        avatarController.setActivity(AgentState.Idle)
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            android.widget.Toast.makeText(
                applicationContext,
                "请在已安装的应用中找到 Bonio 并开启无障碍服务",
                android.widget.Toast.LENGTH_LONG
            ).show()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open accessibility settings", e)
        }
    }

    private var currentAssetPath: String? = null
    private var isPlayingTransition = false

    override fun onBind(intent: Intent?): IBinder? = null

    private var isViewAttached = false

    private var cloneView: View? = null
    private var cloneLayoutParams: WindowManager.LayoutParams? = null
    private var cloneLottie: LottieAnimationView? = null
    private var isCloneAttached = false
    private var cloneReceiver: BroadcastReceiver? = null

    /** When true, [observeAvatarState] does not auto-hide the clone when leaving [AgentState.Working] (smart-reader flow). */
    private var suppressCloneHideForSmartReader = false

    private val prefs by lazy {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val jsonLenient = Json { ignoreUnknownKeys = true }

    override fun onCreate() {
        Log.d(TAG, "FloatingWindowService onCreate")
        super.onCreate()

        themeManager = ThemeManager(applicationContext)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "bonio_agent_channel"
            val channel = android.app.NotificationChannel(
                channelId,
                "Agent Service",
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager?.createNotificationChannel(channel)

            val notification = android.app.Notification.Builder(this, channelId)
                .setContentTitle("Bonio Agent")
                .setContentText("Agent is running in the background")
                .setSmallIcon(R.mipmap.ic_launcher)
                .build()

            if (Build.VERSION.SDK_INT >= 34) {
                val hasMic = ContextCompat.checkSelfPermission(
                    this, android.Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
                val serviceType = if (hasMic) {
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                } else {
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                }
                startForeground(101, notification, serviceType)
            } else {
                startForeground(101, notification)
            }
        }

        sttManager = SpeechToTextManager(applicationContext)
        sttManager?.warmUp()

        callTtsManager = ai.axiomaster.bonio.remote.chat.SystemTtsManager(applicationContext)
        val runtime = (application as BonioApp).runtime
        runtime.callEventHandler.ttsManager = callTtsManager
        runtime.callEventHandler.sttManager = sttManager
        runtime.callStateMonitor.start()
        runtime.avatarCommandExecutor.ttsManager = callTtsManager
        runtime.floatingWindowIntentHandler = { payload -> handleIntentExecute(payload) }
        runtime.chat.onAssistantReply = { text ->
            if (screenSuggestionPending) {
                screenSuggestionPending = false
                actionableSuggestion = text.trim()
                mainHandler.post {
                    avatarController.setActivity(AgentState.Speaking)
                    avatarController.setBubble(text, SUGGESTION_BG_COLOR, android.graphics.Color.WHITE)
                    mainHandler.postDelayed({
                        if (stateManager.currentState.value == AgentState.Speaking) {
                            avatarController.clearBubble()
                            avatarController.setActivity(AgentState.Idle)
                        }
                    }, SUGGESTION_DISPLAY_MS)
                }
            }
        }

        avatarController.updateScreenMetrics(resources.displayMetrics)

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        floatingView = LayoutInflater.from(this).inflate(R.layout.floating_agent_layout, null)
        floatingRoot = floatingView.findViewById(R.id.floating_root)

        pixelAvatarView = floatingView.findViewById(R.id.pixel_avatar)
        val avatarPrefs = getSharedPreferences("bonio_avatar", Context.MODE_PRIVATE)
        val initSkin = avatarPrefs.getString("avatar_skin", "cat") ?: "cat"
        pixelAvatarView.setSkin(initSkin)
        bubbleContainer = floatingView.findViewById(R.id.bubble_container)
        bubbleLabel = floatingView.findViewById(R.id.bubble_label)
        textBubble = floatingView.findViewById(R.id.text_bubble)
        textBubbleScroll = floatingView.findViewById(R.id.text_bubble_scroll)
        bubbleContainer.setOnClickListener {
            if (pendingAccessibilityPrompt) {
                openAccessibilitySettings()
            } else if (actionableCues.isNotEmpty()) {
                applyMagicCue()
            } else {
                sendActionableSuggestion()
            }
        }

        val savedX = prefs.getInt(KEY_POS_X, 0)
        val savedY = prefs.getInt(KEY_POS_Y, 100)
        avatarController.setPosition(savedX.toFloat(), savedY.toFloat())

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = savedX
            y = savedY
        }

        setupTouchListener()
        observeAvatarState()

        avatarController.onTransition = { transition ->
            mainHandler.post { playTransitionThenLoop(transition) }
        }

        // Start watching for on-device phone-use-agent action events
        actionEventWatcher = ActionEventWatcher(avatarController, serviceScope)
        actionEventWatcher?.start()

        // Observe overlay visibility preference
        serviceScope.launch {
            val prefs = applicationContext.getSharedPreferences("bonio_avatar", Context.MODE_PRIVATE)
            while (true) {
                val shouldShow = prefs.getBoolean("show_overlay", true)
                val targetVisibility = if (shouldShow) View.VISIBLE else View.GONE
                if (floatingView.visibility != targetVisibility) {
                    floatingView.visibility = targetVisibility
                }
                kotlinx.coroutines.delay(1000)
            }
        }

        try {
            Log.d(TAG, "FloatingWindowService - adding view to WindowManager")
            windowManager.addView(floatingView, layoutParams)
            isViewAttached = true
            Log.d(TAG, "FloatingWindowService - view attached successfully")
        } catch (e: Exception) {
            Log.e(TAG, "FloatingWindowService - failed to add view", e)
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    CloneManager.ACTION_SHOW_CLONE -> {
                        val asset = intent.getStringExtra(CloneManager.EXTRA_ANIMATION_ASSET)
                        showClone(asset)
                    }
                    CloneManager.ACTION_HIDE_CLONE -> hideClone()
                    ACTION_TRIGGER_CUE -> runMagicCue()
                    ACTION_APPLY_CUE -> {
                        val extraText = intent.getStringExtra("text") ?: intent.getStringExtra("content")
                        if (!extraText.isNullOrEmpty()) {
                            applyMagicCue(MagicCue(title = "快捷回复", content = extraText, kind = "reply"))
                        } else {
                            applyMagicCue()
                        }
                    }
                }
            }
        }
        cloneReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(CloneManager.ACTION_SHOW_CLONE)
            addAction(CloneManager.ACTION_HIDE_CLONE)
            addAction(ACTION_TRIGGER_CUE)
            addAction(ACTION_APPLY_CUE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
    }

    private fun savePosition() {
        prefs.edit()
            .putInt(KEY_POS_X, layoutParams.x)
            .putInt(KEY_POS_Y, layoutParams.y)
            .apply()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "FloatingWindowService onStartCommand")
        if (!isViewAttached) {
            try {
                windowManager.addView(floatingView, layoutParams)
                isViewAttached = true
            } catch (e: Exception) {
                Log.e(TAG, "FloatingWindowService - re-attempt add view failed", e)
            }
        }
        return START_STICKY
    }

    private fun observeAvatarState() {
        // Load themes once at startup
        serviceScope.launch {
            themeManager.refreshThemes()
        }

        // Observe composite avatar state for animation + position
        serviceScope.launch {
            avatarController.avatarState.collect { state: AvatarState ->
                updateAnimation(state)
                updatePosition(state)
                updateBubbleForActivity(state)
                if (state.activity == AgentState.Working) {
                    showClone()
                } else if (isCloneAttached && !suppressCloneHideForSmartReader) {
                    hideClone()
                }
            }
        }

        serviceScope.launch {
            stateManager.bubbleColor.collect { color ->
                bubbleContainer.setCardBackgroundColor(color)
            }
        }
        serviceScope.launch {
            stateManager.bubbleTextColor.collect { color ->
                textBubble.setTextColor(color)
                bubbleLabel.setTextColor(color)
            }
        }

        serviceScope.launch {
            stateManager.bubbleCountdownLabel.collect {
                updateBubbleForActivity(avatarController.avatarState.value)
            }
        }

        // Observe skin changes from preferences
        serviceScope.launch {
            val avatarPrefs = applicationContext.getSharedPreferences("bonio_avatar", Context.MODE_PRIVATE)
            while (true) {
                val skin = avatarPrefs.getString("avatar_skin", "cat") ?: "cat"
                if (pixelAvatarView.getSkin() != skin) {
                    pixelAvatarView.setSkin(skin)
                }
                delay(500)
            }
        }

        // Observe text bubble
        val bubbleMaxHeightPx = (52 * resources.displayMetrics.density).toInt()
        serviceScope.launch {
            stateManager.currentTextBubble.collect { text: String? ->
                if (text.isNullOrEmpty()) {
                    if (bubbleLabel.visibility != View.VISIBLE) {
                        hideBubbleAnimated()
                    }
                    textBubbleScroll.visibility = View.GONE
                    textBubbleScroll.layoutParams = textBubbleScroll.layoutParams.apply {
                        height = ViewGroup.LayoutParams.WRAP_CONTENT
                    }
                } else {
                    textBubble.text = text
                    textBubbleScroll.visibility = View.VISIBLE
                    showBubbleAnimated()
                    textBubble.post {
                        val lp = textBubbleScroll.layoutParams
                        if (textBubble.height > bubbleMaxHeightPx) {
                            lp.height = bubbleMaxHeightPx
                        } else {
                            lp.height = ViewGroup.LayoutParams.WRAP_CONTENT
                        }
                        textBubbleScroll.layoutParams = lp
                        textBubbleScroll.fullScroll(View.FOCUS_DOWN)
                    }
                }
            }
        }

        // Observe streaming assistant text
        val chatController = (application as BonioApp).runtime.chat
        serviceScope.launch {
            chatController.streamingAssistantText.collect { text: String? ->
                if (!text.isNullOrEmpty()) {
                    stateManager.setBubble(text)
                }
            }
        }
    }

    private fun updateAnimation(state: AvatarState) {
        val visual = when (state.activity) {
            AgentState.Working -> "working"
            AgentState.Thinking, AgentState.Confused -> "thinking"
            AgentState.Listening -> "waiting"
            AgentState.Speaking -> "wave"
            AgentState.Happy -> "completed"
            AgentState.Bored, AgentState.Sleeping, AgentState.Idle -> "idle"
            else -> "idle"
        }
        pixelAvatarView.setVisualState(visual)
    }

    private fun playTransitionThenLoop(transition: ai.axiomaster.bonio.avatar.AvatarTransition) {
        pixelAvatarView.setVisualState("wave")
        mainHandler.postDelayed({
            avatarController.clearTransition()
            updateAnimation(avatarController.avatarState.value)
        }, 1200)
    }

    private fun updatePosition(state: AvatarState) {
        val newX = state.position.x.toInt()
        val newY = state.position.y.toInt()
        if (layoutParams.x != newX || layoutParams.y != newY) {
            layoutParams.x = newX
            layoutParams.y = newY
            if (isViewAttached) {
                try {
                    windowManager.updateViewLayout(floatingView, layoutParams)
                } catch (e: Exception) {
                    Log.w(TAG, "updateViewLayout failed", e)
                }
            }
        }
    }

    private fun bubbleLabelTextForActivity(state: AvatarState): String? {
        stateManager.bubbleCountdownLabel.value?.let { return it }
        val stateName = when (state.activity) {
            AgentState.Working -> "working"
            AgentState.Thinking, AgentState.Confused -> "thinking"
            AgentState.Listening -> "waiting"
            AgentState.Happy -> "completed"
            AgentState.Sleeping, AgentState.Idle -> "idle"
            else -> null
        } ?: return null
        return ai.axiomaster.bonio.avatar.CustomSkinManager.getAgentBubble(stateName, pixelAvatarView.getSkin())
    }

    private fun updateBubbleForActivity(state: AvatarState) {
        val labelText = bubbleLabelTextForActivity(state)
        if (labelText != null) {
            bubbleLabel.text = labelText
            bubbleLabel.visibility = View.VISIBLE
            showBubbleAnimated()
        } else {
            bubbleLabel.visibility = View.GONE
            if (textBubbleScroll.visibility != View.VISIBLE) {
                hideBubbleAnimated()
            }
        }
    }

    private fun showBubbleAnimated() {
        positionBubbleBesideAvatar()
        bubbleContainer.animate().cancel()
        if (bubbleContainer.visibility == View.VISIBLE &&
            bubbleContainer.alpha == 1f &&
            bubbleContainer.scaleX == 1f &&
            bubbleContainer.scaleY == 1f
        ) {
            return
        }
        bubbleContainer.visibility = View.VISIBLE
        bubbleContainer.alpha = 0f
        bubbleContainer.scaleX = 0.6f
        bubbleContainer.scaleY = 0.6f
        bubbleContainer.animate()
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(250)
            .setInterpolator(OvershootInterpolator(1.5f))
            .start()
    }

    private fun positionBubbleBesideAvatar() {
        // Bubble is positioned directly above pixel avatar in vertical root
    }

    private fun hideBubbleAnimated() {
        bubbleContainer.animate().cancel()
        if (bubbleContainer.visibility != View.VISIBLE) return
        bubbleContainer.animate()
            .alpha(0f)
            .scaleX(0.6f)
            .scaleY(0.6f)
            .setDuration(200)
            .setInterpolator(AccelerateInterpolator())
            .withEndAction {
                bubbleContainer.visibility = View.GONE
                bubbleContainer.alpha = 1f
                bubbleContainer.scaleX = 1f
                bubbleContainer.scaleY = 1f
            }
            .start()
    }

    private fun setupTouchListener() {
        val density = resources.displayMetrics.density
        val dragThresholdPx = (DRAG_THRESHOLD_DP * density).toInt()
        Log.d(TAG, "setupTouchListener: dragThresholdPx=$dragThresholdPx density=$density")

        pixelAvatarView.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isDragging = false
            private var longPressTriggered = false
            private var lastTapAt = 0L

            private val longPressRunnable = Runnable {
                if (!isDragging) {
                    longPressTriggered = true
                    Log.d(TAG, "Long press detected -> analyzing current screen")
                    analyzeCurrentScreen()
                }
            }

            override fun onTouch(v: View?, event: MotionEvent?): Boolean {
                if (event == null) return false

                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams.x
                        initialY = layoutParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isDragging = false
                        longPressTriggered = false
                        mainHandler.postDelayed(longPressRunnable, LONG_PRESS_THRESHOLD_MS)
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (!isDragging && (Math.abs(dx) > dragThresholdPx || Math.abs(dy) > dragThresholdPx)) {
                            isDragging = true
                            mainHandler.removeCallbacks(longPressRunnable)
                            if (longPressTriggered) {
                                cancelVoiceInputFromFloating()
                                longPressTriggered = false
                            }
                        }
                        if (isDragging) {
                            if (dx < -10) {
                                pixelAvatarView.setVisualState("dragLeft")
                            } else if (dx > 10) {
                                pixelAvatarView.setVisualState("dragRight")
                            }
                            val newX = initialX + dx
                            val newY = initialY + dy
                            avatarController.dragTo(newX, newY)
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        mainHandler.removeCallbacks(longPressRunnable)
                        if (longPressTriggered) {
                            longPressTriggered = false
                        } else if (isDragging) {
                            avatarController.endDrag()
                            savePosition()
                            updateAnimation(avatarController.avatarState.value)
                        } else {
                            v?.performClick()
                            val now = android.os.SystemClock.uptimeMillis()
                            if (now - lastTapAt <= DOUBLE_TAP_THRESHOLD_MS) {
                                lastTapAt = 0L
                                runMagicCue()
                            } else {
                                lastTapAt = now
                                if (pendingAccessibilityPrompt) {
                                    openAccessibilitySettings()
                                } else {
                                    pixelAvatarView.setVisualState("wave")
                                    val skin = pixelAvatarView.getSkin()
                                    val greeting = when (skin) {
                                        "kun" -> "你干嘛~哎哟"
                                        "mario" -> "Here we go!"
                                        "messi" -> "Vamos!"
                                        else -> "喵~ 休息中~ 有事叫我"
                                    }
                                    avatarController.setBubble(greeting)
                                    mainHandler.postDelayed({
                                        avatarController.clearBubble()
                                        updateAnimation(avatarController.avatarState.value)
                                    }, 2400)
                                }
                            }
                        }
                        return true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        mainHandler.removeCallbacks(longPressRunnable)
                        if (longPressTriggered) {
                            longPressTriggered = false
                        } else if (isDragging) {
                            avatarController.endDrag()
                            updateAnimation(avatarController.avatarState.value)
                        }
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun analyzeCurrentScreen() {
        if (screenSuggestionPending) return
        avatarController.clearBubble()
        actionableSuggestion = null
        avatarController.setActivity(AgentState.Thinking)
        avatarController.setBubble("正在理解当前屏幕…")
        serviceScope.launch {
            try {
                val uiTree = withContext(Dispatchers.Default) {
                    ai.axiomaster.bonio.remote.node.BonioAccessibilityService.instance?.dumpActiveWindow()
                }
                if (uiTree == null) {
                    throw IllegalStateException("请先在系统设置中启用 Bonio 无障碍服务")
                }
                val suggestion = withContext(Dispatchers.Default) {
                    ai.axiomaster.bonio.remote.node.ScreenSuggestionRules.match(uiTree)
                }
                if (suggestion == null) {
                    avatarController.setActivity(AgentState.Confused)
                    avatarController.setBubble("暂时没有匹配的建议")
                    delay(2500)
                    avatarController.clearBubble()
                    avatarController.setActivity(AgentState.Idle)
                    return@launch
                }
                actionableSuggestion = suggestion
                avatarController.setActivity(AgentState.Speaking)
                avatarController.setBubble(suggestion, SUGGESTION_BG_COLOR, android.graphics.Color.WHITE)
                delay(SUGGESTION_DISPLAY_MS)
                if (actionableSuggestion == suggestion) {
                    actionableSuggestion = null
                    avatarController.clearBubble()
                    avatarController.setActivity(AgentState.Idle)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Screen context analysis failed", e)
                avatarController.setActivity(AgentState.Confused)
                avatarController.setBubble(e.message ?: "屏幕分析失败")
                delay(2500)
                avatarController.clearBubble()
                avatarController.setActivity(AgentState.Idle)
            }
        }
    }

    private fun sendActionableSuggestion() {
        val suggestion = actionableSuggestion?.takeIf { it.isNotBlank() } ?: return
        actionableSuggestion = null
        avatarController.setActivity(AgentState.Working)
        avatarController.setBubble("正在发送…")
        serviceScope.launch {
            val accessibility = ai.axiomaster.bonio.remote.node.BonioAccessibilityService.instance
            val filled = accessibility?.fillActiveReplyField(suggestion) == true
            if (filled) {
                avatarController.setActivity(AgentState.Happy)
                avatarController.setBubble("已写入回复框")
            } else {
                actionableSuggestion = suggestion
                avatarController.setActivity(AgentState.Confused)
                avatarController.setBubble("未找到回复框，点此重试")
            }
            delay(1800)
            avatarController.clearBubble()
            avatarController.setActivity(AgentState.Idle)
        }
    }

    // ── Magic Cue (double-tap): screen text → LLM suggestions → capsule ──

    private fun runMagicCue() {
        if (magicCuePending) return
        val runtime = (application as BonioApp).runtime
        if (!runtime.isConnected.value) {
            avatarController.setActivity(AgentState.Confused)
            avatarController.setBubble("后端未连接")
            mainHandler.postDelayed({ avatarController.clearBubble(); avatarController.setActivity(AgentState.Idle) }, 2000)
            return
        }

        val a11y = ai.axiomaster.bonio.remote.node.BonioAccessibilityService.instance
        if (a11y == null) {
            avatarController.setActivity(AgentState.Confused)
            avatarController.setBubble("未开启无障碍服务\n点我前往系统设置")
            pendingAccessibilityPrompt = true
            mainHandler.postDelayed({
                if (pendingAccessibilityPrompt) {
                    pendingAccessibilityPrompt = false
                    avatarController.clearBubble()
                    avatarController.setActivity(AgentState.Idle)
                }
            }, 6000)
            return
        }

        magicCuePending = true
        actionableCues = emptyList()
        cueEpoch += 1
        avatarController.clearBubble()

        serviceScope.launch {
            try {
                // Briefly hide the floating avatar so the captured screenshot does not have the overlay blocking content
                var screenshotBase64: String? = null
                val ctxRes = try {
                    val prevVis = floatingView.visibility
                    floatingView.visibility = View.INVISIBLE
                    delay(50)
                    kotlinx.coroutines.coroutineScope {
                        val screenshotDef = async(Dispatchers.Default) {
                            runtime.captureScreenshot(maxEdge = 1080, quality = 80)
                        }
                        val textDef = async(Dispatchers.Default) {
                            runtime.captureScreenContext(6000)
                        }
                        screenshotBase64 = screenshotDef.await()
                        textDef.await()
                    }
                } finally {
                    floatingView.visibility = View.VISIBLE
                    avatarController.setActivity(AgentState.Thinking)
                    avatarController.setBubble("正在分析屏幕…")
                }

                if (!ctxRes.ok || ctxRes.payloadJson == null) {
                    throw IllegalStateException(ctxRes.error?.message ?: "无法读取屏幕内容")
                }
                val obj = withContext(Dispatchers.Default) { org.json.JSONObject(ctxRes.payloadJson) }
                val screen = ai.axiomaster.bonio.remote.cue.MagicCueController.ScreenContext(
                    packageName = obj.optString("package"),
                    title = obj.optString("title"),
                    content = obj.optString("content"),
                    rawJson = ctxRes.payloadJson,
                )
                var cues: List<ai.axiomaster.bonio.remote.cue.MagicCue>? = null
                var remembered = false
                kotlinx.coroutines.coroutineScope {
                    launch { cues = withContext(Dispatchers.Default) { runtime.magicCue.runCue(screen) } }
                    launch {
                        remembered = withContext(Dispatchers.Default) {
                            runtime.companionMemory.capture(
                                screen = screen,
                                explicit = true,
                                coverImage = screenshotBase64,
                                originalImage = screenshotBase64,
                            )
                        }
                    }
                }
                magicCuePending = false
                ai.axiomaster.bonio.util.AppLogger.i(TAG, "runMagicCue completed: cues=${cues?.size} remembered=$remembered hasScreenshot=${!screenshotBase64.isNullOrEmpty()}")
                when {
                    !cues.isNullOrEmpty() -> showCues(cues!!)
                    remembered -> {
                        cueEpoch += 1
                        val epoch = cueEpoch
                        avatarController.setActivity(AgentState.Happy)
                        avatarController.setBubble("已记住 ✅", SUGGESTION_BG_COLOR, android.graphics.Color.WHITE)
                        mainHandler.postDelayed({
                            if (cueEpoch == epoch) {
                                avatarController.clearBubble()
                                avatarController.setActivity(AgentState.Idle)
                            }
                        }, 2000)
                    }
                    cues != null -> showCueFailure("当前页面没有什么可以帮你")
                    else -> showCueFailure("屏幕分析失败，请稍后再试")
                }
            } catch (e: Throwable) {
                magicCuePending = false
                Log.e(TAG, "Magic cue failed", e)
                showCueFailure(e.message ?: "屏幕分析失败，请稍后再试")
            }
        }
    }

    private fun showCues(cues: List<ai.axiomaster.bonio.remote.cue.MagicCue>) {
        actionableCues = cues
        cueEpoch += 1
        val epoch = cueEpoch
        val first = cues.first()
        val prompt = if (cues.size > 1) {
            "有 ${cues.size} 条建议，点我发送"
        } else if (first.title.isNotEmpty() && first.title != first.content) {
            "${first.title}\n${first.content}"
        } else {
            first.content
        }
        avatarController.setActivity(AgentState.Speaking)
        avatarController.setBubble(prompt, SUGGESTION_BG_COLOR, android.graphics.Color.WHITE)
        mainHandler.postDelayed({
            if (cueEpoch == epoch) {
                actionableCues = emptyList()
                avatarController.clearBubble()
                avatarController.setActivity(AgentState.Idle)
            }
        }, SUGGESTION_DISPLAY_MS)
    }

    private fun showCueFailure(message: String) {
        avatarController.setActivity(AgentState.Confused)
        avatarController.setBubble(message)
        mainHandler.postDelayed({ avatarController.clearBubble(); avatarController.setActivity(AgentState.Idle) }, 2500)
    }

    private fun applyMagicCue(customCue: MagicCue? = null) {
        val cue = customCue ?: actionableCues.firstOrNull() ?: return
        cueEpoch += 1
        actionableCues = emptyList()
        avatarController.setActivity(AgentState.Working)
        avatarController.setBubble("正在发送…")
        serviceScope.launch {
            if (cue.kind == "calendar") {
                openCalendarApp()
                avatarController.setActivity(AgentState.Happy)
                avatarController.setBubble("已打开日历")
                delay(1500)
            } else {
                val accessibility = ai.axiomaster.bonio.remote.node.BonioAccessibilityService.instance
                // Try sending directly (silent text injection + dynamic send button click)
                val sent = accessibility?.sendTextToActiveChat(cue.content) == true
                if (sent) {
                    avatarController.setActivity(AgentState.Happy)
                    avatarController.setBubble("已发送 ✅")
                } else {
                    // Fallback to fill active reply field if send button wasn't found
                    val filled = accessibility?.fillActiveReplyField(cue.content) == true
                    if (filled) {
                        avatarController.setActivity(AgentState.Happy)
                        avatarController.setBubble("已填入回复框")
                    } else {
                        avatarController.setActivity(AgentState.Confused)
                        avatarController.setBubble("未找到回复框，点此重试")
                    }
                }
                delay(1800)
            }
            avatarController.clearBubble()
            avatarController.setActivity(AgentState.Idle)
        }
    }

    private fun openCalendarApp() {
        try {
            val launch = packageManager.getLaunchIntentForPackage("com.google.android.calendar")
                ?: packageManager.getLaunchIntentForPackage("com.samsung.android.calendar")
                ?: packageManager.getLaunchIntentForPackage("com.android.calendar")
            if (launch != null) {
                launch.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launch)
                return
            }
            val view = android.content.Intent(android.content.Intent.ACTION_VIEW)
                .setData(android.provider.CalendarContract.CONTENT_URI.buildUpon().appendPath("time").build())
            view.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(view)
        } catch (e: Throwable) {
            Log.w(TAG, "open calendar failed", e)
        }
    }

    private fun startVoiceInputFromFloating() {
        val currentState = stateManager.currentState.value
        if (currentState == AgentState.Bored || currentState == AgentState.Sleeping) {
            avatarController.setActivity(AgentState.Idle)
        } else if (currentState != AgentState.Idle) {
            Log.d(TAG, "Cannot start voice input, agent state is $currentState")
            return
        }

        val hasMic = ContextCompat.checkSelfPermission(
            this, android.Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasMic) {
            Log.w(TAG, "RECORD_AUDIO permission not granted, bringing app to front")
            bringAppToFront()
            return
        }

        Log.d(TAG, "Starting voice input from floating window")
        val mySession = ++voiceSessionId
        isVoiceActive = true
        avatarController.setActivity(AgentState.Listening)

        sttManager?.startListening(object : SpeechToTextManager.Listener {
            override fun onPartialResult(text: String) {
                if (voiceSessionId != mySession) return
                avatarController.setBubble(text)
            }

            override fun onFinalResult(text: String) {
                if (voiceSessionId != mySession) {
                    Log.d(TAG, "STT onFinalResult ignored (session $mySession stale, current $voiceSessionId)")
                    return
                }
                Log.d(TAG, "STT final result from floating: $text")
                isVoiceActive = false
                avatarController.clearBubble()
                avatarController.setActivity(AgentState.Thinking)

                val runtime = (application as BonioApp).runtime
                sendSttResultToServer(text, runtime)
            }

            override fun onError(errorCode: Int) {
                if (voiceSessionId != mySession) return
                Log.w(TAG, "STT error from floating: $errorCode")
                isVoiceActive = false
                avatarController.clearBubble()
                avatarController.setActivity(AgentState.Idle)
            }

            override fun onReadyForSpeech() {
                if (voiceSessionId != mySession) return
                Log.d(TAG, "STT ready for speech from floating")
            }

            override fun onEndOfSpeech() {
                if (voiceSessionId != mySession) return
                Log.d(TAG, "STT end of speech from floating")
                if (isVoiceActive) {
                    isVoiceActive = false
                    avatarController.clearBubble()
                    avatarController.setActivity(AgentState.Idle)
                }
            }
        })
    }

    private fun stopVoiceInputFromFloating() {
        if (isVoiceActive) {
            Log.d(TAG, "Stopping voice input from floating window")
            val mySession = voiceSessionId
            sttManager?.stopListening()
            mainHandler.postDelayed({
                if (isVoiceActive && voiceSessionId == mySession) {
                    Log.w(TAG, "STT stop safety timeout — forcing state reset")
                    isVoiceActive = false
                    avatarController.clearBubble()
                    avatarController.setActivity(AgentState.Idle)
                }
            }, 1500L)
        }
    }

    private fun cancelVoiceInputFromFloating() {
        if (isVoiceActive) {
            Log.d(TAG, "Cancelling voice input from floating window")
            voiceSessionId++
            sttManager?.cancelListening()
            isVoiceActive = false
            avatarController.setActivity(AgentState.Idle)
        }
    }

    private fun handleAgentClick() {
        val currentState = stateManager.currentState.value
        when (currentState) {
            AgentState.Speaking, AgentState.Working -> {
                Log.d(TAG, "Tap during $currentState -> interrupting, entering Listening")
                callTtsManager?.stop()
                val runtime = (application as BonioApp).runtime
                runtime.chat.stopStreaming()
                forceStartVoiceInput()
            }
            AgentState.Listening -> {
                Log.d(TAG, "Tap during Listening -> stopping voice input")
                stopVoiceInputFromFloating()
            }
            AgentState.Thinking -> {
                bringAppToFront()
            }
            else -> {
                bringAppToFront()
            }
        }
    }

    private fun forceStartVoiceInput() {
        val hasMic = ContextCompat.checkSelfPermission(
            this, android.Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasMic) {
            Log.w(TAG, "RECORD_AUDIO permission not granted, bringing app to front")
            bringAppToFront()
            return
        }

        Log.d(TAG, "Force starting voice input (interrupting current state)")
        if (isVoiceActive) {
            sttManager?.cancelListening()
        }
        val mySession = ++voiceSessionId
        isVoiceActive = true
        avatarController.setActivity(AgentState.Listening)

        sttManager?.startListening(object : SpeechToTextManager.Listener {
            override fun onPartialResult(text: String) {
                if (voiceSessionId != mySession) return
                avatarController.setBubble(text)
            }

            override fun onFinalResult(text: String) {
                if (voiceSessionId != mySession) {
                    Log.d(TAG, "STT onFinalResult ignored (session $mySession stale)")
                    return
                }
                Log.d(TAG, "STT final result (interrupt): $text")
                isVoiceActive = false
                avatarController.clearBubble()
                avatarController.setActivity(AgentState.Thinking)

                val runtime = (application as BonioApp).runtime
                sendSttResultToServer(text, runtime)
            }

            override fun onError(errorCode: Int) {
                if (voiceSessionId != mySession) return
                Log.w(TAG, "STT error (interrupt): $errorCode")
                isVoiceActive = false
                avatarController.clearBubble()
                avatarController.setActivity(AgentState.Idle)
            }

            override fun onReadyForSpeech() {}

            override fun onEndOfSpeech() {
                if (voiceSessionId != mySession) return
                if (isVoiceActive) {
                    isVoiceActive = false
                    avatarController.clearBubble()
                    avatarController.setActivity(AgentState.Idle)
                }
            }
        })
    }

    private fun bringAppToFront() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    private fun sendSttResultToServer(text: String, runtime: NodeRuntime) {
        serviceScope.launch {
            try {
                val payload = kotlinx.serialization.json.buildJsonObject {
                    put("text", kotlinx.serialization.json.JsonPrimitive(text))
                    put("context", kotlinx.serialization.json.JsonPrimitive("floating"))
                }
                runtime.sendEventToServer("stt.final_result", payload.toString())
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send stt.final_result to server, falling back to chat", e)
                runtime.chat.sendMessage(
                    message = text,
                    thinkingLevel = runtime.chat.thinkingLevel.value,
                    attachments = emptyList()
                )
            }
        }
    }

    fun handleIntentExecute(payloadJson: String?) {
        if (payloadJson.isNullOrBlank()) return
        try {
            val obj = jsonLenient.parseToJsonElement(payloadJson) as? JsonObject ?: return
            val action = obj["action"]?.jsonPrimitive?.content ?: return
            val userText = obj["userText"]?.jsonPrimitive?.content ?: obj["text"]?.jsonPrimitive?.content ?: ""
            val runtime = (application as BonioApp).runtime

            when (action) {
                "screen_capture" -> {
                    serviceScope.launch { handleScreenCaptureCommand(userText, runtime) }
                }
                "summarize" -> {
                    serviceScope.launch { handleSummarizeCommand(userText, runtime) }
                }
                "chat" -> {
                    runtime.chat.sendMessage(
                        message = userText,
                        thinkingLevel = runtime.chat.thinkingLevel.value,
                        attachments = emptyList()
                    )
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to handle intent.execute: ${e.message}")
        }
    }

    private suspend fun handleSummarizeCommand(userText: String, runtime: NodeRuntime) {
        suppressCloneHideForSmartReader = true
        try {
            withContext(Dispatchers.Main) {
                avatarController.setActivity(AgentState.Speaking)
                avatarController.setBubble("Let me have my clone read it")
            }

            CloneManager.showClone(applicationContext)

            delay(1500)

            withContext(Dispatchers.Main) {
                avatarController.setActivity(AgentState.Idle)
                avatarController.clearBubble()
            }

            val base64 = runtime.captureScreenshot(maxEdge = 1080, quality = 80)
                ?: run {
                    val capturer = runtime.screenCaptureManager
                    val payload = capturer.capture(null)
                    val payloadObj = jsonLenient.parseToJsonElement(payload.payloadJson) as? JsonObject
                    payloadObj?.get("base64")?.jsonPrimitive?.content ?: ""
                }
            if (base64.isBlank()) throw IllegalStateException("Screenshot unavailable")

            val message = if (userText.isNotBlank()) userText else "Please summarize what's on the screen"
            val attachment = OutgoingAttachment(
                type = "image",
                mimeType = "image/jpeg",
                fileName = "screenshot.jpg",
                base64 = base64,
            )

            serviceScope.launch {
                var waited = 0
                while (waited < 30_000) {
                    val state = stateManager.currentState.value
                    if (state == AgentState.Speaking) {
                        delay(500)
                        CloneManager.hideClone(applicationContext)
                        suppressCloneHideForSmartReader = false
                        break
                    }
                    if (state == AgentState.Idle && waited > 5000) {
                        CloneManager.hideClone(applicationContext)
                        suppressCloneHideForSmartReader = false
                        break
                    }
                    delay(500)
                    waited += 500
                }
                if (waited >= 30_000) {
                    CloneManager.hideClone(applicationContext)
                    suppressCloneHideForSmartReader = false
                }
            }

            runtime.chat.sendMessage(
                message = message,
                thinkingLevel = runtime.chat.thinkingLevel.value,
                attachments = listOf(attachment),
            )
        } catch (e: Exception) {
            Log.e(TAG, "Summarize command failed: ${e.message}", e)
            suppressCloneHideForSmartReader = false
            CloneManager.hideClone(applicationContext)
            withContext(Dispatchers.Main) {
                avatarController.setActivity(AgentState.Confused)
                avatarController.setBubble("Reading failed")
            }
            delay(2000)
            withContext(Dispatchers.Main) {
                avatarController.setActivity(AgentState.Idle)
                avatarController.clearBubble()
            }
        }
    }

    private suspend fun handleScreenCaptureCommand(userText: String, runtime: NodeRuntime) {
        try {
            avatarController.setBubble("Taking screenshot...")

            val base64 = runtime.captureScreenshot(maxEdge = 1080, quality = 80)
                ?: run {
                    val capturer = runtime.screenCaptureManager
                    val payload = capturer.capture(null)
                    val payloadObj = jsonLenient.parseToJsonElement(payload.payloadJson) as? JsonObject
                    payloadObj?.get("base64")?.jsonPrimitive?.content ?: ""
                }
            if (base64.isBlank()) throw IllegalStateException("Screenshot unavailable")

            avatarController.setBubble("Analyzing screen...")

            val attachment = OutgoingAttachment(
                type = "image",
                mimeType = "image/jpeg",
                fileName = "screenshot.jpg",
                base64 = base64,
            )
            runtime.chat.sendMessage(
                message = userText,
                thinkingLevel = runtime.chat.thinkingLevel.value,
                attachments = listOf(attachment),
            )
        } catch (e: Exception) {
            Log.e(TAG, "Screen capture failed: ${e.message}", e)
            avatarController.clearBubble()
            avatarController.setActivity(AgentState.Confused)
            avatarController.setBubble("Screenshot failed")
            delay(2000)
            avatarController.setActivity(AgentState.Idle)
            avatarController.clearBubble()
        }
    }

    fun showClone(animationAsset: String? = null) {
        if (isCloneAttached) return

        val view = LayoutInflater.from(this).inflate(R.layout.clone_agent_layout, null)
        val lottie = view.findViewById<LottieAnimationView>(R.id.clone_lottie)
        lottie.setFailureListener { e -> Log.w(TAG, "Clone Lottie failed", e) }

        val asset = animationAsset ?: themeManager.resolveAssetPath(
            AvatarState(activity = AgentState.Working)
        )
        try {
            lottie.repeatCount = LottieDrawable.INFINITE
            lottie.setAnimation(asset)
            lottie.playAnimation()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set clone animation: $asset", e)
        }

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val metrics = resources.displayMetrics
        val sizePx = (80 * metrics.density).toInt()
        val marginPx = (16 * metrics.density).toInt()

        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = marginPx
            y = marginPx
        }

        view.alpha = 0f
        view.scaleX = 0.3f
        view.scaleY = 0.3f

        try {
            windowManager.addView(view, params)
            isCloneAttached = true
            cloneView = view
            cloneLayoutParams = params
            cloneLottie = lottie

            view.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(300)
                .setInterpolator(android.view.animation.OvershootInterpolator(1.2f))
                .start()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add clone view", e)
        }
    }

    fun hideClone() {
        val view = cloneView ?: return
        if (!isCloneAttached) return

        view.animate()
            .alpha(0f)
            .scaleX(0.3f)
            .scaleY(0.3f)
            .setDuration(250)
            .setInterpolator(android.view.animation.AccelerateInterpolator())
            .withEndAction {
                try {
                    windowManager.removeView(view)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to remove clone view", e)
                }
                isCloneAttached = false
                cloneView = null
                cloneLayoutParams = null
                cloneLottie?.cancelAnimation()
                cloneLottie = null
            }
            .start()
    }

    fun updateCloneAnimation(animationAsset: String) {
        val lottie = cloneLottie ?: return
        try {
            lottie.repeatCount = LottieDrawable.INFINITE
            lottie.setAnimation(animationAsset)
            lottie.playAnimation()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update clone animation: $animationAsset", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cloneReceiver?.let { unregisterReceiver(it) }
        cloneReceiver = null
        if (isCloneAttached) {
            try {
                cloneView?.let { windowManager.removeView(it) }
            } catch (_: Exception) {
            }
            isCloneAttached = false
            cloneLottie?.cancelAnimation()
        }
        cloneView = null
        cloneLayoutParams = null
        cloneLottie = null
        avatarController.onTransition = null
        actionEventWatcher?.stop()
        actionEventWatcher = null
        if (isVoiceActive) {
            sttManager?.cancelListening()
            isVoiceActive = false
        }
        sttManager?.destroy()
        sttManager = null
        callTtsManager?.release()
        callTtsManager = null
        val runtime = (application as BonioApp).runtime
        runtime.callStateMonitor.stop()
        runtime.callEventHandler.ttsManager = null
        runtime.callEventHandler.sttManager = null
        runtime.avatarCommandExecutor.ttsManager = null
        runtime.floatingWindowIntentHandler = null
        runtime.chat.onAssistantReply = null
        serviceScope.cancel()
        if (::floatingView.isInitialized && isViewAttached) {
            try {
                windowManager.removeView(floatingView)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to remove floating view", e)
            }
            isViewAttached = false
        }
    }

    companion object {
        const val ACTION_TRIGGER_CUE = "ai.axiomaster.bonio.ACTION_MAGIC_CUE"
        const val ACTION_APPLY_CUE = "ai.axiomaster.bonio.ACTION_APPLY_CUE"
        private const val TAG = "BonioApp"
        private const val LONG_PRESS_THRESHOLD_MS = 600L
        private const val DOUBLE_TAP_THRESHOLD_MS = 500L
        private const val SUGGESTION_DISPLAY_MS = 15_000L
        private const val SUGGESTION_BG_COLOR = 0xE62D303E.toInt()
        private const val DRAG_THRESHOLD_DP = 10f
        private const val PREFS_NAME = "bonio_floating_window"
        private const val KEY_POS_X = "pos_x"
        private const val KEY_POS_Y = "pos_y"
    }
}
