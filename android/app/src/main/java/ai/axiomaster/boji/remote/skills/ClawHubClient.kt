package ai.axiomaster.boji.remote.skills

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.zip.ZipInputStream

@Serializable
data class ClawHubSearchResult(
    val slug: String = "",
    val displayName: String = "",
    val summary: String = "",
    val score: Double = 0.0,
    val updatedAt: Long = 0,
)

@Serializable
data class ClawHubOwner(
    val handle: String = "",
    val displayName: String = "",
    val image: String? = null,
)

@Serializable
data class ClawHubStats(
    val stars: Int = 0,
    val downloads: Int = 0,
    val installsAllTime: Int = 0,
    val installsCurrent: Int = 0,
    val comments: Int = 0,
    val versions: Int = 0,
)

@Serializable
data class ClawHubVersion(
    val version: String = "",
    val createdAt: Long = 0,
    val changelog: String? = null,
)

@Serializable
data class ClawHubSkillPayload(
    val slug: String = "",
    val displayName: String = "",
    val summary: String = "",
    val stats: ClawHubStats = ClawHubStats(),
    val tags: Map<String, String> = emptyMap(),
)

@Serializable
data class ClawHubSkillDetail(
    val skill: ClawHubSkillPayload = ClawHubSkillPayload(),
    val latestVersion: ClawHubVersion? = null,
    val owner: ClawHubOwner = ClawHubOwner(),
)

@Serializable
private data class SearchResponse(val results: List<ClawHubSearchResult> = emptyList())

@Serializable
private data class VersionFileInfo(
    val path: String = "",
    val size: Long = 0,
    val sha256: String = "",
    val contentType: String = "",
)

@Serializable
private data class VersionDetail(
    val version: String = "",
    val files: List<VersionFileInfo> = emptyList(),
)

@Serializable
private data class VersionResponse(
    val version: VersionDetail? = null,
)

class ClawHubClient {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    suspend fun search(query: String, limit: Int = 20): Result<List<ClawHubSearchResult>> =
        withContext(Dispatchers.IO) {
            try {
                val url = "$BASE_URL/api/search?q=${encode(query)}&limit=$limit"
                val body = fetch(url)
                val resp = json.decodeFromString(SearchResponse.serializer(), body)
                Result.success(resp.results)
            } catch (e: Exception) {
                Log.e(TAG, "search failed", e)
                Result.failure(e)
            }
        }

    suspend fun getSkillDetail(slug: String): Result<ClawHubSkillDetail> =
        withContext(Dispatchers.IO) {
            try {
                val url = "$BASE_URL/api/v1/skills/${encode(slug)}"
                val body = fetch(url)
                val detail = json.decodeFromString(ClawHubSkillDetail.serializer(), body)
                Result.success(detail)
            } catch (e: Exception) {
                Log.e(TAG, "getSkillDetail failed", e)
                Result.failure(e)
            }
        }

    suspend fun downloadSkillContent(slug: String, version: String): Result<String> =
        withContext(Dispatchers.IO) {
            val downloadUrl = "$BASE_URL/api/v1/skills/${encode(slug)}/versions/${encode(version)}/download"
            tryDownloadZip(downloadUrl)?.let { return@withContext Result.success(it) }

            val contentUrl = "$BASE_URL/api/v1/skills/${encode(slug)}/content"
            tryFetchText(contentUrl)?.let { return@withContext Result.success(it) }

            val rawUrl = "$BASE_URL/api/download?slug=${encode(slug)}&version=${encode(version)}"
            tryFetchText(rawUrl)?.let { return@withContext Result.success(it) }

            Result.failure(IOException("Could not download SKILL.md. Visit https://clawhub.ai/$slug to copy content manually."))
        }

    private fun tryDownloadZip(url: String): String? {
        return try {
            val request = Request.Builder().url(url).build()
            val response = client.newCall(request).execute()
            if (!response.isSuccessful) return null
            val bytes = response.body?.bytes() ?: return null
            ZipInputStream(bytes.inputStream()).use { zis ->
                var entry = zis.nextEntry
                while (entry != null) {
                    if (entry.name.endsWith("SKILL.md", ignoreCase = true)) {
                        return zis.bufferedReader().readText()
                    }
                    entry = zis.nextEntry
                }
            }
            null
        } catch (e: Exception) {
            Log.d(TAG, "zip download failed: ${e.message}")
            null
        }
    }

    private fun tryFetchText(url: String): String? {
        return try {
            val request = Request.Builder().url(url).build()
            val response = client.newCall(request).execute()
            if (!response.isSuccessful) return null
            val text = response.body?.string() ?: return null
            if (text.isBlank()) return null
            if (text.trimStart().startsWith("{")) return null
            text
        } catch (e: Exception) {
            Log.d(TAG, "text fetch failed: ${e.message}")
            null
        }
    }

    private fun fetch(url: String): String {
        val request = Request.Builder().url(url).build()
        val response = client.newCall(request).execute()
        if (!response.isSuccessful) {
            throw IOException("HTTP ${response.code}: ${response.message}")
        }
        return response.body?.string() ?: throw IOException("Empty response body")
    }

    private fun encode(value: String): String = java.net.URLEncoder.encode(value, "UTF-8")

    companion object {
        private const val TAG = "ClawHubClient"
        private const val BASE_URL = "https://clawhub.ai"
    }
}
