# Magic Cue（魔法胶囊）PRD

日期：2026-09-05
来源 PRD：`docs/design/rr/magic-cue-20260905.md`
状态：已确认（触发方式、备忘录来源、匹配引擎三项决策已与用户对齐）

## 1. 背景与目标

Pixel 的 Magic Cue（魔力锦囊）核心卖点不是"提醒"，而是**预判**：跨应用把信息关联起来，
当聊天对象询问某信息（航班、餐厅地址、日程等）时，直接在输入场景旁给出**答案本身**，
一键发送。它解决的是"翻 app 找信息 → 切回聊天 → 手动输入"的上下文切换成本。

Google 官方评测中暴露的教训（我们直接吸收为设计约束）：

- **胶囊里必须是答案本身，不能是入口**。Pixel 被批评最多的就是"只显示'查看日历'而不是航班号"。
- **宁缺毋滥**：识别不确定时不弹胶囊，避免骚扰感。
- **安全边界**：验证码、密码类信息官方刻意不支持，我们也排除。

### Bonio 版目标

双击 avatar 识别屏幕时，如果发现屏幕上的对话正在**询问**联系人、日程、备忘（Bonio 记忆）
等信息，avatar 侧边弹出横条胶囊显示匹配到的答案；点击胶囊把答案填入当前聊天应用的输入框并发出。

### 衡量指标（验收口径）

- 朋友在微信问"张三电话多少" → 双击 → 胶囊显示张三号码 → 点击后聊天框出现号码并发送，全程 ≤ 15s。
- 朋友问"我们几点吃饭" → 胶囊显示日历中的晚餐安排（时间+地点）。
- 朋友问"上次那家餐厅的电话" → 胶囊显示 Bonio 记忆中双击记下的餐厅信息。
- 屏幕没有信息询问时，双击行为与现状一致（记忆/识别），不弹胶囊。

## 2. 用户已确认的决策

| 决策项 | 结论 |
|---|---|
| 触发方式（V1） | 双击 avatar 手动触发；被动自动识别列为后续版本 |
| 备忘录来源（2026-09-05 更新） | **Bonio 自身 memo 存储 + 手机系统备忘录数据库直读**。针对已 root 设备，由 DSH（root 权限进程）直接读取华为备忘录 SQLite 数据库（`/data/app/el2/100/database/com.huawei.hmos.notepad/rdb/notepad.db-dwr`），打破无公开 API 限制，备忘录开关全面解封并启用 |
| 短信数据源（2026-09-05 补充确认） | **精准确认为“读取短信”**（`ohos.permission.READ_MESSAGES`，非发短信）。支持通过 DSH 直接读取短信数据库（`/data/app/el2/100/database/com.ohos.telephonydataability/rdb/sms_mms.db`），满足智能体检索与填发短信内容需求 |
| 通知数据源（2026-09-05 补充确认） | 通过特权权限 `ohos.permission.NOTIFICATION_CONTROLLER`（`system_core` ACL 静态授权）与系统即时通知感知机制，支持对各应用通知的语义感知与即时处理 |
| 匹配引擎 | 云端 LLM，复用 dsh 链路（与现有双击识别一致） |
| 点击胶囊行为 | 填入当前聊天输入框并发送（用户原始需求明确） |
| **Magic Cue 定位** | **默认功能，无功能开关**。双击 avatar 总是先跑 Magic Cue；没有命中时静默降级为原双击记忆流程，不让用户感知到“功能关掉/开起来” |
| **数据源授权展示位置（2026-09-05 重构）** | **从设置页迁移至“自定义页面”（Tab 2, SkillsTab）**底部的**“系统数据授权访问范围”**，统一集中管理 7 项系统数据权限（通讯录、短信、通知、日历、备忘录、图库、文管）；设置页（Tab 3）收敛为底层连接与基础硬件权限，删除冗余 Node Info |
| **页面极简设计规范（2026-09-05 确认）** | **移除所有页面顶部冗余文字说明**（如 Chat 顶部无文字说明、Memory 顶部去除“记忆”大字直接为搜索框、自定义与设置页面顶部去除说明段落） |
| **授权交互与 UI 状态机（2026-09-05 攻坚）** | **标准 user_grant + 独立响应式组件**：自定义组件 `SettingToggleRow` 采用 `@Prop @Watch('onPropChange')` + 异步 `Promise<boolean>` 结果反写，解决 ArkTS 原生 Switch 在权限被拒时 UI 回弹不刷新的缺陷；用户开启时按需弹窗授权，**app 启动绝不自动弹窗** |
| **未授权时的行为** | 数据源未授权 → 该类型不参与推荐（对应命令不广播给 agent），但 Magic Cue 其余数据源照常工作 |

