package ai.axiomaster.bonio.util

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object AppLogger {
  private var logFile: File? = null

  fun init(context: Context) {
    logFile = File(context.filesDir, "bonio.log")
  }

  fun d(tag: String, msg: String) {
    Log.d(tag, msg)
    write("D/$tag: $msg")
  }

  fun i(tag: String, msg: String) {
    Log.i(tag, msg)
    write("I/$tag: $msg")
  }

  fun w(tag: String, msg: String, tr: Throwable? = null) {
    Log.w(tag, msg, tr)
    write("W/$tag: $msg ${tr?.stackTraceToString().orEmpty()}")
  }

  fun e(tag: String, msg: String, tr: Throwable? = null) {
    Log.e(tag, msg, tr)
    write("E/$tag: $msg ${tr?.stackTraceToString().orEmpty()}")
  }

  private fun write(line: String) {
    try {
      val f = logFile ?: return
      val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())
      synchronized(this) {
        f.appendText("[$time] $line\n")
        if (f.length() > 2 * 1024 * 1024) {
          f.writeText("") // simple rotate
        }
      }
    } catch (_: Throwable) {}
  }
}
