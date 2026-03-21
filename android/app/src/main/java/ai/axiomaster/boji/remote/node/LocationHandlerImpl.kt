package ai.axiomaster.boji.remote.node

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.util.Log
import androidx.core.content.ContextCompat
import ai.axiomaster.boji.remote.gateway.GatewaySession
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.coroutines.resume

class LocationHandlerImpl(private val context: Context) {

  suspend fun handleLocationGet(p: String?): GatewaySession.InvokeResult {
    val fineOk = ContextCompat.checkSelfPermission(
      context, Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
    val coarseOk = ContextCompat.checkSelfPermission(
      context, Manifest.permission.ACCESS_COARSE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    if (!fineOk && !coarseOk) {
      return GatewaySession.InvokeResult.error(
        code = "LOCATION_PERMISSION_DENIED",
        message = "LOCATION_PERMISSION_DENIED: grant location permission in Settings",
      )
    }

    val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
      ?: return GatewaySession.InvokeResult.error(
        code = "LOCATION_UNAVAILABLE",
        message = "LOCATION_UNAVAILABLE: LocationManager not available",
      )

    val location = getBestLastKnownLocation(lm, fineOk)
      ?: try {
        requestSingleUpdate(lm, fineOk)
      } catch (e: Throwable) {
        Log.w("LocationHandler", "requestSingleUpdate failed", e)
        null
      }

    if (location == null) {
      return GatewaySession.InvokeResult.error(
        code = "LOCATION_UNAVAILABLE",
        message = "LOCATION_UNAVAILABLE: could not obtain location fix",
      )
    }

    val json = buildJsonObject {
      put("latitude", location.latitude)
      put("longitude", location.longitude)
      put("accuracy", location.accuracy.toDouble())
      if (location.hasAltitude()) put("altitude", location.altitude)
      if (location.hasSpeed()) put("speed", location.speed.toDouble())
      if (location.hasBearing()) put("bearing", location.bearing.toDouble())
      put("time", location.time)
      put("provider", location.provider ?: "unknown")
    }
    return GatewaySession.InvokeResult.ok(json.toString())
  }

  @Suppress("MissingPermission")
  private fun getBestLastKnownLocation(lm: LocationManager, fineOk: Boolean): Location? {
    val providers = buildList {
      if (fineOk) add(LocationManager.GPS_PROVIDER)
      add(LocationManager.NETWORK_PROVIDER)
      add(LocationManager.FUSED_PROVIDER)
    }

    var best: Location? = null
    for (provider in providers) {
      try {
        val loc = lm.getLastKnownLocation(provider) ?: continue
        val age = System.currentTimeMillis() - loc.time
        if (age > MAX_CACHE_AGE_MS) continue
        if (best == null || loc.accuracy < best.accuracy) {
          best = loc
        }
      } catch (_: Throwable) { }
    }
    return best
  }

  @Suppress("MissingPermission")
  private suspend fun requestSingleUpdate(lm: LocationManager, fineOk: Boolean): Location? {
    val provider = when {
      fineOk && lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
        LocationManager.GPS_PROVIDER
      lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
        LocationManager.NETWORK_PROVIDER
      lm.isProviderEnabled(LocationManager.FUSED_PROVIDER) ->
        LocationManager.FUSED_PROVIDER
      else -> return null
    }

    val cancellationSignal = android.os.CancellationSignal()
    return withTimeout(SINGLE_UPDATE_TIMEOUT_MS) {
      suspendCancellableCoroutine { cont ->
        cont.invokeOnCancellation { cancellationSignal.cancel() }
        lm.getCurrentLocation(
          provider,
          cancellationSignal,
          { it.run() },
        ) { location ->
          if (cont.isActive) cont.resume(location)
        }
      }
    }
  }

  companion object {
    private const val MAX_CACHE_AGE_MS = 2 * 60 * 1000L
    private const val SINGLE_UPDATE_TIMEOUT_MS = 15_000L
  }
}
