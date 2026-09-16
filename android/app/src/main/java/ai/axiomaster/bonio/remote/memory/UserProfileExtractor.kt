package ai.axiomaster.bonio.remote.memory

import android.util.Log

/**
 * 充电时从用户的原始记录（L3 Memos）中萃取 L0 基础固定信息与 L1 长期稳定信息的提取引擎。
 */
object UserProfileExtractor {
    private const val TAG = "UserProfileExtractor"

    // ── L0 正则模式 ──
    private val NAME_PATTERNS = listOf(
        Regex("""(?:我叫|姓名[：:\s]+|我是)([^\n,，。]{2,6})(?:[，,。\n]|$)"""),
    )

    private val GENDER_PATTERNS = listOf(
        Regex("""(?:性别[：:\s]+)(男|女)"""),
        Regex("""(?:我是|是个|为)?(男生|女生|男士|女士|男人|女人)"""),
    )

    private val AGE_PATTERNS = listOf(
        Regex("""今年\s*(\d{1,3})\s*岁"""),
        Regex("""(?:生日[：:\s]+|出生于\s*)([^\n,，。]{4,20})"""),
    )

    private val PHONE_PATTERNS = listOf(
        Regex("""(?:我的手机|手机号?|电话|联系方式)[：:\s是]*(1[3-9]\d{9})"""),
        Regex("""(?<!\d)(1[3-9]\d{9})(?!\d)"""),
    )

    // ── L1 正则模式 ──
    private val RELATION_PATTERN = Regex(
        """(我妈(?:妈)?|我母亲|我爸(?:爸)?|我父亲|我老婆|我老公|我妻子|我丈夫|我儿子|我女儿|我朋友|闺蜜|兄弟)[：:\s]*(?:叫|是)?([^\n,，。]{2,10})"""
    )

    private val ADDRESS_PATTERNS = listOf(
        Regex("""(?:我家在|我住在|住在|住址[：:\s]+|家庭住址[：:\s]+)([^\n,，。]{4,40})"""),
        Regex("""(?:公司地址[：:\s]+|工作地点[：:\s]+|单位地址[：:\s]+)([^\n,，。]{4,40})"""),
    )

    private val OCCUPATION_PATTERNS = listOf(
        Regex("""(?:我的职业是|职业[：:\s是]+|我的工作是|工作[：:\s是]+|在做|是一名?|是个?)([^\n,，。]{2,20}(?:工程师|架构师|开发|程序员|设计师|产品经理|教师|老师|医生|护士|律师|学生|研究生|主管|总监|经理|销售|运营|分析师|研究员))"""),
    )

    /**
     * 对单条文本内容进行 L0/L1 规则萃取
     */
    fun extractFromText(text: String): UserProfile {
        if (text.isBlank()) return UserProfile()

        var name = ""
        for (pattern in NAME_PATTERNS) {
            val match = pattern.find(text)
            if (match != null) {
                val candidate = match.groupValues[1].trim()
                // 排除常见的代词或非人名词汇
                if (!candidate.contains("一个") && !candidate.contains("一名") &&
                    !candidate.contains("男生") && !candidate.contains("女生") &&
                    !candidate.contains("谁") && !candidate.contains("什么")) {
                    name = candidate
                    break
                }
            }
        }

        var gender = ""
        for (pattern in GENDER_PATTERNS) {
            val match = pattern.find(text)
            if (match != null) {
                val raw = match.groupValues[1].trim()
                gender = when {
                    raw.contains("男") -> "男"
                    raw.contains("女") -> "女"
                    else -> raw
                }
                break
            }
        }

        var ageOrBirthday = ""
        for (pattern in AGE_PATTERNS) {
            val match = pattern.find(text)
            if (match != null) {
                val raw = match.groupValues[1].trim()
                ageOrBirthday = if (raw.all { it.isDigit() }) "${raw}岁" else raw
                break
            }
        }

        var phone = ""
        for (pattern in PHONE_PATTERNS) {
            val match = pattern.find(text)
            if (match != null) {
                phone = match.groupValues[1].trim()
                break
            }
        }

        val familyList = mutableListOf<String>()
        RELATION_PATTERN.findAll(text).forEach { m ->
            val relation = m.groupValues[1].trim()
            val target = m.groupValues[2].trim()
            if (target.isNotBlank()) {
                familyList.add("$relation: $target")
            }
        }

        val addressList = mutableListOf<String>()
        for (pattern in ADDRESS_PATTERNS) {
            pattern.findAll(text).forEach { m ->
                val addr = m.groupValues[1].trim()
                if (addr.isNotBlank() && !addressList.contains(addr)) {
                    addressList.add(addr)
                }
            }
        }

        var occupation = ""
        for (pattern in OCCUPATION_PATTERNS) {
            val match = pattern.find(text)
            if (match != null) {
                occupation = match.groupValues[1].trim()
                break
            }
        }

        return UserProfile(
            name = name,
            gender = gender,
            ageOrBirthday = ageOrBirthday,
            phone = phone,
            familyAndFriends = familyList.joinToString("；"),
            addresses = addressList.joinToString("；"),
            occupation = occupation,
        )
    }

