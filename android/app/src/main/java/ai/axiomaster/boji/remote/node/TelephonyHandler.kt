package ai.axiomaster.boji.remote.node

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat
import ai.axiomaster.boji.remote.gateway.GatewaySession
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class TelephonyHandler(private val context: Context) {

    private val telecomManager: TelecomManager =
        context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
    private val telephonyManager: TelephonyManager =
        context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

    @Suppress("DEPRECATION")
    suspend fun handleAnswer(paramsJson: String?): GatewaySession.InvokeResult {
        if (!hasPermission(Manifest.permission.ANSWER_PHONE_CALLS)) {
            return GatewaySession.InvokeResult.error(
                code = "PERMISSION_DENIED",
                message = "ANSWER_PHONE_CALLS permission not granted"
            )
        }
        return try {
            telecomManager.acceptRingingCall()
            Log.i(TAG, "Call answered via TelecomManager")
            GatewaySession.InvokeResult.ok(
                buildJsonObject { put("status", "answered") }.toString()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to answer call: ${e.message}")
            GatewaySession.InvokeResult.error(
                code = "TELEPHONY_ERROR",
                message = "Failed to answer call: ${e.message}"
            )
        }
    }

    suspend fun handleReject(paramsJson: String?): GatewaySession.InvokeResult {
        if (!hasPermission(Manifest.permission.ANSWER_PHONE_CALLS)) {
            return GatewaySession.InvokeResult.error(
                code = "PERMISSION_DENIED",
                message = "ANSWER_PHONE_CALLS permission not granted"
            )
        }
        return try {
            @Suppress("DEPRECATION")
            val ended = telecomManager.endCall()
            Log.i(TAG, "Call rejected via TelecomManager: $ended")
            GatewaySession.InvokeResult.ok(
                buildJsonObject { put("status", if (ended) "rejected" else "no_active_call") }.toString()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reject call: ${e.message}")
            GatewaySession.InvokeResult.error(
                code = "TELEPHONY_ERROR",
                message = "Failed to reject call: ${e.message}"
            )
        }
    }

    suspend fun handleState(paramsJson: String?): GatewaySession.InvokeResult {
        @Suppress("DEPRECATION")
        val stateStr = try {
            when (telephonyManager.callState) {
                TelephonyManager.CALL_STATE_IDLE -> "idle"
                TelephonyManager.CALL_STATE_RINGING -> "ringing"
                TelephonyManager.CALL_STATE_OFFHOOK -> "offhook"
                else -> "unknown"
            }
        } catch (e: SecurityException) {
            "permission_denied"
        }
        return GatewaySession.InvokeResult.ok(
            buildJsonObject { put("callState", stateStr) }.toString()
        )
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    companion object {
        private const val TAG = "TelephonyHandler"
    }
}
