package ai.axiomaster.bonio

import ai.axiomaster.bonio.avatar.SkinAnim
import ai.axiomaster.bonio.avatar.SkinGrid
import ai.axiomaster.bonio.avatar.SkinManifest
import ai.axiomaster.bonio.avatar.SkinManifestException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SkinManifestTest {

    private fun validJson(
        id: String = "ninja-cat",
        grid: String? = null,
        animations: String? = null,
        formatVersion: Int = 1,
    ): String {
        val sb = StringBuilder()
        sb.append("{")
        sb.append("\"format_version\":$formatVersion,")
        sb.append("\"id\":\"$id\",")
        sb.append("\"name\":\"Ninja Cat\",")
        sb.append("\"subtitle\":\"shadow ninja\",")
        sb.append("\"spritesheet\":\"spritesheet.webp\"")
        if (grid != null) sb.append(",\"grid\":$grid")
        if (animations != null) sb.append(",\"animations\":$animations")
        sb.append("}")
        return sb.toString()
    }

    @Test
    fun `valid manifest parses and validates`() {
        val m = SkinManifest.parse(validJson())
        assertEquals("ninja-cat", m.id)
        assertEquals(SkinGrid.DEFAULT, m.grid)
        assertNull(m.validate())
    }

    @Test
    fun `wrong format version rejected`() {
        val m = SkinManifest.parse(validJson(formatVersion = 2))
        assertEquals(SkinManifest.ERR_BAD_MANIFEST, m.validate())
    }

    @Test
    fun `reserved id rejected`() {
        val m = SkinManifest.parse(validJson(id = "cat"))
        assertEquals(SkinManifest.ERR_RESERVED_ID, m.validate())
    }

    @Test
    fun `malformed id rejected`() {
        // uppercase not allowed
        assertEquals(
            SkinManifest.ERR_BAD_MANIFEST,
            SkinManifest.parse(validJson(id = "NinjaCat")).validate()
        )
        // single char too short
        assertEquals(
            SkinManifest.ERR_BAD_MANIFEST,
            SkinManifest.parse(validJson(id = "a")).validate()
        )
    }

    @Test
    fun `oversized grid rejected`() {
        val m = SkinManifest.parse(
            validJson(grid = """{"cols":16,"rows":16,"frame_width":512,"frame_height":512}""")
        )
        assertEquals(SkinManifest.ERR_BAD_MANIFEST, m.validate())
    }

    @Test
    fun `animation row out of grid rejected`() {
        val m = SkinManifest.parse(
            validJson(animations = """{"idle":{"row":9}}""")
        )
        assertEquals(SkinManifest.ERR_BAD_MANIFEST, m.validate())
    }

    @Test
    fun `animation count mismatch rejected`() {
        val m = SkinManifest.parse(
            validJson(animations = """{"idle":{"row":0,"count":3,"frames":[100,100]}}""")
        )
        assertEquals(SkinManifest.ERR_BAD_MANIFEST, m.validate())
    }

    @Test
    fun `omitted frames become uniform 150ms`() {
        val m = SkinManifest.parse(validJson(animations = """{"idle":{"row":2,"count":4}}"""))
        assertNull(m.validate())
        val anim = m.resolvedAnim("idle")
        assertEquals(2, anim.row)
        assertEquals(4, anim.count)
        assertEquals(listOf(150, 150, 150, 150), anim.frames.toList())
    }

    @Test
    fun `overrides win and unmapped states fall back to defaults`() {
        val m = SkinManifest.parse(
            validJson(animations = """{"working":{"row":1,"count":2,"frames":[90,90]}}""")
        )
        assertNull(m.validate())
        assertEquals(SkinAnim(1, 2, intArrayOf(90, 90)), m.resolvedAnim("working"))
        // untouched state uses the built-in table
        assertEquals(SkinManifest.defaultAnim("idle"), m.resolvedAnim("idle"))
    }

    @Test
    fun `unknown state key rejected`() {
        val m = SkinManifest.parse(
            validJson(animations = """{"dancing":{"row":1}}""")
        )
        assertEquals(SkinManifest.ERR_BAD_MANIFEST, m.validate())
    }

    @Test
    fun `garbage json throws with stable code`() {
        try {
            SkinManifest.parse("{not json")
            throw AssertionError("expected SkinManifestException")
        } catch (e: SkinManifestException) {
            assertEquals(SkinManifest.ERR_BAD_MANIFEST, e.code)
        }
    }

    @Test
    fun `default table matches bundled sprite sheet layout`() {
        assertEquals(0, SkinManifest.defaultAnim("idle").row)
        assertEquals(1, SkinManifest.defaultAnim("run_right").row)
        assertEquals(2, SkinManifest.defaultAnim("run_left").row)
        assertEquals(8, SkinManifest.defaultAnim("thinking").row)
        assertEquals(6, SkinManifest.defaultAnim("idle").frames.size)
        assertEquals(280, SkinManifest.defaultAnim("idle").frames.first())
        assertEquals(9, SkinManifest.STATES.size)
    }

    @Test
    fun `non-default grid clamps fallback rows`() {
        val m = SkinManifest.parse(
            validJson(grid = """{"cols":4,"rows":3,"frame_width":192,"frame_height":208}""")
        )
        assertNull(m.validate())
        assertTrue(m.resolvedAnim("thinking").row <= 2)
    }

    @Test
    fun `preview file name must match allowlist`() {
        val json = validJson().replaceFirst(
            "\"spritesheet\"",
            "\"preview\":\"preview.png\",\"spritesheet\""
        )
        assertNotNull(SkinManifest.parse(json))
    }
}
