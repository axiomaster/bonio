package ai.axiomaster.boji.remote.node

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.CallLog
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class CallStateMonitor(
    private val context: Context,
    private val scope: CoroutineScope,
    private val sendEvent: suspend (event: String, payloadJson: String) -> Unit,
) {
    var onCallEnded: (() -> Unit)? = null

    private var receiver: BroadcastReceiver? = null
    private var lastState: String? = null
    private var ringingNumber: String? = null
    private var callStartTime: Long = 0L
    private var incomingEventSent = false

    fun start() {
        if (receiver != null) return
        if (!hasTelephony()) {
            Log.w(TAG, "No telephony hardware, skipping call monitor")
            return
        }

        val br = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
                val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
                @Suppress("DEPRECATION")
                val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                Log.d(TAG, "Phone state broadcast: state=$stateStr, number=$number")
                handleCallState(stateStr, number)
            }
        }
        receiver = br

        try {
            val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(br, filter, Context.RECEIVER_EXPORTED)
            } else {
                context.registerReceiver(br, filter)
            }
            Log.i(TAG, "Call state monitoring started (BroadcastReceiver)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register call state receiver: ${e.message}", e)
            receiver = null
        }
    }

    fun stop() {
        receiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to unregister receiver: ${e.message}")
            }
            receiver = null
            Log.i(TAG, "Call state monitoring stopped")
        }
    }

    private fun handleCallState(stateStr: String, number: String?) {
        when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                if (number != null && number.isNotBlank()) {
                    ringingNumber = number
                    Log.d(TAG, "Got number from broadcast: $number")
                }

                if (lastState == TelephonyManager.EXTRA_STATE_RINGING) {
                    Log.d(TAG, "Duplicate RINGING broadcast (number update), ignoring")
                    return
                }
                lastState = stateStr
                callStartTime = System.currentTimeMillis()
                incomingEventSent = false

                scope.launch {
                    // Wait briefly for a second broadcast that might carry the number
                    if (ringingNumber == null) {
                        delay(600)
                    }
                    // Fallback: query call log for recent incoming calls
                    if (ringingNumber == null) {
                        ringingNumber = queryRecentCallLogNumber()
                        if (ringingNumber != null) {
                            Log.d(TAG, "Got number from call log: $ringingNumber")
                        }
                    }

                    if (incomingEventSent) return@launch
                    incomingEventSent = true

                    val callerNumber = ringingNumber ?: "unknown"
                    val contactName = lookupContactName(callerNumber)

                    Log.i(TAG, "Incoming call: $callerNumber (contact: $contactName)")
                    val payload = buildJsonObject {
                        put("number", callerNumber)
                        put("contactName", contactName ?: "")
                        put("timestamp", callStartTime)
                    }.toString()
                    try {
                        sendEvent("telephony.incoming_call", payload)
                        Log.i(TAG, "Sent telephony.incoming_call event")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to send incoming_call event: ${e.message}", e)
                    }
                }
            }

            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                if (lastState == TelephonyManager.EXTRA_STATE_RINGING) {
                    val payload = buildJsonObject {
                        put("number", ringingNumber ?: "unknown")
                        put("timestamp", System.currentTimeMillis())
                    }.toString()
                    scope.launch {
                        try {
                            sendEvent("telephony.call_answered", payload)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to send call_answered event: ${e.message}", e)
                        }
                    }
                }
                lastState = stateStr
            }

            TelephonyManager.EXTRA_STATE_IDLE -> {
                if (lastState != null && lastState != TelephonyManager.EXTRA_STATE_IDLE) {
                    val duration = if (callStartTime > 0)
                        (System.currentTimeMillis() - callStartTime) / 1000 else 0
                    val payload = buildJsonObject {
                        put("number", ringingNumber ?: "unknown")
                        put("duration", duration)
                        put("timestamp", System.currentTimeMillis())
                    }.toString()
                    scope.launch {
                        try {
                            sendEvent("telephony.call_ended", payload)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to send call_ended event: ${e.message}", e)
                        }
                    }
                    ringingNumber = null
                    callStartTime = 0
                    incomingEventSent = false
                    onCallEnded?.invoke()
                }
                lastState = stateStr
            }
        }
    }

    /**
     * Query the call log for the most recent entry within the last 5 seconds.
     * On many Chinese phones, the call log is updated during RINGING.
     */
    private fun queryRecentCallLogNumber(): String? {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.d(TAG, "READ_CALL_LOG permission not granted")
            return null
        }

        var cursor: Cursor? = null
        try {
            val recentThreshold = System.currentTimeMillis() - 5000
            cursor = context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE),
                "${CallLog.Calls.DATE} > ?",
                arrayOf(recentThreshold.toString()),
                "${CallLog.Calls.DATE} DESC"
            )
            if (cursor != null && cursor.moveToFirst()) {
                val num = cursor.getString(0)
                if (!num.isNullOrBlank()) return num
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to query recent call log: ${e.message}")
        } finally {
            cursor?.close()
        }
        return null
    }

    private fun lookupContactName(number: String): String? {
        if (number == "unknown" || number.isBlank()) return null
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.d(TAG, "READ_CONTACTS permission not granted, skipping contact lookup")
            return null
        }

        var cursor: Cursor? = null
        try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(number)
            )
            cursor = context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )
            if (cursor != null && cursor.moveToFirst()) {
                return cursor.getString(0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Contact lookup failed: ${e.message}")
        } finally {
            cursor?.close()
        }
        return null
    }

    private fun hasTelephony(): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)

    companion object {
        private const val TAG = "CallStateMonitor"
    }
}
