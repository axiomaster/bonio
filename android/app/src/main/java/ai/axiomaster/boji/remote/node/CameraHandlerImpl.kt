package ai.axiomaster.boji.remote.node

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Base64
import android.util.Log
import androidx.core.content.ContextCompat
import ai.axiomaster.boji.remote.gateway.GatewaySession
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private const val TAG = "CameraHandler"
private const val SNAP_TIMEOUT_MS = 10_000L

class CameraHandlerImpl(private val context: Context) {

  suspend fun handleList(p: String?): GatewaySession.InvokeResult {
    if (!hasCameraPermission()) {
      return GatewaySession.InvokeResult.error(
        code = "CAMERA_PERMISSION_DENIED",
        message = "CAMERA_PERMISSION_DENIED: grant camera permission in Settings",
      )
    }

    val cm = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
      ?: return GatewaySession.InvokeResult.error(
        code = "CAMERA_UNAVAILABLE",
        message = "CAMERA_UNAVAILABLE: CameraManager not available",
      )

    val cameras = cm.cameraIdList.mapNotNull { id ->
      try {
        val chars = cm.getCameraCharacteristics(id)
        val facing = chars.get(CameraCharacteristics.LENS_FACING)
        val facingStr = when (facing) {
          CameraCharacteristics.LENS_FACING_FRONT -> "front"
          CameraCharacteristics.LENS_FACING_BACK -> "back"
          CameraCharacteristics.LENS_FACING_EXTERNAL -> "external"
          else -> "unknown"
        }
        buildJsonObject {
          put("id", id)
          put("facing", facingStr)
        }
      } catch (e: Throwable) {
        Log.w(TAG, "Failed to query camera $id", e)
        null
      }
    }

    val json = buildJsonObject {
      put("cameras", JsonArray(cameras))
    }
    return GatewaySession.InvokeResult.ok(json.toString())
  }

  suspend fun handleSnap(p: String?): GatewaySession.InvokeResult {
    if (!hasCameraPermission()) {
      return GatewaySession.InvokeResult.error(
        code = "CAMERA_PERMISSION_DENIED",
        message = "CAMERA_PERMISSION_DENIED: grant camera permission in Settings",
      )
    }

    val params = parseJsonParamsObject(p)
    val requestedCameraId = parseJsonString(params, "cameraId")
    val requestedFacing = parseJsonString(params, "facing") ?: "back"

    val cm = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
      ?: return GatewaySession.InvokeResult.error(
        code = "CAMERA_UNAVAILABLE",
        message = "CAMERA_UNAVAILABLE: CameraManager not available",
      )

    val cameraId = requestedCameraId ?: resolveCameraId(cm, requestedFacing)
    ?: return GatewaySession.InvokeResult.error(
      code = "CAMERA_NOT_FOUND",
      message = "CAMERA_NOT_FOUND: no camera matching facing=$requestedFacing",
    )

    return try {
      val base64 = capturePhoto(cm, cameraId)
      val json = buildJsonObject {
        put("cameraId", cameraId)
        put("mimeType", "image/jpeg")
        put("base64", base64)
      }
      GatewaySession.InvokeResult.ok(json.toString())
    } catch (e: Throwable) {
      Log.e(TAG, "capturePhoto failed", e)
      GatewaySession.InvokeResult.error(
        code = "CAMERA_CAPTURE_FAILED",
        message = "CAMERA_CAPTURE_FAILED: ${e.message ?: "unknown error"}",
      )
    }
  }

  suspend fun handleClip(p: String?): GatewaySession.InvokeResult {
    return GatewaySession.InvokeResult.error(
      code = "NOT_IMPLEMENTED",
      message = "NOT_IMPLEMENTED: camera.clip video recording is not yet supported",
    )
  }

  private fun hasCameraPermission(): Boolean {
    return ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
        PackageManager.PERMISSION_GRANTED
  }