    /**
     * 批量从 Memos 中提取并增量合并到现有 profile 中。
     * 保留现有 profile 中已填写的属性，不被空值覆盖；多值属性（亲友、地址、事实）做去重合并。
     */
    fun extractAndMerge(
        current: UserProfile,
        memos: List<BonioMemo>,
        sinceTime: Long = current.lastExtractedMemoTime
    ): UserProfile {
        val targetMemos = memos.filter { (it.createdAt ?: 0L) > sinceTime }
        if (targetMemos.isEmpty()) {
            return current
        }

        var merged = current
        var latestMemoTime = sinceTime

        for (memo in targetMemos) {
            val fullText = buildString {
                append(memo.title).append("\n")
                append(memo.content).append("\n")
                if (memo.tags.isNotEmpty()) {
                    append(memo.tags.joinToString(" ")).append("\n")
                }
            }

            val extracted = extractFromText(fullText)
            merged = mergeProfiles(merged, extracted)

            val mTime = memo.createdAt ?: 0L
            if (mTime > latestMemoTime) {
                latestMemoTime = mTime
            }
        }

        return merged.copy(
            lastExtractedMemoTime = latestMemoTime,
            updatedAt = System.currentTimeMillis()
        )
    }

    /**
     * 合并两个 UserProfile，以 base 为主，新增补充 supplement 中的非空信息
     */
    fun mergeProfiles(base: UserProfile, supplement: UserProfile): UserProfile {
        val name = if (base.name.isNotBlank()) base.name else supplement.name
        val gender = if (base.gender.isNotBlank()) base.gender else supplement.gender
        val ageOrBirthday = if (base.ageOrBirthday.isNotBlank()) base.ageOrBirthday else supplement.ageOrBirthday
        val phone = if (base.phone.isNotBlank()) base.phone else supplement.phone
        val occupation = if (base.occupation.isNotBlank()) base.occupation else supplement.occupation

        val mergedFamily = mergeListStrings(base.familyAndFriends, supplement.familyAndFriends)
        val mergedAddresses = mergeListStrings(base.addresses, supplement.addresses)
        val mergedFacts = mergeListStrings(base.customFacts, supplement.customFacts)

        return base.copy(
            name = name,
            gender = gender,
            ageOrBirthday = ageOrBirthday,
            phone = phone,
            occupation = occupation,
            familyAndFriends = mergedFamily,
            addresses = mergedAddresses,
            customFacts = mergedFacts,
        )
    }

    private fun mergeListStrings(first: String, second: String): String {
        val items = linkedSetOf<String>()
        if (first.isNotBlank()) {
            first.split(';', '；', '\n').map { it.trim() }.filter { it.isNotBlank() }.forEach { items.add(it) }
        }
        if (second.isNotBlank()) {
            second.split(';', '；', '\n').map { it.trim() }.filter { it.isNotBlank() }.forEach { items.add(it) }
        }
        return items.joinToString("；")
    }
}
