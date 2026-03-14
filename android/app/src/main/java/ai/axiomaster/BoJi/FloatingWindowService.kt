package ai.axiomaster.BoJi

import ai.axiomaster.BoJi.ai.AgentManager
import ai.axiomaster.BoJi.ai.AgentState
import ai.axiomaster.BoJi.ai.AgentStateManager
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.cardview.widget.CardView
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
    private lateinit var textBubble: TextView

    private val stateManager = AgentManager.stateManager
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private var isViewAttached = false

    override fun onCreate() {
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
            startForeground(1, notification)
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        
        floatingView = LayoutInflater.from(this).inflate(R.layout.floating_agent_layout, null)

        lottieAnimationView = floatingView.findViewById(R.id.lottie_agent)
        bubbleContainer = floatingView.findViewById(R.id.bubble_container)
        textBubble = floatingView.findViewById(R.id.text_bubble)

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
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 100
        }

        setupTouchListener()
        observeAgentState()
        
        try {
            windowManager.addView(floatingView, layoutParams)
            isViewAttached = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isViewAttached) {
            try {
                windowManager.addView(floatingView, layoutParams)
                isViewAttached = true
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        return START_NOT_STICKY
    }

    private fun observeAgentState() {
        serviceScope.launch {
            stateManager.currentState.collect { state ->
                when (state) {
                    AgentState.Idle -> {
                        lottieAnimationView.setAnimation("Cat playing animation.lottie")
                        lottieAnimationView.playAnimation()
                    }
                    AgentState.Listening -> {
                        // Placeholder for listening animation
                    }
                    AgentState.Thinking -> {
                        // Placeholder for thinking animation
                    }
                    AgentState.Speaking -> {
                        // Placeholder for speaking animation
                    }
                    AgentState.Working -> {
                        // Handled in Phase 4
                    }
                }
            }
        }

        serviceScope.launch {
            stateManager.currentTextBubble.collect { text ->
                if (text.isNullOrEmpty()) {
                    bubbleContainer.visibility = View.GONE
                } else {
                    textBubble.text = text
                    bubbleContainer.visibility = View.VISIBLE
                }
            }
        }
    }

    private fun setupTouchListener() {
        floatingView.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isClick = false

            override fun onTouch(v: View?, event: MotionEvent?): Boolean {
                if (event == null) return false

                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams.x
                        initialY = layoutParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isClick = true
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                            isClick = false
                        }
                        layoutParams.x = initialX + dx.toInt()
                        layoutParams.y = initialY + dy.toInt()
                        windowManager.updateViewLayout(floatingView, layoutParams)
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (isClick) {
                            v?.performClick()
                            handleAgentClick()
                        }
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun handleAgentClick() {
        // Bring MainActivity to front
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)

        // Cycle states for testing purposes
        when (stateManager.currentState.value) {
            AgentState.Idle -> stateManager.transitionTo(AgentState.Listening)
            AgentState.Listening -> stateManager.transitionTo(AgentState.Thinking)
            AgentState.Thinking -> stateManager.transitionTo(AgentState.Idle)
            else -> stateManager.transitionTo(AgentState.Idle)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        if (::floatingView.isInitialized && isViewAttached) {
            try {
                windowManager.removeView(floatingView)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isViewAttached = false
        }
    }
}