## 3. 范围

### V1 目标（in scope）

1. 双击触发识别 + 信息询问匹配（联系人 / 日历 / 备忘录 / 短信 / 记忆等）
2. 侧边横条胶囊 UI（按 avatar 位置决定弹出方向）
3. 点击胶囊 → 填入输入框 → 发送
4. 自定义页面（Tab 2）的 **系统数据授权访问范围**（通讯录、短信、通知、日历、备忘录、图库、文管共 7 项）集中授权与持久化管理
5. 特权签名与系统权限集成（`system_core` ACL、`tools/hapsigner` 签名）

### 非目标（out of scope，V1 不做）

- **被动自动识别**（后台监听屏幕/通知自动弹胶囊）——后续版本
- 验证码 / 密码 / 支付类信息的识别与填充——安全红线，明确排除
- 桌面端（Flutter）与 Android 端（当前以 HarmonyOS 平台为先锋验证）

## 4. 功能需求

### FR1 触发

- 双击 avatar（现有手势）触发一次 Magic Cue 流程。
- 前置条件：屏幕感知开关开启（现有 `screenAwareness.enabled`）+ 已连接 dsh。Magic Cue 是默认功能，**无独立开关**；其推荐能力随 Settings 中数据源授权情况伸缩（见 FR6）。
- 流程中 avatar 进入 thinking 状态，顶部提示"看看朋友在问什么…"。
- 屏幕上没有信息询问时静默降级：走现有记忆流程（或仅提示"没发现需要的信息"），**不弹胶囊**。

### FR2 屏幕内容获取

- 复用 MSDP `onScreen`（SmartEdge trigger / getPageContent）获取结构化文本（段落、应用名、标题）。
- 纯文本优先（token 省、隐私面小）；当前场景文本不可得时降级用截图。

### FR3 信息询问识别与数据匹配（云端 LLM）

- 新增 dsh 会话 `system:magic-cue`（ephemeral，不污染持久上下文）。
- Prompt 契约：识别"屏幕对话中是否有人**询问**以下类别的信息"，并调用工具取真实数据：
  - 联系人（姓名 → 电话/公司/邮箱）：`bonio_node_invoke(contacts.search)`
  - 日历（时间范围/标题 → 事件）：`bonio_node_invoke(calendar.events)`
  - Bonio 记忆（关键词 → memo）：`memo_list`（增强带 query）
- 输出严格 JSON：`{cues:[{kind, title, content}]}`，最多 3 条；**查不到数据必须返回空**，禁止编造。
- 明确排除：验证码、密码、支付信息，prompt 中写死。

### FR4 胶囊 UI

- 横条胶囊从 avatar 侧边弹出（同一个悬浮窗内渲染，跨应用可见）：
  - avatar 位于屏幕左半边 → 胶囊从 avatar **右侧**弹出；
  - avatar 位于屏幕右半边 → 胶囊从 avatar **左侧**弹出。
- 胶囊内容：图标+类别（联系人/日历/记忆）、答案摘要（姓名+号码 / 时间+地点 / 标题+关键内容）。
- 多条胶囊**上下垂直堆叠**；信息类胶囊最多 2 条，总胶囊数（含跳转胶囊）≤ 3；单条可点击。
- **日历类双胶囊**：命中日历信息时渲染为一组上下两条——
  1. 信息胶囊：具体日历内容（时间+地点+标题），点击 → 填入输入框并发送（FR5）；
  2. 跳转胶囊："查看日历"，点击 → 直接打开系统日历应用（便于查看完整日程/编辑）。
  联系人/记忆类默认只有信息胶囊（后续可按需扩展同样的双胶囊模式）。
