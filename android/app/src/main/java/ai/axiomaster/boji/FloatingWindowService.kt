package ai.axiomaster.boji

import ai.axiomaster.boji.ai.AgentManager
import ai.axiomaster.boji.ai.AgentState
import ai.axiomaster.boji.remote.chat.SpeechToTextManager
import ai.axiomaster.boji.remote.theme.ThemeRepository
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

    private val stateManager = AgentManager.stateManager
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var sttManager: SpeechToTextManager? = null
    private var isVoiceActive = false

    override fun onBind(intent: Intent?): IBinder? = null

    private var isViewAttached = false

    private val prefs by lazy {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    override fun onCreate() {
        Log.d(TAG, "FloatingWindowService onCreate")
        super.onCreate()

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
        observeAgentState()

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

    private fun observeAgentState() {
        serviceScope.launch {
            val themes = ThemeRepository(applicationContext).listInstalledThemes()
            stateManager.currentState.collect { state: AgentState ->
                val stateKey = when (state) {
                    AgentState.Idle -> "idle"
                    AgentState.Listening -> "listening"
                    AgentState.Thinking -> "thinking"
                    AgentState.Speaking -> "speaking"
                    AgentState.Working -> "working"
                }
                val assetName = themes.firstOrNull()?.assetPathForState(stateKey)
                    ?: when (state) {
                        AgentState.Idle -> "cat-idle.lottie"
                        AgentState.Listening -> "cat-listening.lottie"
                        AgentState.Thinking -> "cat-thinking.lottie"
                        AgentState.Speaking -> "cat-speaking.lottie"
                        AgentState.Working -> "cat-working.lottie"
                    }
                try {
                    lottieAnimationView.setAnimation(assetName)
                    lottieAnimationView.playAnimation()
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to set Lottie animation: $assetName", e)
                }

                when (state) {
                    AgentState.Listening -> {
                        bubbleLabel.text = "Listening..."
                        bubbleLabel.visibility = View.VISIBLE
                        bubbleContainer.visibility = View.VISIBLE
                    }
                    AgentState.Thinking -> {
                        bubbleLabel.text = "Thinking..."
                        bubbleLabel.visibility = View.VISIBLE
                        bubbleContainer.visibility = View.VISIBLE
                    }
                    AgentState.Speaking -> {
                        bubbleLabel.text = "Speaking..."
                        bubbleLabel.visibility = View.VISIBLE
                        bubbleContainer.visibility = View.VISIBLE
                    }
                    else -> {
                        bubbleLabel.visibility = View.GONE
                        if (textBubble.visibility != View.VISIBLE) {
                            bubbleContainer.visibility = View.GONE
                        }
                    }
                }
            }
        }

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
                        if (longPressTriggered) {
                            return true
                        }
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (!isDragging && (Math.abs(dx) > dragThresholdPx || Math.abs(dy) > dragThresholdPx)) {
                            isDragging = true
                            mainHandler.removeCallbacks(longPressRunnable)
                        }
                        if (isDragging) {
                            layoutParams.x = initialX + dx.toInt()
                            layoutParams.y = initialY + dy.toInt()
                            windowManager.updateViewLayout(floatingView, layoutParams)
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
        if (currentState != AgentState.Idle) {
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
        isVoiceActive = true
        stateManager.transitionTo(AgentState.Listening)

        sttManager?.startListening(object : SpeechToTextManager.Listener {
            override fun onPartialResult(text: String) {
                stateManager.setBubble(text)
            }

            override fun onFinalResult(text: String) {
                Log.d(TAG, "STT final result from floating: $text")
                isVoiceActive = false
                stateManager.clearBubble()
                stateManager.transitionTo(AgentState.Thinking)
                val runtime = (application as BoJiApp).runtime
                runtime.chat.sendMessage(
                    message = text,
                    thinkingLevel = runtime.chat.thinkingLevel.value,
                    attachments = emptyList()
                )
            }

            override fun onError(errorCode: Int) {
                Log.w(TAG, "STT error from floating: $errorCode")
                isVoiceActive = false
                stateManager.clearBubble()
                stateManager.transitionTo(AgentState.Idle)
            }

            override fun onReadyForSpeech() {
                Log.d(TAG, "STT ready for speech from floating")
            }

            override fun onEndOfSpeech() {
                Log.d(TAG, "STT end of speech from floating")
                if (isVoiceActive) {
                    isVoiceActive = false
                    stateManager.clearBubble()
                    stateManager.transitionTo(AgentState.Idle)
                }
            }
        })
    }

    private fun stopVoiceInputFromFloating() {
        if (isVoiceActive) {
            Log.d(TAG, "Stopping voice input from floating window")
            sttManager?.stopListening()
            mainHandler.postDelayed({
                if (isVoiceActive) {
                    Log.w(TAG, "STT stop safety timeout — forcing state reset")
                    isVoiceActive = false
                    stateManager.clearBubble()
                    stateManager.transitionTo(AgentState.Idle)
                }
            }, 1500L)
        }
    }

    private fun cancelVoiceInputFromFloating() {
        if (isVoiceActive) {
            Log.d(TAG, "Cancelling voice input from floating window")
            sttManager?.cancelListening()
            isVoiceActive = false
            AgentManager.stateManager.transitionTo(AgentState.Idle)
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
        private const val LONG_PRESS_THRESHOLD_MS = 300L
        private const val DRAG_THRESHOLD_DP = 15f
        private const val PREFS_NAME = "boji_floating_window"
        private const val KEY_POS_X = "pos_x"
        private const val KEY_POS_Y = "pos_y"
    }
}
