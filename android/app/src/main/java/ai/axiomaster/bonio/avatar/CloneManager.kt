package ai.axiomaster.bonio.avatar

import android.content.Context
import android.content.Intent

object CloneManager {
    const val ACTION_SHOW_CLONE = "ai.axiomaster.bonio.SHOW_CLONE"
    const val ACTION_HIDE_CLONE = "ai.axiomaster.bonio.HIDE_CLONE"
    const val EXTRA_ANIMATION_ASSET = "animation_asset"

    fun showClone(context: Context, animationAsset: String? = null) {
        val intent = Intent(ACTION_SHOW_CLONE).apply {
            setPackage(context.packageName)
            if (animationAsset != null) {
                putExtra(EXTRA_ANIMATION_ASSET, animationAsset)
            }
        }
        context.sendBroadcast(intent)
    }

    fun hideClone(context: Context) {
        val intent = Intent(ACTION_HIDE_CLONE).apply {
            setPackage(context.packageName)
        }
        context.sendBroadcast(intent)
    }
}
