package ai.axiomaster.bonio.remote.memory

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * 分层记忆架构核心基础档案：
 * - L0 层：用户基础信息（固定，如性别、年龄/生日、姓名、手机号等）；
 * - L1 层：长期稳定信息（如亲属/家属/亲朋好友、住址、职业身份、用户主动记录的长期事实等）；
 *
 * 注：
 * - L2 层为用户最近的动态偏好（会话聚合与近期喜好）；
 * - L3 层为用户记录的原始记忆明细（BonioMemo 列表）。
 */
@Serializable
data class UserProfile(
    // ── L0 基础固定信息 ──
    val name: String = "",
    val gender: String = "",
    val ageOrBirthday: String = "",
    val phone: String = "",

    // ── L1 长期稳定信息 ──
    val familyAndFriends: String = "", // 亲属、家属、亲朋好友 (例: 母亲: 李华; 配偶: 王丽; 儿子: 明明)
    val addresses: String = "",         // 常住地址、工作地点 (例: 家: 杭州市西湖区xxx; 公司: 阿里西溪园区)
    val occupation: String = "",        // 职业与身份 (例: 软件工程师)
    val customFacts: String = "",       // 用户主动记录的长期稳定事实

    val lastExtractedMemoTime: Long = 0L,
    val updatedAt: Long = System.currentTimeMillis()
) {
    /**
     * 判断是否为空档案
     */
    fun isEmpty(): Boolean =
        name.isBlank() && gender.isBlank() && ageOrBirthday.isBlank() && phone.isBlank() &&
        familyAndFriends.isBlank() && addresses.isBlank() && occupation.isBlank() && customFacts.isBlank()

    /**
     * 将 L0 / L1 格式化为大模型问答注入的 Prompt 上下文
     */
    fun toPromptContext(): String {
        val l0Items = mutableListOf<String>()
        if (name.isNotBlank()) l0Items.add("姓名: $name")
        if (gender.isNotBlank()) l0Items.add("性别: $gender")
        if (ageOrBirthday.isNotBlank()) l0Items.add("年龄/生日: $ageOrBirthday")
        if (phone.isNotBlank()) l0Items.add("手机号: $phone")

        val l1Items = mutableListOf<String>()
        if (familyAndFriends.isNotBlank()) l1Items.add("亲友关系: $familyAndFriends")
        if (addresses.isNotBlank()) l1Items.add("住址/常去地点: $addresses")
        if (occupation.isNotBlank()) l1Items.add("职业身份: $occupation")
        if (customFacts.isNotBlank()) l1Items.add("长期事实: $customFacts")

        if (l0Items.isEmpty() && l1Items.isEmpty()) return ""

        val sb = StringBuilder()
        sb.append("<用户基础信息(L0/L1)>\n")
        if (l0Items.isNotEmpty()) {
            sb.append("[L0 基础固定信息]\n")
            l0Items.forEach { sb.append("- ").append(it).append("\n") }
        }
        if (l1Items.isNotEmpty()) {
            sb.append("[L1 长期稳定信息]\n")
            l1Items.forEach { sb.append("- ").append(it).append("\n") }
        }
        sb.append("</用户基础信息(L0/L1)>")
        return sb.toString().trim()
    }

    companion object {
        private val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        fun fromJson(jsonStr: String): UserProfile = runCatching {
            json.decodeFromString<UserProfile>(jsonStr)
        }.getOrDefault(UserProfile())

        fun toJson(profile: UserProfile): String =
            json.encodeToString(profile)
    }
}
