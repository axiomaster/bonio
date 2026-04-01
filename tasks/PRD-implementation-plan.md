# PRD 实现计划：BoJi 桌面拟人助手

**基于:** PRD-20260329.md  
**日期:** 2026-03-29  

---

## 现状盘点

### 已有能力

| 能力 | 状态 | 说明 |
|------|------|------|
| 悬浮窗 Avatar | ✅ 完成 | FloatingWindowService + LottieAnimationView，全局覆盖 |
| 状态机 | ✅ 完成 | 11 种 AgentState（Idle/Bored/Sleeping/Listening/Thinking/Speaking/Working/Happy/Confused/Angry/Watching） |
| 屏幕移动 | ✅ 完成 | walkTo/runTo/dragTo + ValueAnimator 平滑位移 |
| 主题系统 | ✅ 完成 | ThemeManager + theme.json 映射 Lottie 资产 |
| 语音交互 | ✅ 完成 | SystemTTS 播报 + STT（System/Vosk）识别 |
| 文字气泡 | ✅ 完成 | ScrollView 气泡 + auto-scroll |
| Server 通信 | ✅ 完成 | GatewaySession WebSocket，agent.action.step 事件 |
| 聊天对话 | ✅ 完成 | ChatController + LLM 后端 |
| 来电守卫 | ✅ 基础完成 | 来电检测 + TTS/STT 交互 + 接听/挂断 + 传送门跑位 |
| 通知监听 | ✅ 完成 | DeviceNotificationListenerService + notifications.list/actions |
| 屏幕录制 | ✅ 完成 | MediaProjection + screen.record（MP4） |
| Idle 行为 | ✅ 完成 | IdleBehaviorScheduler 随机漫步 + Idle→Bored→Sleeping 升级 |

### 已有 Lottie 资产（themes/installed/default-cat/）

| 类别 | 文件 | 可用于 PRD 场景 |
|------|------|-----------------|
| **活动状态** | idle, bored, sleeping, listening, thinking, speaking, working, happy, confused, angry, watching | 基础 5 状态 ✅ |
| **运动** | walking, running, dragging | 跑位 ✅ |
| **GUI 动作** | tapping, swiping, longpressing, doubletapping, typing, waiting, finishing, launching, goback, take-photo | 按键/打字 ✅ |
| **过渡** | appear, disappear, idle-to-listening, startdrag, enddrag, error-shake | 出场/消失 ✅ |
| **额外** | jumping, landing, falling | 可复用 |

### 缺失对照 PRD

| PRD 要求 | 缺失资产 | 可行替代方案 |
|----------|----------|-------------|
| 红色警报动画（骚扰电话） | 无专属红光动画 | **复用 angry** + 气泡文字用红色标记 + 代码层给 LottieView 叠加红色 ColorFilter |
| 愤怒挥爪下拍（挂断） | 无专属挥爪 | **复用 tapping** 动画（猫爪拍下），语义接近 |
| 开心按键（接听） | 无专属 | **复用 happy → tapping** 组合（先切 happy 再切 tapping） |
| 睡眼惺忪/打哈欠/疲惫 | sleeping 已有 | ✅ sleeping 可直接使用 |
| 分身（Working 场景） | 无缩小版分身动画 | **复用 working** 动画在第二个小悬浮窗中渲染 |
| 闪烁灯泡气泡（通知） | 无灯泡动画 | 气泡文字 + 💡 emoji + 系统通知音 "叮" |
| 擦汗（打字完成） | finishing 已有 | ✅ finishing 可直接使用 |
| 翻书/读屏（分身） | 无翻书动画 | **复用 working** 或 **thinking** |
| screen.capture（截图） | 仅有 screen.record | 需要新增截图能力（PixelCopy/MediaProjection 单帧） |

---

## 实施阶段规划

### Phase 0：基础补全（前置条件）
> **目标:** 补齐 PRD 所有场景共同依赖的基础能力

#### 0-1. 截图能力 `screen.capture`
- **Android 端:** 在 `ScreenRecordManager` 旁新增 `ScreenCaptureManager`，利用已有 MediaProjection 的 `VirtualDisplay` + `ImageReader` 获取单帧 JPEG/PNG，base64 返回
- **Node 端:** 在 `InvokeCommandRegistry` 注册 `screen.capture` 命令，`ScreenHandler` 增加 `handleCapture`
- **Server 端:** `remote_tools_array()` 中 `screen.capture` 已有定义，格式对齐即可
- **工作量:** ~1 天

#### 0-2. 气泡增强
- 气泡支持颜色参数（红/绿/默认白），用于来电场景
- 气泡支持倒计时数字动态更新
- 气泡淡入淡出 + 弹性缩放动画（PRD 3.全局规范要求）
- **工作量:** ~0.5 天

