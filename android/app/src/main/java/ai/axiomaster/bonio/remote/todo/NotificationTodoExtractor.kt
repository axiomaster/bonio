package ai.axiomaster.bonio.remote.todo

import android.util.Log
import java.util.regex.Pattern

/**
 * 通知待办抽取引擎：从通知文本中抽取 时间、地点、任务、相关人/机构
 */
object NotificationTodoExtractor {
    private const val TAG = "TodoExtractor"

    // 来源应用名称映射
    private val appMap = mapOf(
        "com.tencent.mm" to "微信",
        "com.tencent.mobileqq" to "QQ",
        "com.alibaba.android.rimet" to "钉钉",
        "com.ss.android.lark" to "飞书",
        "com.eg.android.AlipayGphone" to "支付宝",
        "com.android.mms" to "短信",
        "com.google.android.apps.messaging" to "短信",
        "com.samsung.android.messaging" to "短信",
        "com.miui.smsextra" to "短信",
        "com.huawei.message" to "短信",
        "com.coloros.sms" to "短信",
        "com.jingdong.app.mall" to "京东",
        "com.taobao.taobao" to "淘宝",
        "com.chinamworld.main" to "建设银行",
        "cmb.pb" to "招商银行"
    )

    // 过滤非待办白噪音
    private val noisePhrases = listOf(
        "正在下载", "下载完成", "步数", "已连接", "剩余电量", "运行中", "截屏已保存",
        "收到红包", "拍了拍我", "撤回了一条消息", "哈哈", "收到请回复"
    )

    fun extract(
        packageName: String,
        title: String?,
        text: String?,
        subText: String?,
        category: String? = null,
        postTimeMs: Long = System.currentTimeMillis()
    ): TodoItem? {
        val rawTitle = title?.trim().orEmpty()
        val rawBody = text?.trim().orEmpty()
        val fullContent = "$rawTitle $rawBody ${subText.orEmpty()}".trim()

        if (fullContent.length < 5) return null

        // 噪音过滤
        if (noisePhrases.any { fullContent.contains(it) }) {
            return null
        }

        val appName = appMap[packageName] ?: when {
            packageName.contains("mms", true) || packageName.contains("sms", true) || packageName.contains("message", true) -> "短信"
            else -> rawTitle.ifEmpty { "系统通知" }
        }

        // 1. 尝试信用卡 / 账单 / 贷款还款
        val billTodo = extractBillOrRepayment(rawTitle, rawBody, appName, fullContent, postTimeMs)
        if (billTodo != null) return billTodo

        // 2. 尝试会议 / 日程 / 工作待办
        val meetingTodo = extractMeetingOrSchedule(rawTitle, rawBody, appName, fullContent, postTimeMs)
        if (meetingTodo != null) return meetingTodo

        // 3. 尝试出行 / 高铁 / 航班
        val travelTodo = extractTravel(rawTitle, rawBody, appName, fullContent, postTimeMs)
        if (travelTodo != null) return travelTodo

        // 4. 尝试快递 / 取件码
        val expressTodo = extractExpress(rawTitle, rawBody, appName, fullContent, postTimeMs)
        if (expressTodo != null) return expressTodo

        // 5. 尝试预约 / 挂号 / 体检
        val appointmentTodo = extractAppointment(rawTitle, rawBody, appName, fullContent, postTimeMs)
        if (appointmentTodo != null) return appointmentTodo

        return null
    }

    /** 抽取还款与账单通知 */
    private fun extractBillOrRepayment(
        title: String,
        body: String,
        appName: String,
        full: String,
        postTimeMs: Long
    ): TodoItem? {
        val isBill = full.contains("还款") || full.contains("账单") || full.contains("应还") ||
                full.contains("借款") || full.contains("到期还款") || full.contains("白条") || full.contains("花呗")
        if (!isBill) return null

        // 提取机构/主体
        var person = extractOrgOrPerson(title, body)
        if (person == null) {
            when {
                full.contains("招商银行") || full.contains("招行") -> person = "招商银行"
                full.contains("建设银行") || full.contains("建行") -> person = "建设银行"
                full.contains("工商银行") || full.contains("工行") -> person = "工商银行"
                full.contains("农业银行") || full.contains("农行") -> person = "农业银行"
                full.contains("中国银行") || full.contains("中行") -> person = "中国银行"
                full.contains("京东白条") || full.contains("白条") -> person = "京东白条"
                full.contains("微粒贷") -> person = "微粒贷"
                full.contains("花呗") -> person = "支付宝花呗"
                full.contains("借呗") -> person = "支付宝借呗"
            }
        }

        // 提取金额
        val amountRegex = Pattern.compile("(?:应还款?|金额|还款|欠款|账单)?(?:为|人民币|：|:)?\\s*([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?)\\s*元")
        val amountMatcher = amountRegex.matcher(full)
        val amount = if (amountMatcher.find()) amountMatcher.group(1) else null

        // 提取还款时间
        val dateRegex = Pattern.compile("(?:还款日|到期日|账单日)?(?:为|是|：|:)?\\s*([0-9]{1,2}月[0-9]{1,2}日|[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|明[天日]|今日|今日内|[0-9]{1,2}日)")
        val dateMatcher = dateRegex.matcher(full)
        val time = if (dateMatcher.find()) dateMatcher.group(1) else null

        val taskDesc = buildString {
            if (!person.isNullOrBlank()) append(person).append(" ")
            append("还款")
            if (!amount.isNullOrBlank()) append(" ").append(amount).append("元")
        }

        return TodoItem(
            task = taskDesc,
            time = time,
            location = null,
            person = person,
            sourceApp = appName,
            rawText = full,
            createdAt = postTimeMs
        )
    }

