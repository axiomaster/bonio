package ai.axiomaster.bonio

import ai.axiomaster.bonio.remote.todo.NotificationTodoExtractor
import org.junit.Assert.*
import org.junit.Test

class NotificationTodoExtractorTest {

    @Test
    fun testExtractCmbCreditCardBill() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.android.mms",
            title = "【招商银行】",
            text = "您的信用卡当期账单为人民币5,800.00元，还款日为09月25日。",
            subText = null
        )

        assertNotNull("Should extract credit card bill todo", todo)
        assertEquals("招商银行", todo!!.person)
        assertEquals("09月25日", todo.time)
        assertTrue("Task should contain repayment and amount", todo.task.contains("招商银行") && todo.task.contains("还款"))
        assertEquals("短信", todo.sourceApp)
    }

    @Test
    fun testExtractCcbLoanRepayment() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.android.mms",
            title = "【建设银行】",
            text = "尊敬的客户，您尾号1234的快贷于09月20日需还款1,200.50元，请确保账户余额充足。",
            subText = null
        )

        assertNotNull("Should extract CCB repayment todo", todo)
        assertEquals("建设银行", todo!!.person)
        assertEquals("09月20日", todo.time)
        assertTrue("Task should describe repayment", todo.task.contains("还款"))
    }

    @Test
    fun testExtractWeChatMeeting() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.tencent.mm",
            title = "李主管",
            text = "明天上午10点在A座302开架构评审会，请准时参加",
            subText = null
        )

        assertNotNull("Should extract meeting todo", todo)
        assertEquals("架构评审会", todo!!.task)
        assertEquals("A座302", todo.location)
        assertEquals("李主管", todo.person)
        assertEquals("微信", todo.sourceApp)
        assertTrue("Time should match tomorrow 10am", todo.time?.contains("10点") == true)
    }

    @Test
    fun testExtractTrainTicket() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.android.mms",
            title = "【铁路12306】",
            text = "您已购9月18日14:30发车G1234次列车，上海虹桥-北京南，请提前进站乘车。",
            subText = null
        )

        assertNotNull("Should extract travel todo", todo)
        assertTrue("Task should contain G1234", todo!!.task.contains("G1234"))
        assertEquals("上海虹桥", todo.location)
        assertEquals("铁路12306", todo.person)
        assertTrue("Time should contain 14:30", todo.time?.contains("14:30") == true)
    }

    @Test
    fun testExtractExpressDelivery() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.android.mms",
            title = "【菜鸟驿站】",
            text = "您的包裹已到菜鸟驿站（科技园店），请凭取件码 3-2-1004 及时领取。",
            subText = null
        )

        assertNotNull("Should extract express todo", todo)
        assertTrue("Task should contain package and code", todo!!.task.contains("取快递") && todo.task.contains("3-2-1004"))
        assertEquals("菜鸟驿站", todo.person)
    }

    @Test
    fun testIgnoreChatNoise() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.tencent.mm",
            title = "张三",
            text = "哈哈哈哈太好笑了，晚上一起吃鸡啊！",
            subText = null
        )

        assertNull("Should ignore chat noise without todo schedule", todo)
    }

    @Test
    fun testIgnoreDownloadNoise() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.android.providers.downloads",
            title = "下载管理器",
            text = "正在下载 update.apk (45%)",
            subText = null
        )

        assertNull("Should ignore download notification", todo)
    }

    @Test
    fun testExtractHuabeiAndBaitiao() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.eg.android.AlipayGphone",
            title = "花呗",
            text = "9月账单已出，还款日为9月20日，本期应还款2310.50元。",
            subText = null
        )

        assertNotNull("Should extract Huabei bill", todo)
        assertEquals("支付宝花呗", todo!!.person)
        assertEquals("9月20日", todo.time)
        assertTrue("Task should mention repayment", todo.task.contains("还款"))
    }

    @Test
    fun testExtractHospitalAppointment() {
        val todo = NotificationTodoExtractor.extract(
            packageName = "com.tencent.mm",
            title = "仁济医院",
            text = "提醒您，您已预约明天上午9:30在仁济医院口腔科就诊，请提前取号。",
            subText = null
        )

        assertNotNull("Should extract appointment", todo)
        assertEquals("就诊预约", todo!!.task)
        assertEquals("仁济医院", todo.location)
    }

    @Test
    fun testTodoItemJsonSerialization() {
        val original = ai.axiomaster.bonio.remote.todo.TodoItem(
            task = "招商银行还款",
            time = "09月25日",
            location = "线上",
            person = "招商银行",
            sourceApp = "短信",
            rawText = "测试原始通知文本"
        )

        val json = original.toJsonObject()
        val restored = ai.axiomaster.bonio.remote.todo.TodoItem.fromJsonObject(json)

        assertEquals(original.id, restored.id)
        assertEquals(original.task, restored.task)
        assertEquals(original.time, restored.time)
        assertEquals(original.location, restored.location)
        assertEquals(original.person, restored.person)
        assertEquals(original.sourceApp, restored.sourceApp)
        assertEquals(original.rawText, restored.rawText)
        assertEquals(original.isCompleted, restored.isCompleted)
    }
}