- 展示时长：12s 自动收起；点击任意胶囊或超时后整体收起。
- 有 capsule 期间 avatar 状态置 `interacting`/`completed`。

### FR5 填入并发送

- 点击**信息胶囊** → 将 `content` 写入当前聊天应用的输入框并触发发送。
- 主路径（技术方案见架构文档）：bridge（root）通过 uitest 注入：点击输入框 → 输入文本 → 点击发送。
- 降级路径：注入不可用时，复制到剪贴板 + avatar 气泡提示"已复制，请长按输入框粘贴"。
- 目标输入框位置：默认屏幕底部居中（微信等聊天应用输入栏的典型位置），提供一次性校准入口（用户长按胶囊 2s 进入校准模式，点选输入框位置）。
- 点击**跳转胶囊**（"查看日历"）→ 打开系统日历应用（不注入、不发送）；打开后胶囊组收起。

### FR6 设置与系统数据授权访问范围（自定义页面集中管理）

**产品逻辑：** Magic Cue 是 Bonio 的默认能力（双击分析屏幕、命中询问时给出答案），**没有“开/关 Magic Cue”的概念**。原先分散在设置页的权限管理现已重构并升级为**自定义页面（Tab 2, SkillsTab）底部的“系统数据授权访问范围”**——由用户集中控制 Bonio 可以访问哪些个人与系统数据；未授权的数据源不参与推荐，其余已授权项照常工作。

- **页面定位与职责划分**：
  - **自定义页面（Tab 2, SkillsTab）**：用户个性化与数据授权中心，包含 Avatar 皮肤下拉、大模型配置卡片、WeChat 连接、Skills 技能开关，以及底部的**系统数据授权访问范围（7 项开关）**；页面顶部无多余冗余文字说明。
  - **设置页面（Tab 3, SettingsTab）**：基础底层运行设置，包含 DSH 后端连接、全局桌面宠物悬浮窗开关以及系统底层基础硬件权限（定位、语音唤醒、相机、录屏、屏幕感知）；Node Info 区域与业务数据权限全部移除。
- **系统数据授权访问范围清单（7 项）**：
  1. **通讯录**：授权 `ohos.permission.READ_CONTACTS`（user_grant），允许读取联系人信息；
  2. **短信**：确认为**读取短信**（`ohos.permission.READ_MESSAGES`），允许智能体读取和检索短信内容；底层由 DSH 直读 SQLite 数据库；
  3. **通知**：授权 `ohos.permission.NOTIFICATION_CONTROLLER`（`system_core` ACL 静态授权），允许智能体感知各应用即时通知；
  4. **日历**：授权 `ohos.permission.READ_CALENDAR`（user_grant），允许读取日程与日历；
  5. **备忘录**：允许读取和记录便签备忘；支持 Bonio memo 及 DSH 直接读取华为备忘录 SQLite 数据库（`/data/app/el2/100/database/com.huawei.hmos.notepad/rdb/notepad.db-dwr`），开关全面启用；
  6. **图库**：授权 `ohos.permission.READ_IMAGEVIDEO`（user_grant），允许读取相册与图片媒体；
  7. **文管**：授权 `ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY`（user_grant），允许访问文档与本地文件。
- **授权交互与 UI 响应式机制（解决 ArkTS 原生 Switch 缺陷）**：
  - 自定义封装 `@Component struct SettingToggleRow`，绑定 `@Prop @Watch('onPropChange') isOn: boolean` 与内部状态；
  - `onChange` 扩展为 `Promise<boolean>` 异步模式：用户点击开启时触发 `requestPermissionsFromUser` 或后台使能；若用户在系统弹窗中拒绝授权，Toggle 开关平滑反向动画回弹复位，绝不留存错误视觉状态；
  - **EntryAbility 启动零弹窗**：应用冷启动时绝不自动申请任何 `user_grant` 权限，完全按需触发。
- **特权签名与 ACL 配置**：
  - `ohos.permission.READ_MESSAGES` 与 `ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY` 写入 `msdpdemo-system-core-profile.json` 的 `allowed-acls` 与 `restricted-permissions`；
  - 通过 `tools/hapsigner` 签署 `system_core` 权限 profile 与 HAP 包。