    /** 抽取会议与日程安排 */
    private fun extractMeetingOrSchedule(
        title: String,
        body: String,
        appName: String,
        full: String,
        postTimeMs: Long
    ): TodoItem? {
        val meetingKeywords = listOf("开会", "会议", "评审", "复盘", "讨论", "碰头", "述职", "周报", "汇报", "交周报", "发周报", "答辩", "面试")
        val matchedKeyword = meetingKeywords.find { full.contains(it) } ?: return null

        // 提取时间
        val timeRegex = Pattern.compile("([今明后]天|本周[一二三四五六日天]|下周[一二三四五六日天]|[0-9]{1,2}月[0-9]{1,2}日)?\\s*([早上下午晚间晨]*\\s*[0-9]{1,2}[:：点时][0-9]{0,2}分?前?)")
        val timeMatcher = timeRegex.matcher(full)
        val time = if (timeMatcher.find()) timeMatcher.group(0)?.trim() else null

        // 提取地点
        val locRegex = Pattern.compile("(?:在|到|于)\\s*([A-Za-z0-9一-龥]{2,15}?(?:室|楼|栋|厦|馆|堂|局|站|院|门|厅|会议室|腾讯会议|Zoom|飞书会议|[0-9]{3,4}))|(?<=(?:在|到|于))\\s*([A-Za-z0-9一-龥]{2,12}?)(?=(?:开|召开|举行|进行|碰头))")
        val locMatcher = locRegex.matcher(full)
        val location = if (locMatcher.find()) (locMatcher.group(1) ?: locMatcher.group(2))?.trim() else null

        // 发起人 / 发信人 (优先看 title，或正文里的 "xxx:")
        var person: String? = null
        if (title.isNotBlank() && !title.contains("通知") && !title.contains("系统") && !title.contains("群")) {
            person = title.replace(Regex("[:：].*"), "").trim()
        }

        // 待办任务名
        val task = when {
            full.contains("架构评审") -> "架构评审会"
            full.contains("复盘") -> "项目复盘会"
            full.contains("周报") -> "提交周报"
            full.contains("碰头") -> "碰头会"
            full.contains("开会") || full.contains("会议") -> {
                // 截取会议名称
                val nameMatch = Pattern.compile("([A-Za-z0-9一-龥]{2,10}(?:会|会议|评审|讨论))").matcher(full)
                if (nameMatch.find()) nameMatch.group(1) else "参加会议"
            }
            else -> matchedKeyword
        }

        return TodoItem(
            task = task,
            time = time,
            location = location,
            person = person,
            sourceApp = appName,
            rawText = full,
            createdAt = postTimeMs
        )
    }

