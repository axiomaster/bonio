package ai.axiomaster.bonio.avatar

import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

/**
 * Security-checked extraction of a skin zip into a flat directory.
 * Pure JVM (java.util.zip only) so it is unit-testable.
 *
 * Package contract (docs/design/prd/skin-import-prd-20260926.md §3.1):
 * entries live at the zip root; a single wrapping folder is tolerated and stripped.
 */
object SkinPackage {

  const val ERR_TOO_LARGE = "ERR_TOO_LARGE"
  const val ERR_BAD_ZIP = "ERR_BAD_ZIP"
  const val ERR_NO_MANIFEST = "ERR_NO_MANIFEST"

  const val MAX_ZIP_BYTES: Long = 20L * 1024 * 1024
  const val MAX_ENTRY_BYTES: Long = 10L * 1024 * 1024
  const val MAX_ENTRIES = 16

  private val ALLOWED_ENTRY = Regex(
    "^(manifest\\.json|spritesheet\\.(webp|png)|preview\\.(png|jpg|jpeg|webp))$"
  )

  /** Result of a successful [extract]: paths relative to [outDir]. */
  data class Extracted(
    val manifestFile: File,
    val sheetFile: File,
    val previewFile: File?,
  )

  /**
   * Extract [zipFile] into fresh [outDir]. Throws [SkinPackageException] on any
   * contract or safety violation; [outDir] is cleaned either way.
   */
  fun extract(zipFile: File, outDir: File): Extracted {
    if (zipFile.length() > MAX_ZIP_BYTES) throw SkinPackageException(ERR_TOO_LARGE, "zip exceeds size cap")
    outDir.deleteRecursively()
    outDir.mkdirs()
    try {
      ZipFile(zipFile).use { zip ->
        val rawEntries = zip.entries().asSequence().filter { !it.isDirectory }.toList()
        if (rawEntries.isEmpty()) throw SkinPackageException(ERR_BAD_ZIP, "empty zip")
        if (rawEntries.size > MAX_ENTRIES) throw SkinPackageException(ERR_BAD_ZIP, "too many entries")
        for (entry in rawEntries) checkEntrySafe(entry)

        val names = rawEntries.map { it.name }
        // Strip one common wrapping folder when nothing sits at the root.
        val stripPrefix = run {
          if (names.none { !it.contains('/') }) {
            val firstSegs = names.map { it.substringBefore('/') }.toSet()
            if (firstSegs.size == 1) firstSegs.first() + "/" else ""
          } else ""
        }

        var manifest: File? = null
        var sheet: File? = null
        var preview: File? = null
        for (entry in rawEntries) {
          val rel = entry.name.removePrefix(stripPrefix)
          if (rel.isEmpty()) continue
          if (!ALLOWED_ENTRY.matches(rel)) throw SkinPackageException(ERR_BAD_ZIP, "unexpected entry: ${entry.name}")
          if (entry.size > MAX_ENTRY_BYTES) throw SkinPackageException(ERR_TOO_LARGE, "entry too large: ${entry.name}")
          val dest = File(outDir, rel)
          zip.getInputStream(entry).use { input ->
            dest.outputStream().use { output -> input.copyTo(output, bufferSize = 64 * 1024) }
          }
          when {
            rel == "manifest.json" -> manifest = dest
            rel.startsWith("spritesheet.") -> sheet = dest
            rel.startsWith("preview.") -> preview = dest
          }
        }
        val m = manifest ?: throw SkinPackageException(ERR_NO_MANIFEST, "manifest.json missing")
        val s = sheet ?: throw SkinPackageException(ERR_BAD_ZIP, "spritesheet missing")
        return Extracted(m, s, preview)
      }
    } catch (e: SkinPackageException) {
      outDir.deleteRecursively()
      throw e
    } catch (e: Exception) {
      outDir.deleteRecursively()
      throw SkinPackageException(ERR_BAD_ZIP, "not a readable zip: ${e.message}")
    }
  }

  /** Reject path traversal, absolute paths, backslashes and nested packages. */
  private fun checkEntrySafe(entry: ZipEntry) {
    val name = entry.name
    if (name.isEmpty()) throw SkinPackageException(ERR_BAD_ZIP, "empty entry name")
    if (name.contains('\\')) throw SkinPackageException(ERR_BAD_ZIP, "unsafe entry name: $name")
    if (name.startsWith("/")) throw SkinPackageException(ERR_BAD_ZIP, "absolute entry path: $name")
    if (name.split('/').any { it == ".." }) throw SkinPackageException(ERR_BAD_ZIP, "path traversal: $name")
  }
}

class SkinPackageException(val code: String, message: String) : Exception(message)
