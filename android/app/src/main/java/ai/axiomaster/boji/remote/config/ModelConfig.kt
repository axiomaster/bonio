package ai.axiomaster.boji.remote.config

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ModelConfig(
    val id: String,
    val provider: String,
    @SerialName("base_url") val baseUrl: String? = null,
    @SerialName("model_id") val modelId: String? = null,
    @SerialName("api_key") val apiKey: String? = null
)