  private fun resolveCameraId(cm: CameraManager, facing: String): String? {
    val targetFacing = when (facing.lowercase()) {
      "front" -> CameraCharacteristics.LENS_FACING_FRONT
      "back" -> CameraCharacteristics.LENS_FACING_BACK
      "external" -> CameraCharacteristics.LENS_FACING_EXTERNAL
      else -> CameraCharacteristics.LENS_FACING_BACK
    }
    for (id in cm.cameraIdList) {
      try {
        val chars = cm.getCameraCharacteristics(id)
        if (chars.get(CameraCharacteristics.LENS_FACING) == targetFacing) return id
      } catch (_: Throwable) { }
    }
    return cm.cameraIdList.firstOrNull()
  }

  @Suppress("MissingPermission")
  private suspend fun capturePhoto(cm: CameraManager, cameraId: String): String {
    val thread = HandlerThread("CameraCapture").apply { start() }
    val handler = Handler(thread.looper)

    try {
      val chars = cm.getCameraCharacteristics(cameraId)
      val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
      val sizes = map.getOutputSizes(ImageFormat.JPEG)
      val size = sizes.firstOrNull { it.width <= 1920 && it.height <= 1920 }
        ?: sizes.lastOrNull()
        ?: throw IllegalStateException("No JPEG output size available")

      val reader = ImageReader.newInstance(size.width, size.height, ImageFormat.JPEG, 1)

      return withTimeout(SNAP_TIMEOUT_MS) {
        val device = openCamera(cm, cameraId, handler)
        try {
          val jpegBytes = captureWithDevice(device, reader, handler)
          Base64.encodeToString(jpegBytes, Base64.NO_WRAP)
        } finally {
          device.close()
          reader.close()
        }
      }
    } finally {
      thread.quitSafely()
    }
  }

  @Suppress("MissingPermission")
  private suspend fun openCamera(
    cm: CameraManager,
    cameraId: String,
    handler: Handler,
  ): CameraDevice = suspendCancellableCoroutine { cont ->
    cm.openCamera(cameraId, object : CameraDevice.StateCallback() {
      override fun onOpened(camera: CameraDevice) {
        if (cont.isActive) cont.resume(camera)
      }
      override fun onDisconnected(camera: CameraDevice) {
        camera.close()
        if (cont.isActive) cont.resumeWithException(
          RuntimeException("Camera disconnected")
        )
      }
      override fun onError(camera: CameraDevice, error: Int) {
        camera.close()
        if (cont.isActive) cont.resumeWithException(
          RuntimeException("Camera error: $error")
        )
      }
    }, handler)
  }

  private suspend fun captureWithDevice(
    device: CameraDevice,
    reader: ImageReader,
    handler: Handler,
  ): ByteArray = suspendCancellableCoroutine { cont ->
    reader.setOnImageAvailableListener({ ir ->
      val image = ir.acquireLatestImage() ?: return@setOnImageAvailableListener
      try {
        val buffer = image.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        if (cont.isActive) cont.resume(bytes)
      } finally {
        image.close()
      }
    }, handler)

    try {
      val outputConfig = OutputConfiguration(reader.surface)
      val sessionCallback = object : CameraCaptureSession.StateCallback() {
        override fun onConfigured(session: CameraCaptureSession) {
          try {
            val req = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
              addTarget(reader.surface)
              set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
              set(CaptureRequest.JPEG_QUALITY, 85.toByte())
            }
            session.capture(req.build(), null, handler)
          } catch (e: Throwable) {
            if (cont.isActive) cont.resumeWithException(e)
          }
        }
        override fun onConfigureFailed(session: CameraCaptureSession) {
          if (cont.isActive) cont.resumeWithException(
            RuntimeException("Camera session configuration failed")
          )
        }
      }
      val sessionConfig = SessionConfiguration(
        SessionConfiguration.SESSION_REGULAR,
        listOf(outputConfig),
        { it.run() },
        sessionCallback,
      )
      device.createCaptureSession(sessionConfig)
    } catch (e: Throwable) {
      if (cont.isActive) cont.resumeWithException(e)
    }
  }
}
