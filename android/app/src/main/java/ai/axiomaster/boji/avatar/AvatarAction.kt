package ai.axiomaster.boji.avatar

enum class AvatarAction {
    None,
    Tapping,
    Swiping,
    LongPressing,
    DoubleTapping,
    Typing,
    Waiting,
    Finishing,
    Launching,
    GoBack,
    TakingPhoto;

    companion object {
        fun fromAgentAction(action: String): AvatarAction {
            val normalized = action.lowercase().replace(" ", "")
            return when (normalized) {
                "tap", "click" -> Tapping
                "swipe", "scroll" -> Swiping
                "longpress" -> LongPressing
                "doubletap" -> DoubleTapping
                "type", "input", "type_name" -> Typing
                "wait", "sleep" -> Waiting
                "finish" -> Finishing
                "launch", "open", "start_app" -> Launching
                "back", "go_back", "press_back" -> GoBack
                "take_photo", "screenshot", "photo" -> TakingPhoto
                else -> None
            }
        }
    }
}
