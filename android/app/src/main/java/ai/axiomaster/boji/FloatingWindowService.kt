package ai.axiomaster.boji

import ai.axiomaster.boji.ai.AgentManager
import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.avatar.AvatarController
import ai.axiomaster.boji.avatar.AvatarState
import ai.axiomaster.boji.avatar.MotionState
import ai.axiomaster.boji.avatar.ThemeManager
import ai.axiomaster.boji.avatar.ActionEventWatcher
import ai.axiomaster.boji.remote.chat.SpeechToTextManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.util.Log
import android.widget.TextView
import androidx.cardview.widget.CardView
import androidx.core.content.ContextCompat
import com.airbnb.lottie.LottieAnimationView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class FloatingWindowService : Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var floatingView: View
    private lateinit var layoutParams: WindowManager.LayoutParams

    private lateinit var lottieAnimationView: LottieAnimationView
    private lateinit var bubbleContainer: CardView
    private lateinit var bubbleLabel: TextView
    private lateinit var textBubble: TextView

    private val avatarController: AvatarController get() = AgentManager.avatarController
    private val stateManager get() = AgentManager.stateManager
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var themeManager: ThemeManager
    private var actionEventWatcher: ActionEventWatcher? = null
    private var idleBehaviorScheduler: ai.axiomaster.boji.avatar.IdleBehaviorScheduler? = null

    private var sttManager: SpeechToTextManager? = null
    private var isVoiceActive = false
    private var voiceSessionId = 0

    private var currentAssetPath: String? = null
    private var isPlayingTransition = false

    override fun onBind(intent: Intent?): IBinder? = null

    private var isViewAttached = false

    private val prefs by lazy {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    override fun onCreate() {
        Log.d(TAG, "FloatingWindowService onCreate")
        super.onCreate()

        themeManager = ThemeManager(applicationContext)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "boji_agent_channel"
            val channel = android.app.NotificationChannel(
                channelId,
                "Desktop Agent Service",
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager?.createNotificationChannel(channel)

            val notification = android.app.Notification.Builder(this, channelId)
                .setContentTitle("BoJi Agent")
                .setContentText("Agent is running in the background")
                .setSmallIcon(R.mipmap.ic_launcher)
                .build()

            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(
                    101, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(101, notification)
            }
        }

        sttManager = SpeechToTextManager(applicationContext)
        sttManager?.warmUpVosk()

        avatarController.updateScreenMetrics(resources.displayMetrics)

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        floatingView = LayoutInflater.from(this).inflate(R.layout.floating_agent_layout, null)

        lottieAnimationView = floatingView.findViewById(R.id.lottie_agent)
        lottieAnimationView.setFailureListener { e ->
            Log.w(TAG, "Lottie composition failed, ignoring", e)
        }
        bubbleContainer = floatingView.findViewById(R.id.bubble_container)
        bubbleLabel = floatingView.findViewById(R.id.bubble_label)
        textBubble = floatingView.findViewById(R.id.text_bubble)

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

        // Start idle wandering behavior (reads enabled state from BoJiApp)
        val bojiApp = application as BoJiApp
        val wanderingEnabled = kotlinx.coroutines.flow.MutableStateFlow(false)
        serviceScope.launch {
            // Poll the preference periodically since we don't have direct ViewModel access
            val prefs = applicationContext.getSharedPreferences("boji_avatar", Context.MODE_PRIVATE)
            while (true) {
                wanderingEnabled.value = prefs.getBoolean("cat_wandering", false)
                kotlinx.coroutines.delay(2000)
            }
        }
        idleBehaviorScheduler = ai.axiomaster.boji.avatar.IdleBehaviorScheduler(
            controller = avatarController,
            enabled = wanderingEnabled,
            scope = serviceScope,
        )
        idleBehaviorScheduler?.start()

        // Observe overlay visibility preference
        serviceScope.launch {
            val prefs = applicationContext.getSharedPreferences("boji_avatar", Context.MODE_PRIVATE)
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
        return START_NOT_STICKY
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
            }
        }

        // Observe text bubble
        serviceScope.launch {
            stateManager.currentTextBubble.collect { text: String? ->
                if (text.isNullOrEmpty()) {
                    if (bubbleLabel.visibility != View.VISIBLE) {
                        bubbleContainer.visibility = View.GONE
                    }
                    textBubble.visibility = View.GONE
                } else {
                    textBubble.text = text
                    textBubble.visibility = View.VISIBLE
                    bubbleContainer.visibility = View.VISIBLE
                }
            }
        }

        // Observe streaming assistant text
        val chatController = (application as BoJiApp).runtime.chat
        serviceScope.launch {
            chatController.streamingAssistantText.collect { text: String? ->
                val state = stateManager.currentState.value
                if (!text.isNullOrEmpty()) {
                    val lines = text.lines()
                    val lastTwoLines = lines.takeLast(2).joinToString("\n")
                    stateManager.setBubble(lastTwoLines)
                } else if (state != AgentState.Listening && state != AgentState.Speaking) {
                    stateManager.clearBubble()
                }
            }
        }
    }

    private fun updateAnimation(state: AvatarState) {
        if (isPlayingTransition) {
            updateFlip(state)
            return
        }

        val assetPath = themeManager.resolveAssetPath(state)
        if (assetPath == currentAssetPath) return
        currentAssetPath = assetPath

        try {
            lottieAnimationView.repeatCount = com.airbnb.lottie.LottieDrawable.INFINITE
            lottieAnimationView.setAnimation(assetPath)
            lottieAnimationView.playAnimation()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set Lottie animation: $assetPath", e)
        }

        updateFlip(state)
    }

    private fun updateFlip(state: AvatarState) {
        val target = state.targetPosition
        if (target != null && (state.motion == MotionState.Walking || state.motion == MotionState.Running)) {
            val movingLeft = target.x < state.position.x
            lottieAnimationView.scaleX = if (movingLeft) -1f else 1f
        } else {
            lottieAnimationView.scaleX = 1f
        }
    }

    private fun playTransitionThenLoop(transition: ai.axiomaster.boji.avatar.AvatarTransition) {
        val transitionPath = themeManager.resolveTransitionPath(transition) ?: return
        isPlayingTransition = true
        currentAssetPath = null

        try {
            lottieAnimationView.repeatCount = 0
            lottieAnimationView.setAnimation(transitionPath)
            lottieAnimationView.removeAllAnimatorListeners()
            lottieAnimationView.addAnimatorListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    lottieAnimationView.removeAllAnimatorListeners()
                    isPlayingTransition = false
                    avatarController.clearTransition()
                    val stableState = avatarController.avatarState.value
                    updateAnimation(stableState)
                }
            })
            lottieAnimationView.playAnimation()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to play transition animation: $transitionPath", e)
            isPlayingTransition = false
            avatarController.clearTransition()
        }
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

    private fun updateBubbleForActivity(state: AvatarState) {
        val labelText = when (state.activity) {
            AgentState.Listening -> "Listening..."
            AgentState.Thinking -> "Thinking..."
            AgentState.Speaking -> "Speaking..."
            AgentState.Working -> "Working..."
            AgentState.Happy -> null
            AgentState.Confused -> "Hmm?"
            AgentState.Angry -> "Grr!"
            AgentState.Watching -> null
            AgentState.Bored -> null
            AgentState.Sleeping -> "Zzz..."
            AgentState.Idle -> null
        }
        if (labelText != null) {
            bubbleLabel.text = labelText
            bubbleLabel.visibility = View.VISIBLE
            bubbleContainer.visibility = View.VISIBLE
        } else {
            bubbleLabel.visibility = View.GONE
            if (textBubble.visibility != View.VISIBLE) {
                bubbleContainer.visibility = View.GONE
            }
        }
    }

    private fun setupTouchListener() {
        val density = resources.displayMetrics.density
        val dragThresholdPx = (DRAG_THRESHOLD_DP * density).toInt()
        Log.d(TAG, "setupTouchListener: dragThresholdPx=$dragThresholdPx density=$density")

        lottieAnimationView.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isDragging = false
            private var longPressTriggered = false

            private val longPressRunnable = Runnable {
                if (!isDragging) {
                    longPressTriggered = true
                    Log.d(TAG, "Long press detected -> starting voice input")
                    startVoiceInputFromFloating()
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
                            val newX = initialX + dx
                            val newY = initialY + dy
                            avatarController.dragTo(newX, newY)
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        mainHandler.removeCallbacks(longPressRunnable)
                        if (longPressTriggered) {
                            Log.d(TAG, "Finger lifted -> stopping voice input")
                            stopVoiceInputFromFloating()
                            longPressTriggered = false
                        } else if (isDragging) {
                            avatarController.endDrag()
                            savePosition()
                        } else {
                            v?.performClick()
                            handleAgentClick()
                        }
                        return true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        mainHandler.removeCallbacks(longPressRunnable)
                        if (longPressTriggered) {
                            cancelVoiceInputFromFloating()
                            longPressTriggered = false
                        } else if (isDragging) {
                            avatarController.endDrag()
                        }
                        return true
                    }
                }
                return false
            }
        })
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
                val runtime = (application as BoJiApp).runtime
                runtime.chat.sendMessage(
                    message = text,
                    thinkingLevel = runtime.chat.thinkingLevel.value,
                    attachments = emptyList()
                )
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
        bringAppToFront()
    }

    private fun bringAppToFront() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        avatarController.onTransition = null
        idleBehaviorScheduler?.stop()
        idleBehaviorScheduler = null
        actionEventWatcher?.stop()
        actionEventWatcher = null
        if (isVoiceActive) {
            sttManager?.cancelListening()
            isVoiceActive = false
        }
        sttManager?.destroy()
        sttManager = null
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
        private const val TAG = "BoJiApp"
        private const val LONG_PRESS_THRESHOLD_MS = 600L
        private const val DRAG_THRESHOLD_DP = 10f
        private const val PREFS_NAME = "boji_floating_window"
        private const val KEY_POS_X = "pos_x"
        private const val KEY_POS_Y = "pos_y"
    }
}
