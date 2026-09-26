package ai.axiomaster.bonio.avatar

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Installs skin zip packages (local SAF uri or https URL) into filesDir/skins/<id>/.
 * Pipeline: size precheck → safe extraction (SkinPackage) → manifest validation
 * (SkinManifest) → bitmap decode check → atomic swap into place. See
 * docs/design/arch/skin-import-arch-20260926.md.
 */
object SkinImporter {
    private const val TAG = "SkinImporter"

    const val ERR_BAD_URL = "ERR_BAD_URL"
    const val ERR_DOWNLOAD = "ERR_DOWNLOAD"
    const val ERR_SHEET = "ERR_SHEET"
    const val ERR_IO = "ERR_IO"

    sealed class ImportResult {
        data class Success(val skin: SkinItem) : ImportResult()
        data class Failure(val code: String, val detail: String? = null) : ImportResult()
    }

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    /** Copy a content uri into cache (with the size cap applied), then install. */
    suspend fun installFromUri(context: Context, uri: Uri): ImportResult = withContext(Dispatchers.IO) {
        val cache = File(context.cacheDir, "skin_import.zip")
        try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                cache.outputStream().use { output ->
                    val copied = input.copyTo(output, bufferSize = 64 * 1024)
                    if (copied > SkinPackage.MAX_ZIP_BYTES) {
                        return@withContext ImportResult.Failure(SkinPackage.ERR_TOO_LARGE, "selected file exceeds cap")
                    }
                }
            } ?: return@withContext ImportResult.Failure(ERR_IO, "cannot open uri")
            install(context, cache)
        } catch (e: Exception) {
            Log.e(TAG, "installFromUri failed", e)
            ImportResult.Failure(ERR_IO, e.message)
        }
    }

    /** Stream a skin zip from [url] into cache with progress callbacks (0..100), then install. */
    suspend fun installFromUrl(
        context: Context,
        url: String,
        onProgress: (Int) -> Unit = {},
    ): ImportResult = withContext(Dispatchers.IO) {
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            return@withContext ImportResult.Failure(ERR_BAD_URL, "only http(s) links are supported")
        }
        val cache = File(context.cacheDir, "skin_import.zip")
        try {
            val request = Request.Builder().url(url).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return@withContext ImportResult.Failure(ERR_DOWNLOAD, "HTTP ${response.code}")
                }
                val body = response.body ?: return@withContext ImportResult.Failure(ERR_DOWNLOAD, "empty body")
                val total = body.contentLength()
                var copied = 0L
                var lastReported = -1
                cache.outputStream().use { output ->
                    body.byteStream().use { input ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            copied += n
                            if (copied > SkinPackage.MAX_ZIP_BYTES) {
                                return@withContext ImportResult.Failure(SkinPackage.ERR_TOO_LARGE, "download exceeds cap")
                            }
                            if (total > 0) {
                                val pct = (copied * 100 / total).toInt().coerceIn(0, 100)
                                if (pct != lastReported) {
                                    lastReported = pct
                                    onProgress(pct)
                                }
                            }
                            output.write(buf, 0, n)
                        }
                    }
                }
            }
            install(context, cache)
        } catch (e: Exception) {
            Log.e(TAG, "installFromUrl failed", e)
            ImportResult.Failure(ERR_DOWNLOAD, e.message)
        }
    }

    /** Core pipeline: validate then atomically swap filesDir/skins/<id>/. */
    suspend fun install(context: Context, zipFile: File): ImportResult = withContext(Dispatchers.IO) {
        val tmpDir = File(context.cacheDir, "skin_import_tmp")
        try {
            val extracted = SkinPackage.extract(zipFile, tmpDir)

            val manifest = try {
                SkinManifest.parse(extracted.manifestFile.readText())
            } catch (e: SkinManifestException) {
                return@withContext ImportResult.Failure(e.code, e.message)
            }
            val manifestError = manifest.validate()
            if (manifestError != null) return@withContext ImportResult.Failure(manifestError, "manifest rejected")

            // Bitmap-level checks: sheet must decode to exactly the declared grid.
            val sheetOpts = BitmapFactory.Options().apply { inScaled = false }
            val sheet = BitmapFactory.decodeFile(extracted.sheetFile.absolutePath, sheetOpts)
            if (sheet == null) {
                return@withContext ImportResult.Failure(ERR_SHEET, "spritesheet failed to decode")
            }
            val sizeOk = sheet.width == manifest.grid.sheetWidth && sheet.height == manifest.grid.sheetHeight
            sheet.recycle()
            if (!sizeOk) {
                return@withContext ImportResult.Failure(
                    ERR_SHEET,
                    "expected ${manifest.grid.sheetWidth}x${manifest.grid.sheetHeight}, got ${sheetOpts.outWidth}x${sheetOpts.outHeight}"
                )
            }
            extracted.previewFile?.let { preview ->
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(preview.absolutePath, bounds)
                if (bounds.outWidth <= 0 || maxOf(bounds.outWidth, bounds.outHeight) > 1024) {
                    preview.delete()
                }
            }

            // Atomic-ish swap: keep the previous install as .bak until the new one is complete.
            val target = File(File(context.filesDir, "skins"), manifest.id)
            val backup = File(context.filesDir, "skins/.${manifest.id}.bak")
            target.parentFile?.mkdirs()
            backup.deleteRecursively()
            val hadPrevious = target.isDirectory
            if (hadPrevious) target.renameTo(backup)
            try {
                target.mkdirs()
                manifestFileCopy(extracted.manifestFile, File(target, "manifest.json"))
                sheetCopy(extracted.sheetFile, File(target, manifest.spritesheet))
                extracted.previewFile?.let { sheetCopy(it, File(target, it.name)) }
                // Drop any stray files carried over from a previous version.
                target.listFiles()?.forEach { f ->
                    if (f.name != "manifest.json" && f.name != manifest.spritesheet &&
                        (manifest.preview == null || f.name != manifest.preview)
                    ) f.delete()
                }
            } catch (e: Exception) {
                target.deleteRecursively()
                if (hadPrevious) backup.renameTo(target)
                throw e
            }
            backup.deleteRecursively()

            CustomSkinManager.refresh(context)
            val skin = CustomSkinManager.getSkinById(manifest.id)
            ImportResult.Success(skin)
        } catch (e: SkinPackageException) {
            ImportResult.Failure(e.code, e.message)
        } catch (e: SkinManifestException) {
            ImportResult.Failure(e.code, e.message)
        } catch (e: Exception) {
            Log.e(TAG, "install failed", e)
            ImportResult.Failure(ERR_IO, e.message)
        } finally {
            tmpDir.deleteRecursively()
        }
    }

    /** Remove an imported skin; returns false for unknown/built-in ids. */
    suspend fun uninstall(context: Context, id: String): Boolean = withContext(Dispatchers.IO) {
        if (CustomSkinManager.builtinSkins.any { it.id.equals(id, ignoreCase = true) }) return@withContext false
        val target = File(File(context.filesDir, "skins"), id)
        val removed = target.deleteRecursively()
        CustomSkinManager.refresh(context)
        removed
    }

    private fun manifestFileCopy(src: File, dst: File) {
        src.copyTo(dst, overwrite = true)
    }

    private fun sheetCopy(src: File, dst: File) {
        src.copyTo(dst, overwrite = true)
    }
}
