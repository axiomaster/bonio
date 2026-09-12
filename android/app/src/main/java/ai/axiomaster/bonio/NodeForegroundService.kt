package ai.axiomaster.bonio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class NodeForegroundService : Service() {
  private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  private var notificationJob: Job? = null
  private var lastRequiresMic = false
  private var lastRequiresMediaProjection = false
  private var mediaProjectionActive = false
  private var didStartForeground = false
  private var lastNotification: Notification? = null

  override fun onCreate() {
    super.onCreate()
    ensureChannel()
    val initial = buildNotification(title = "Bonio Remote", text = "Starting…")
    startForegroundWithTypes(notification = initial, requiresMic = false, requiresMediaProjection = false)

    val runtime = (application as BonioApp).runtime
    if (runtime.prefs.localEnabled.value) {
      (application as BonioApp).localEngine.ensureStarted()
    }
    notificationJob =
      scope.launch {
        combine(
          runtime.statusText,
          runtime.serverName,
          runtime.isConnected,
        ) { status, server, connected ->
          Triple(status, server, connected)
        }.collect { (status, server, connected) ->
          val title = if (connected) "Bonio Remote · Connected" else "Bonio Remote"
          val text = server?.let { "$status · $it" } ?: status

          val notif = buildNotification(title = title, text = text)
          lastNotification = notif
          // Mic requirement check (simplified for now)
          val requiresMic = false
          startForegroundWithTypes(
            notification = notif,
            requiresMic = requiresMic,
            requiresMediaProjection = mediaProjectionActive,
          )
        }
      }
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_STOP -> {
        (application as BonioApp).runtime.disconnect()
        (application as BonioApp).localEngine.stop()
        stopSelf()
        return START_NOT_STICKY
      }
      ACTION_ENABLE_MEDIA_PROJECTION -> {
        mediaProjectionActive = true
        val notif = lastNotification ?: buildNotification(title = "Bonio Remote", text = "Screen capture authorized")
        startForegroundWithTypes(notif, requiresMic = false, requiresMediaProjection = true)
        return START_STICKY
      }
      ACTION_DISABLE_MEDIA_PROJECTION -> {
        mediaProjectionActive = false
        val notif = lastNotification ?: buildNotification(title = "Bonio Remote", text = "Connected")
        startForegroundWithTypes(notif, requiresMic = false, requiresMediaProjection = false)
        return START_STICKY
      }
    }
    return START_STICKY
  }

  override fun onDestroy() {
    notificationJob?.cancel()
    scope.cancel()
    super.onDestroy()
  }

  override fun onBind(intent: Intent?) = null

  private fun ensureChannel() {
    val mgr = getSystemService(NotificationManager::class.java)
    val channel =
      NotificationChannel(
        CHANNEL_ID,
        "Connection",
        NotificationManager.IMPORTANCE_LOW,
      ).apply {
        description = "Bonio remote connection status"
        setShowBadge(false)
      }
    mgr.createNotificationChannel(channel)
  }

  private fun buildNotification(title: String, text: String): Notification {
    val launchIntent = Intent(this, MainActivity::class.java).apply {
      flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val launchPending =
      PendingIntent.getActivity(
        this,
        1,
        launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )

    val stopIntent = Intent(this, NodeForegroundService::class.java).setAction(ACTION_STOP)
    val stopPending =
      PendingIntent.getService(
        this,
        2,
        stopIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )

    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle(title)
      .setContentText(text)
      .setContentIntent(launchPending)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
      .addAction(0, "Disconnect", stopPending)
      .build()
  }

  private fun updateNotification(notification: Notification) {
    val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    mgr.notify(NOTIFICATION_ID, notification)
  }

  private fun startForegroundWithTypes(
    notification: Notification,
    requiresMic: Boolean,
    requiresMediaProjection: Boolean
  ) {
    if (didStartForeground && requiresMic == lastRequiresMic && requiresMediaProjection == lastRequiresMediaProjection) {
      updateNotification(notification)
      return
    }

    lastRequiresMic = requiresMic
    lastRequiresMediaProjection = requiresMediaProjection
    var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
    if (requiresMic) {
      types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
    }
    if (requiresMediaProjection && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
    }
    startForeground(NOTIFICATION_ID, notification, types)
    didStartForeground = true
  }

  companion object {
    private const val CHANNEL_ID = "connection"
    private const val NOTIFICATION_ID = 1
    private const val ACTION_STOP = "ai.axiomaster.Bonio.action.STOP"
    private const val ACTION_ENABLE_MEDIA_PROJECTION = "ai.axiomaster.Bonio.action.ENABLE_MEDIA_PROJECTION"
    private const val ACTION_DISABLE_MEDIA_PROJECTION = "ai.axiomaster.Bonio.action.DISABLE_MEDIA_PROJECTION"

    fun start(context: Context) {
      val intent = Intent(context, NodeForegroundService::class.java)
      context.startForegroundService(intent)
    }

    fun stop(context: Context) {
      val intent = Intent(context, NodeForegroundService::class.java).setAction(ACTION_STOP)
      context.startService(intent)
    }

    fun updateMediaProjection(context: Context, enabled: Boolean) {
      val action = if (enabled) ACTION_ENABLE_MEDIA_PROJECTION else ACTION_DISABLE_MEDIA_PROJECTION
      val intent = Intent(context, NodeForegroundService::class.java).setAction(action)
      context.startService(intent)
    }
  }
}