    /** 抽取出行与车票/机票 */
    private fun extractTravel(
        title: String,
        body: String,
        appName: String,
        full: String,
        postTimeMs: Long
    ): TodoItem? {
        val isTravel = full.contains("车票") || full.contains("列车") || full.contains("航班") ||
                full.contains("12306") || full.contains("机票") || full.contains("高铁") || full.contains("起飞")
        if (!isTravel) return null

        // 提取车次或航班 (例: G1234, CA1855, 必须以字母开头以避免匹配日期或时间中的数字)
        val trainFlightRegex = Pattern.compile("\\b([GDCKTZ][0-9]{1,4}|[A-Z]{2}[0-9]{3,4})\\b")
        val tfMatcher = trainFlightRegex.matcher(full)
        val code = if (tfMatcher.find()) tfMatcher.group(1) else null

        // 提取时间
        val timeRegex = Pattern.compile("([0-9]{1,2}月[0-9]{1,2}日|[今明后]天)?\\s*([0-9]{1,2}[:：点时][0-9]{2}分?(?:开|起飞)?)")
        val timeMatcher = timeRegex.matcher(full)
        val time = if (timeMatcher.find()) timeMatcher.group(0)?.trim() else null

        // 提取地点 / 车站 / 机场 / 行程区间 (例: 上海虹桥-北京南, 上海虹桥站, 大兴机场)
        val routeRegex = Pattern.compile("([A-Za-z0-9一-龥]{2,8})\\s*[-至到]\\s*([A-Za-z0-9一-龥]{2,8})")
        val routeMatcher = routeRegex.matcher(full)
        val locRegex = Pattern.compile("([A-Za-z0-9一-龥]{2,10}(?:火车站|高铁站|站|机场|航站楼))")
        val locMatcher = locRegex.matcher(full)
        val location = when {
            routeMatcher.find() -> routeMatcher.group(1)?.trim()
            locMatcher.find() -> locMatcher.group(1)?.trim()
            else -> null
        }

        val taskDesc = if (!code.isNullOrBlank()) "乘车/出行 $code" else "出行乘车"

        return TodoItem(
            task = taskDesc,
            time = time,
            location = location,
            person = if (full.contains("12306")) "铁路12306" else null,
            sourceApp = appName,
            rawText = full,
            createdAt = postTimeMs
        )
    }

    /** 抽取快递与取件码 */
    private fun extractExpress(
        title: String,
        body: String,
        appName: String,
        full: String,
        postTimeMs: Long
    ): TodoItem? {
        val isExpress = full.contains("取件码") || full.contains("菜鸟") || full.contains("丰巢") ||
                (full.contains("包裹") && full.contains("取件"))
        if (!isExpress) return null

        // 提取取件码
        val codeRegex = Pattern.compile("(?:取件码|凭|提货码)[：: 为是]*([A-Za-z0-9-]+)")
        val codeMatcher = codeRegex.matcher(full)
        val code = if (codeMatcher.find()) codeMatcher.group(1)?.trim() else null

        // 提取地点/驿站
        val locRegex = Pattern.compile("([A-Za-z0-9一-龥]{2,15}(?:驿站|快递柜|丰巢|菜鸟|代收点|大堂|保安室))")
        val locMatcher = locRegex.matcher(full)
        val location = if (locMatcher.find()) locMatcher.group(1)?.trim() else null

        val taskDesc = buildString {
            append("取快递")
            if (!code.isNullOrBlank()) append(" (取件码: ").append(code).append(")")
        }

        return TodoItem(
            task = taskDesc,
            time = null,
            location = location,
            person = if (full.contains("丰巢")) "丰巢" else if (full.contains("菜鸟")) "菜鸟驿站" else null,
            sourceApp = appName,
            rawText = full,
            createdAt = postTimeMs
        )
    }

    /** 抽取预约/挂号/体检 */
    private fun extractAppointment(
        title: String,
        body: String,
        appName: String,
        full: String,
        postTimeMs: Long
    ): TodoItem? {
        val isAppt = full.contains("预约") || full.contains("挂号") || full.contains("就诊") || full.contains("体检")
        if (!isAppt) return null

        // 提取时间
        val timeRegex = Pattern.compile("([今明后]天|[0-9]{1,2}月[0-9]{1,2}日)?\\s*([早上下午晚间晨]*\\s*[0-9]{1,2}[:：点时][0-9]{0,2}分?)")
        val timeMatcher = timeRegex.matcher(full)
        val time = if (timeMatcher.find()) timeMatcher.group(0)?.trim() else null

        // 提取地点 / 医院
        val locRegex = Pattern.compile("([A-Za-z0-9一-龥]{2,15}(?:医院|门诊|科室|诊所|中心|大厦))")
        val locMatcher = locRegex.matcher(full)
        val location = if (locMatcher.find()) locMatcher.group(1)?.trim() else null

        val taskDesc = when {
            full.contains("就诊") || full.contains("看病") -> "就诊预约"
            full.contains("体检") -> "参加体检"
            full.contains("挂号") -> "门诊就医"
            else -> "预约事项"
        }

        return TodoItem(
            task = taskDesc,
            time = time,
            location = location,
            person = location,
            sourceApp = appName,
            rawText = full,
            createdAt = postTimeMs
        )
    }

    private fun extractOrgOrPerson(title: String, body: String): String? {
        // 查找 【机构名】
        val bracketRegex = Pattern.compile("【(.*?)】")
        val m1 = bracketRegex.matcher(title)
        if (m1.find()) return m1.group(1)?.trim()
        val m2 = bracketRegex.matcher(body)
        if (m2.find()) return m2.group(1)?.trim()
        return null
    }
}
