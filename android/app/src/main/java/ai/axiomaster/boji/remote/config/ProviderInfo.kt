package ai.axiomaster.boji.remote.config

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProviderInfo(
    val id: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("requires_api_key") val requiresApiKey: Boolean = true,
    @SerialName("default_base_url") val defaultBaseUrl: String = ""
)