#### 0-3. 分身窗口（Clone Window）
- `FloatingWindowService` 新增第二个 `WindowManager` 子窗口用于分身显示
- 固定在屏幕右上角，尺寸为本体的 40%
- 支持独立 Lottie 动画（working/thinking）和 appear/disappear 出入场
- 提供 `showClone(state)` / `hideClone()` API
- **工作量:** ~1 天

#### 0-4. 打断机制完善
- PRD 要求：Speaking/Working 状态下点击 avatar 立即打断，进入 Listening
- 当前：长按 avatar 才触发语音
- 修改：单击 avatar → 如果在 Speaking/Working/长任务中 → 打断 TTS → 进入 Listening → 开启 STT
- **工作量:** ~0.5 天

---

### Phase 1：来电守卫增强（场景一）
> **当前状态:** 核心流程已实现，需要视觉表现增强

#### 1-1. 骚扰电话红色警报
- 当 `isSpam=true` 时，给 `LottieAnimationView` 叠加红色半透明 `ColorFilter`（`PorterDuff.Mode.MULTIPLY`），切换到 `angry` 动画
- 气泡用红色背景 + 白色文字："发现骚扰电话！{N}秒后自动挂断喵！"
- 倒计时数字在气泡内动态更新
- 离开骚扰电话状态后清除 ColorFilter
- **工作量:** ~0.5 天

#### 1-2. 挂断/接听的动画细化
- **挂断:** avatar 到达挂断按钮位置 → 切换 `tapping` 动画播放一次 → 执行挂断 → 播 `finishing` → 恢复 idle
- **接听:** avatar 到达接听按钮位置 → 切换 `happy` → 短暂停留 → 切换 `tapping` → 执行接听 → 恢复 idle
- 正常来电：绿色气泡 "主人，XXX 来电话啦，接不接喵？"
- **工作量:** ~0.5 天

#### 1-3. Skill 驱动的来电处理（FUTURE）
- 按 `answer-phone-call.md` 中的技术方案将逻辑迁移到 LLM skill
- 依赖 `AsyncAgentManager` 和 call 专用 tools
- **工作量:** ~2 天（可延后）

---

### Phase 2：通知智能剪报（场景二）
> **当前状态:** 通知监听已实现，缺 LLM 摘要 + UI 面板

#### 2-1. 通知摘要 Skill
- 创建 server-side skill `notification-secretary`
- System prompt：你是 BoJi，一只善于整理信息的猫猫助手。当主人询问或有重要通知时，用大白话总结通知内容
- 注册 `notifications.list` 和 `notifications.actions` 为 LLM 工具
- **工作量:** ~1 天

#### 2-2. 主动通知提醒
- 客户端 `DeviceNotificationListenerService` 在检测到重要通知（微信消息、快递、日程）时主动触发
- 通过 `notifications.changed` 事件送到 server，server 触发 notification skill
- Avatar 气泡显示 💡 + "叮" 通知音（`RingtoneManager.TYPE_NOTIFICATION`）
- **工作量:** ~1 天

#### 2-3. 剪报 UI 面板
- 新增 Compose UI：半透明卡片面板，从底部弹出
- 展示 LLM 摘要结果（标题 + 口语化内容列表）
- 支持点击条目跳转到原始通知 App
- 通过 `FloatingWindowService` 用 `TYPE_APPLICATION_OVERLAY` 窗口展示
- **工作量:** ~1.5 天

---

### Phase 3：屏幕速记（场景三）
> **前置依赖:** Phase 0-1 的 screen.capture

#### 3-1. 截图 + LLM 理解
- 用户长按 avatar + 语音 "记一下" / "帮我存下来"
- 客户端截图 → base64 → 发送到 server 的 vision-capable LLM
- LLM 提取关键信息（店名、地址、价格、菜品等）
- **工作量:** ~1 天

#### 3-2. 备忘录存储
- Server 端新增 `memo.save` 工具（写入 memory store 或本地文件）
- 客户端可在 Chat 页面查看历史备忘
- Avatar 动画流程：Listening → Thinking → Speaking（汇报结果）
- **工作量:** ~1 天

---

### Phase 4：物理级代打字（场景四）
> **当前状态:** 有 typing 动画资产，缺乏输入注入能力

#### 4-1. 文本输入注入
- 方案 A（推荐）：利用 Android `AccessibilityService` 获取当前焦点输入框节点，通过 `Bundle` + `ACTION_SET_TEXT` 注入文字
- 方案 B：通过 ADB `input text` shell 命令（需 root 或 shell 权限）
- **工作量:** ~2 天（AccessibilityService 方案）

