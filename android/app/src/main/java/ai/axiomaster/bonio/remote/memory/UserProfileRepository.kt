package ai.axiomaster.bonio.remote.memory

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 本地持久化与管理 L0 / L1 用户基础档案的仓库。
 * 存储路径：context.filesDir/user_profile.json
 */
class UserProfileRepository(
    private val context: Context,
    private val scope: CoroutineScope
) {
    private val storageFile: File by lazy {
        File(context.filesDir, "user_profile.json")
    }

    private val _profile = MutableStateFlow(UserProfile())
    val profile: StateFlow<UserProfile> = _profile.asStateFlow()

    init {
        loadFromDisk()
    }

    private fun loadFromDisk() {
        scope.launch(Dispatchers.IO) {
            try {
                if (storageFile.exists()) {
                    val content = storageFile.readText()
                    val loaded = UserProfile.fromJson(content)
                    _profile.value = loaded
                    Log.i(TAG, "Loaded UserProfile: name=${loaded.name}, updated=${loaded.updatedAt}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load UserProfile from disk", e)
            }
        }
    }

    fun saveProfile(newProfile: UserProfile) {
        val updated = newProfile.copy(updatedAt = System.currentTimeMillis())
        _profile.value = updated
        scope.launch(Dispatchers.IO) {
            try {
                storageFile.writeText(UserProfile.toJson(updated))
                Log.i(TAG, "Saved UserProfile: name=${updated.name}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save UserProfile to disk", e)
            }
        }
    }

    fun updateProfile(transform: (UserProfile) -> UserProfile) {
        val updated = transform(_profile.value).copy(updatedAt = System.currentTimeMillis())
        saveProfile(updated)
    }

    /**
     * 充电时或手动触发时调用：从 Memos 中萃取提炼 L0 / L1 实体并增量合并
     */
    suspend fun extractFromMemos(memos: List<BonioMemo>, forceAll: Boolean = false): UserProfile = withContext(Dispatchers.IO) {
        val current = _profile.value
        val sinceTime = if (forceAll) 0L else current.lastExtractedMemoTime
        val merged = UserProfileExtractor.extractAndMerge(current, memos, sinceTime)
        if (merged != current) {
            saveProfile(merged)
            Log.i(TAG, "Successfully extracted & merged UserProfile from memos. Name=${merged.name}, Family=${merged.familyAndFriends}")
        } else {
            Log.d(TAG, "No new entities extracted from memos (memos count=${memos.size})")
        }
        merged
    }

    companion object {
        private const val TAG = "UserProfileRepository"
    }
}
