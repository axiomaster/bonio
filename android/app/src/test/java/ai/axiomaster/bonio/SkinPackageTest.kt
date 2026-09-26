package ai.axiomaster.bonio

import ai.axiomaster.bonio.avatar.SkinPackage
import ai.axiomaster.bonio.avatar.SkinPackageException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class SkinPackageTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private val manifestJson = """
        {"format_version":1,"id":"ninja-cat","name":"Ninja Cat","subtitle":"n","spritesheet":"spritesheet.webp"}
    """.trimIndent()

    private fun buildZip(vararg entries: Pair<String, ByteArray>): File {
        val zip = File(tmp.root, "skin.zip")
        ZipOutputStream(zip.outputStream()).use { out ->
            for ((name, bytes) in entries) {
                out.putNextEntry(ZipEntry(name))
                out.write(bytes)
                out.closeEntry()
            }
        }
        return zip
    }

    private fun legalEntries() = arrayOf(
        "manifest.json" to manifestJson.toByteArray(),
        "spritesheet.webp" to ByteArray(64) { it.toByte() },
        "preview.png" to ByteArray(16) { 7 },
    )

    @Test
    fun `legal package extracts flat`() {
        val zip = buildZip(*legalEntries())
        val out = tmp.newFolder("out")
        val result = SkinPackage.extract(zip, out)
        assertEquals("manifest.json", result.manifestFile.name)
        assertEquals("spritesheet.webp", result.sheetFile.name)
        assertNotNull(result.previewFile)
        assertTrue(result.manifestFile.isFile)
        assertTrue(result.sheetFile.isFile)
    }

    @Test
    fun `single wrapping folder is stripped`() {
        val zip = buildZip(
            "ninja-cat/manifest.json" to manifestJson.toByteArray(),
            "ninja-cat/spritesheet.webp" to ByteArray(32),
        )
        val out = tmp.newFolder("out2")
        val result = SkinPackage.extract(zip, out)
        assertEquals("manifest.json", result.manifestFile.name)
        assertTrue(File(out, "spritesheet.webp").isFile)
    }

    @Test
    fun `path traversal entry rejected`() {
        val zip = buildZip(
            *legalEntries(),
            "../evil.txt" to ByteArray(4),
        )
        try {
            SkinPackage.extract(zip, tmp.newFolder("out3"))
            throw AssertionError("expected SkinPackageException")
        } catch (e: SkinPackageException) {
            assertEquals(SkinPackage.ERR_BAD_ZIP, e.code)
        }
    }

    @Test
    fun `absolute path entry rejected`() {
        val zip = buildZip(
            *legalEntries(),
            "/abs.txt" to ByteArray(4),
        )
        try {
            SkinPackage.extract(zip, tmp.newFolder("out4"))
            throw AssertionError("expected SkinPackageException")
        } catch (e: SkinPackageException) {
            assertEquals(SkinPackage.ERR_BAD_ZIP, e.code)
        }
    }

    @Test
    fun `unexpected entry rejected`() {
        val zip = buildZip(
            *legalEntries(),
            "readme.txt" to "hello".toByteArray(),
        )
        try {
            SkinPackage.extract(zip, tmp.newFolder("out5"))
            throw AssertionError("expected SkinPackageException")
        } catch (e: SkinPackageException) {
            assertEquals(SkinPackage.ERR_BAD_ZIP, e.code)
        }
    }

    @Test
    fun `missing manifest rejected`() {
        val zip = buildZip(
            "spritesheet.webp" to ByteArray(32),
        )
        try {
            SkinPackage.extract(zip, tmp.newFolder("out6"))
            throw AssertionError("expected SkinPackageException")
        } catch (e: SkinPackageException) {
            assertEquals(SkinPackage.ERR_NO_MANIFEST, e.code)
        }
    }

    @Test
    fun `corrupt zip rejected as bad zip`() {
        val notZip = File(tmp.root, "broken.zip").apply { writeBytes(ByteArray(128) { 0x5a }) }
        try {
            SkinPackage.extract(notZip, tmp.newFolder("out7"))
            throw AssertionError("expected SkinPackageException")
        } catch (e: SkinPackageException) {
            assertEquals(SkinPackage.ERR_BAD_ZIP, e.code)
        }
    }

    @Test
    fun `failed extraction cleans the output directory`() {
        val zip = buildZip("manifest.json" to manifestJson.toByteArray()) // no sheet → fail
        val out = tmp.newFolder("out8")
        try {
            SkinPackage.extract(zip, out)
            throw AssertionError("expected SkinPackageException")
        } catch (e: SkinPackageException) {
            assertTrue(out.listFiles()?.isEmpty() ?: true)
        }
    }
}
