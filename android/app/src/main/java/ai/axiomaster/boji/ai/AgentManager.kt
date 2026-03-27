package ai.axiomaster.boji.ai

import ai.axiomaster.boji.avatar.AvatarController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

object AgentManager {
    val stateManager = AgentStateManager()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    val avatarController: AvatarController by lazy {
        AvatarController(stateManager, scope)
    }
}
