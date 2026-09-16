package ai.axiomaster.bonio

import ai.axiomaster.bonio.remote.memory.BonioMemo
import ai.axiomaster.bonio.remote.memory.UserProfile
import ai.axiomaster.bonio.remote.memory.UserProfileExtractor
import org.junit.Assert.*
import org.junit.Test

class UserProfileExtractionTest {

    @Test
    fun testExtractL0FixedInfo() {
        val text = "你好，我叫李雷，是个男生，今年28岁，手机号是13812345678。"
        val extracted = UserProfileExtractor.extractFromText(text)

        assertEquals("李雷", extracted.name)
        assertEquals("男", extracted.gender)
        assertEquals("28岁", extracted.ageOrBirthday)
        assertEquals("13812345678", extracted.phone)
    }

    @Test
    fun testExtractL1StableInfo() {
        val text = "我妈叫王丽，我老婆叫韩梅梅。我住在北京市海淀区中关村南大街1号，是一名软件架构师。"
        val extracted = UserProfileExtractor.extractFromText(text)

        assertTrue("Should extract mother", extracted.familyAndFriends.contains("我妈: 王丽"))
        assertTrue("Should extract wife", extracted.familyAndFriends.contains("我老婆: 韩梅梅"))
        assertTrue("Should extract address", extracted.addresses.contains("北京市海淀区中关村南大街1号"))
        assertEquals("软件架构师", extracted.occupation)
    }

    @Test
    fun testMergeProfilesPreservesManualEdits() {
        val base = UserProfile(
            name = "张三",
            gender = "男",
            ageOrBirthday = "30岁",
            phone = ""
        )
        val extracted = UserProfile(
            name = "张三丰",
            gender = "女",
            ageOrBirthday = "31岁",
            phone = "13911112222"
        )

        val merged = UserProfileExtractor.mergeProfiles(base, extracted)

        // Existing values must be preserved
        assertEquals("张三", merged.name)
        assertEquals("男", merged.gender)
        assertEquals("30岁", merged.ageOrBirthday)
        // Blank value in base must be supplemented from extracted
        assertEquals("13911112222", merged.phone)
    }

    @Test
    fun testMergeListStringsDeduplication() {
        val base = UserProfile(
            addresses = "家: 杭州市西湖区文三路",
            familyAndFriends = "母亲: 李华"
        )
        val extracted = UserProfile(
            addresses = "公司: 阿里西溪园区；家: 杭州市西湖区文三路",
            familyAndFriends = "母亲: 李华；妻子: 王丽"
        )

        val merged = UserProfileExtractor.mergeProfiles(base, extracted)

        assertTrue(merged.addresses.contains("家: 杭州市西湖区文三路"))
        assertTrue(merged.addresses.contains("公司: 阿里西溪园区"))
        // Check no duplicate
        val addrCount = merged.addresses.split("；").count { it == "家: 杭州市西湖区文三路" }
        assertEquals(1, addrCount)

        assertTrue(merged.familyAndFriends.contains("母亲: 李华"))
        assertTrue(merged.familyAndFriends.contains("妻子: 王丽"))
        val motherCount = merged.familyAndFriends.split("；").count { it == "母亲: 李华" }
        assertEquals(1, motherCount)
    }

    @Test
    fun testExtractAndMergeFromMemos() {
        val initial = UserProfile(
            name = "张三",
            lastExtractedMemoTime = 1000L
        )
        val memos = listOf(
            BonioMemo(
                id = "m1",
                title = "个人备忘",
                content = "今年25岁，住在上海市浦东新区，职业是产品经理",
                source = "manual",
                createdAt = 2000L,
                tags = listOf("个人")
            ),
            BonioMemo(
                id = "m2",
                title = "旧备忘",
                content = "我叫李四",
                source = "manual",
                createdAt = 500L, // should be skipped because <= 1000L
                tags = emptyList()
            )
        )

        val result = UserProfileExtractor.extractAndMerge(initial, memos, sinceTime = 1000L)

        // Name retained from initial
        assertEquals("张三", result.name)
        // New info extracted from m1
        assertEquals("25岁", result.ageOrBirthday)
        assertTrue(result.addresses.contains("上海市浦东新区"))
        assertEquals("产品经理", result.occupation)
        // Latest memo time updated
        assertEquals(2000L, result.lastExtractedMemoTime)
    }

    @Test
    fun testToPromptContextFormatting() {
        val profile = UserProfile(
            name = "张三",
            gender = "男",
            ageOrBirthday = "30岁",
            phone = "13800000000",
            familyAndFriends = "母亲: 李华；配偶: 王丽",
            addresses = "家: 杭州市西湖区文三路",
            occupation = "软件工程师",
            customFacts = "早起晨跑"
        )

        val prompt = profile.toPromptContext()
        assertTrue(prompt.contains("<用户基础信息(L0/L1)>"))
        assertTrue(prompt.contains("[L0 基础固定信息]"))
        assertTrue(prompt.contains("姓名: 张三"))
        assertTrue(prompt.contains("性别: 男"))
        assertTrue(prompt.contains("年龄/生日: 30岁"))
        assertTrue(prompt.contains("手机号: 13800000000"))
        assertTrue(prompt.contains("[L1 长期稳定信息]"))
        assertTrue(prompt.contains("亲友关系: 母亲: 李华；配偶: 王丽"))
        assertTrue(prompt.contains("住址/常去地点: 家: 杭州市西湖区文三路"))
        assertTrue(prompt.contains("职业身份: 软件工程师"))
        assertTrue(prompt.contains("长期事实: 早起晨跑"))
        assertTrue(prompt.contains("</用户基础信息(L0/L1)>"))
    }
}