#### 4-2. 打字动画编排
- 检测到输入框焦点 → avatar 移动到输入框上方
- 切换 `typing` 动画 → 文字逐字注入（50~100ms/字模拟人类速度）
- 完成后切换 `finishing` 动画 → 恢复 idle → 走回屏幕边缘
- **工作量:** ~1 天

---

### Phase 5：深夜碎碎念（场景五）
> **当前状态:** 有 Idle→Bored→Sleeping 状态链，缺时间/使用量触发

#### 5-1. 屏幕使用监控
- 利用 `UsageStatsManager` 统计连续亮屏时间
- 利用系统时间判断深夜（可配置时段，默认 23:00~06:00）
- 两种触发条件：
  - 凌晨 1 点后仍在频繁使用
  - 连续亮屏超过 2 小时
- **工作量:** ~0.5 天

#### 5-2. 碎碎念行为编排
- **轻度提醒:** avatar 从 Idle 变为 sleeping 动画（打哈欠） + 气泡 "主人，好晚了喵…"
- **强制打断:** 如用户继续使用 → avatar 走到屏幕正中间 → Angry 动画 + 语音播报 "还不睡觉！BoJi 的毛都要掉光了！" → 持续 5 秒 → 叹气（confused）→ 走回边缘
- 每次提醒后有 15 分钟冷却期
- **工作量:** ~1 天

---

### Phase 6：长文代读（场景六）
> **前置依赖:** Phase 0-1 screen.capture + Phase 0-3 分身窗口

#### 6-1. 长文阅读 Skill
- 创建 `smart-reader` skill
- 截取当前屏幕 → LLM 识别为长文 → 自动滚动截取多帧或请求全文
- LLM 生成 3 句话核心摘要
- **工作量:** ~1.5 天

#### 6-2. 分身 + 本体协作
- 触发后：本体说 "没问题，我让小弟去读"
- 右上角弹出分身窗口 → working/thinking 动画循环
- 摘要完成后：本体 Speaking 播报 + 分身播放 disappear 消失
- **工作量:** ~1 天

---

## 优先级与里程碑

| 里程碑 | 阶段 | 工作量估算 | 核心交付 |
|--------|------|-----------|----------|
| **M1** | Phase 0（基础补全） | ~3 天 | 截图、气泡增强、分身窗口、打断机制 |
| **M2** | Phase 1（来电增强） | ~1 天 | 红色警报、挂断/接听动画细化 |
| **M3** | Phase 2（通知剪报） | ~3.5 天 | 通知摘要 Skill + 主动提醒 + 剪报面板 |
| **M4** | Phase 5（深夜碎碎念） | ~1.5 天 | 使用时长监控 + 碎碎念行为 |
| **M5** | Phase 3（屏幕速记） | ~2 天 | 截图理解 + 备忘录 |
| **M6** | Phase 4（代打字） | ~3 天 | AccessibilityService + 打字动画 |
| **M7** | Phase 6（长文代读） | ~2.5 天 | 阅读 Skill + 分身协作 |

**推荐执行顺序:** M1 → M2 → M4 → M3 → M5 → M6 → M7

**理由:**
- M1 是所有后续场景的共同基础
- M2 是已有功能的增量打磨，投入小见效快
- M4（碎碎念）纯客户端逻辑，无服务端依赖，实现简单且情感价值高
- M3（通知）是高频刚需，但需要 LLM skill 和 UI 面板
- M5/M6/M7 依赖 screen.capture 和 AccessibilityService，复杂度较高

---

## Lottie 资产复用策略

由于当前资产无法 100% 覆盖 PRD 所有视觉要求，采用以下策略：

1. **ColorFilter 叠加:** 通过代码给 LottieView 添加颜色滤镜（红色警报、疲惫灰调）
2. **动画组合:** 多个已有动画串联播放（happy → tapping = 开心按键）
3. **状态复用:** 无专属动画的状态复用相近动画（翻书→working，灯泡→confused+emoji）
4. **分身复用:** 分身窗口直接使用 working/thinking 动画的缩小版本
5. **气泡增强:** 用文字/emoji/颜色弥补动画表达力不足（💡灯泡、⚠️警报、😴打哈欠）
6. **未来补充:** 标记需要定制的高优先级动画（红色警报、挥爪拍击），后续由设计师补充

### 需要未来定制的高优先级动画

| 动画 | 用途 | 临时替代 | 优先级 |
|------|------|---------|--------|
| cat-alert.lottie | 骚扰电话红色警报 | angry + 红色 ColorFilter | P1 |
| cat-swipe-down.lottie | 挥爪挂断电话 | tapping | P2 |
| cat-yawning.lottie | 深夜打哈欠 | sleeping | P2 |
| cat-reading.lottie | 分身翻书/读屏 | working | P3 |
| cat-lightbulb.lottie | 有通知时头顶灯泡 | 气泡+💡emoji | P3 |
