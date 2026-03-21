package ai.axiomaster.boji.remote.config

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ServerConfig(
    @SerialName("default_model") val defaultModel: String = "",
    val models: List<ModelConfig> = emptyList(),
    val providers: List<ProviderInfo> = emptyList(),
    val gateway: GatewayConfig? = null
)

@Serializable
data class GatewayConfig(
    val port: Int = 8765,
    val host: String = "0.0.0.0",
    val enabled: Boolean = true
)
