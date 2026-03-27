package ai.axiomaster.boji.avatar

import kotlin.math.sqrt

data class AvatarPosition(val x: Float, val y: Float) {
    fun distanceTo(other: AvatarPosition): Float {
        val dx = other.x - x
        val dy = other.y - y
        return sqrt(dx * dx + dy * dy)
    }
}
