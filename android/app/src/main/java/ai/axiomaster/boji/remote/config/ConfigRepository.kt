package ai.axiomaster.boji.remote.config

import ai.axiomaster.boji.remote.gateway.GatewaySession
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.encodeToJsonElement

class ConfigRepository(private val session: GatewaySession) {

    private companion object {
        private const val TAG = "ConfigRepository"
    }

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    /**
     * Get full config from server, including providers metadata
     */
    suspend fun getConfig(): Result<ServerConfig> = withContext(Dispatchers.IO) {
        try {
            val payloadJson = session.request("config.get", null)
            Log.d(TAG, "config.get response: $payloadJson")
            val config = json.decodeFromString(ServerConfig.serializer(), payloadJson)
            Log.d(TAG, "Parsed config: defaultModel=${config.defaultModel}, models=${config.models.size}")
            Result.success(config)
        } catch (e: Exception) {
            Log.e(TAG, "config.get failed: ${e.message}", e)
            Result.failure(e)
        }
    }

    /**
     * Update config on server (saves to hiclaw.json)
     */
    suspend fun setConfig(
        defaultModel: String? = null,
        models: List<ModelConfig>? = null
    ): Result<Boolean> = withContext(Dispatchers.IO) {
        try {
            val params = buildJsonObject {
                if (defaultModel != null) {
                    put("default_model", defaultModel)
                }
                if (models != null) {
                    put("models", json.encodeToJsonElement(models))
                }
            }

            session.request("config.set", params.toString())
            Result.success(true)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