- **能力联动**：某数据源授权后才把对应能力/命令广播给 dsh agent；未授权不广播 → agent 查不到 → 该类型 cue 自动缺席。toggle 变更后调 `refreshNodeCapabilities()` 重连 node 会话即时生效。
- **双击兜底**：Magic Cue 无命中时静默降级为原双击记忆流程（非死路、不报错）。

## 5. 数据源可行性（调研结论）

| 数据源 | 可行性 | API / 权限 / 数据路径 | 备注 |
|---|---|---|---|
| 联系人 | ✅ | `@ohos.contact` queryContacts 等；`READ_CONTACTS`（**NORMAL 级 user_grant**，系统设置可见可 revoke） | 标准运行时弹窗授权，`contacts.search` 模糊匹配 |
| 日历 | ✅ | `@ohos.calendarManager` getEvents；`READ_CALENDAR`（normal user_grant）；`calendar.events` | 标准运行时弹窗授权，默认 ±7 天，支持双胶囊（信息+跳转系统日历） |
| 备忘录 | ✅ | Bonio 本地 `memo_list` + 华为系统备忘录数据库直读（`/data/app/el2/100/database/com.huawei.hmos.notepad/rdb/notepad.db-dwr`） | **2026-09-05 全面解封**：DSH root 直接读取 SQLite 数据库，无需公开 API 即可读取便签待办 |
| 短信读取 | ✅ | `ohos.permission.READ_MESSAGES`（`system_basic`，声明于 profile `allowed-acls`） + Telephony SQLite 直读（`/data/app/el2/100/database/com.ohos.telephonydataability/rdb/sms_mms.db`） | **2026-09-05 精准落地**：确认为读取短信，DSH root 数据库直读彻底解决商用 PrivacyCenter 拦截弹窗问题 |
| 通知感知 | ✅ | `ohos.permission.NOTIFICATION_CONTROLLER`（`system_core` ACL 静态授权） + `NotificationSubscriberExtensionAbility` | **2026-09-05 落地**：系统级通知感知，支持来信与各应用通知语义分析 |
| 图库 | ✅ | `@ohos.file.picker` / `READ_IMAGEVIDEO`（user_grant） | 标准运行时授权，支持读取相册图片多媒体 |
| 文管 | ✅ | `ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY`（user_grant / ACL） + DSH 本地文件系统全盘访问 | 访问本地文档与文件 |

## 6. 隐私

- 屏幕文本 + 检索到的联系人/日历/memo 数据会一并送云端 LLM（DeepSeek）做匹配——已与用户确认接受（与现有双击识别同链路）。
- magic-cue 会话为 ephemeral，匹配原始数据不进入持久会话历史。
- 排除验证码/密码/支付类信息（prompt 硬约束 + PRD 红线）。

## 7. 交互文案（草案）

- 识别中："看看朋友在问什么…"
- 命中："找到啦，点击就能发～"
- 未命中："没发现朋友在问什么信息～"（轻提示，不打扰）
- 降级复制："已复制，长按输入框粘贴发送～"

## 8. 验收标准

1. 微信聊天中朋友询问联系人电话/日程/记忆内容三类场景，双击后 15s 内出现正确胶囊（真机验证）。
2. 日历命中时出现上下排列的双胶囊：信息胶囊 + "查看日历"跳转胶囊；点跳转胶囊能打开系统日历应用。
3. 胶囊弹出方向随 avatar 位置正确翻转（左/右各验证一次）。
4. 点击信息胶囊后文本出现在聊天输入框并自动发送（主路径真机验证；降级路径可演示）。
5. 无询问场景不弹胶囊，双击记忆功能回归正常。
6. 数据源未授权时该类型不推荐且无崩溃无静默失败；无任何数据源授权时 Magic Cue 仍能工作（memo），双击降级记忆流程正常。
7. 胶囊 12s 自动收起，不遮挡 avatar，不影响拖动 avatar。

## 9. 开放问题

- 目标聊天应用以微信为主，其他应用（QQ、短信）的输入框位置兼容性——V1 用默认底部居中+校准，不逐应用适配。
- 被动触发（Pixel 原版形态）的产品化节奏——依赖本次手动版验证价值后另立 PRD。