package ai.axiomaster.boji.remote.skills

import ai.axiomaster.boji.remote.gateway.GatewaySession
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class SkillInfo(
    val id: String,
    val name: String = "",
    val description: String = "",
    val enabled: Boolean = true,
    val builtin: Boolean = false,
)

@Serializable
private data class SkillListResponse(val skills: List<SkillInfo> = emptyList())

@Serializable
private data class SkillToggleResponse(val id: String, val enabled: Boolean)

class SkillRepository(private val session: GatewaySession) {

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    suspend fun listSkills(): Result<List<SkillInfo>> = withContext(Dispatchers.IO) {
        try {
            val raw = session.request("skills.list", null)
            Log.d(TAG, "skills.list: $raw")
            val resp = json.decodeFromString(SkillListResponse.serializer(), raw)
            Result.success(resp.skills)
        } catch (e: Exception) {
            Log.e(TAG, "skills.list failed", e)
            Result.failure(e)
        }
    }

    suspend fun enableSkill(id: String): Result<Boolean> = withContext(Dispatchers.IO) {
        try {
            val params = buildJsonObject { put("id", id) }
            val raw = session.request("skills.enable", params.toString())
            val resp = json.decodeFromString(SkillToggleResponse.serializer(), raw)
            Result.success(resp.enabled)
        } catch (e: Exception) {
            Log.e(TAG, "skills.enable failed", e)
            Result.failure(e)
        }
    }

    suspend fun disableSkill(id: String): Result<Boolean> = withContext(Dispatchers.IO) {
        try {
            val params = buildJsonObject { put("id", id) }
            val raw = session.request("skills.disable", params.toString())
            val resp = json.decodeFromString(SkillToggleResponse.serializer(), raw)
            Result.success(!resp.enabled)
        } catch (e: Exception) {
            Log.e(TAG, "skills.disable failed", e)
            Result.failure(e)
        }
    }

    suspend fun installSkill(id: String, content: String): Result<Boolean> = withContext(Dispatchers.IO) {
        try {
            val params = buildJsonObject {
                put("id", id)
                put("content", content)
            }
            session.request("skills.install", params.toString())
            Result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "skills.install failed", e)
            Result.failure(e)
        }
    }

    suspend fun removeSkill(id: String): Result<Boolean> = withContext(Dispatchers.IO) {
        try {
            val params = buildJsonObject { put("id", id) }
            session.request("skills.remove", params.toString())
            Result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "skills.remove failed", e)
            Result.failure(e)
        }
    }

    companion object {
        private const val TAG = "SkillRepository"
    }
}
