# Magic Cue 架构与开发方案

日期：2026-09-05
来源：`docs/design/prd/magic-cue-prd-20260905.md`（决策：双击手动触发 / Bonio memo / 云端 LLM 匹配）

## 1. 现状挂钩点（调研结论）

| 关注点 | 现有基础 | 位置 |
|---|---|---|
| 双击触发 | `handleTap()` 双击分支 | `harmonyos/entry/src/main/ets/pages/FloatWindowPage.ets:457` |
| 屏幕文本 | MSDP SmartEdge trigger / `getPageContent`（结构化段落+应用名+标题） | `system/MsdpScreenAwarenessManager.ets`（`triggerSmartEdge` L142、`captureContext` L121） |
| 悬浮窗 | `TYPE_FLOAT` 系统级悬浮窗 300×348px，可触摸、覆盖其他应用，可 resize/moveTo | `common/FloatWindowManager.ets`（位置态 `windowX/Y`） |
| 会话样板 | companion-memory 的 chat.send + final 等待模式 | `node/CompanionMemoryController.ets`（`startActive` L241、`handleGatewayEvent` L196） |
| 设备命令框架 | node invoke 分发 + bridge `bonio_node_invoke` 工具 | `node/InvokeDispatcher.ets:98`、`dsh-plugins/bonio-bridge/src/driver.ts:600` |
| memo 存储 | bridge 侧 `memo.list` RPC + `memo_list` 工具（无 query 参数） | `dsh-plugins/bonio-bridge/src/memo_store.ts:204`、`gateway.ts:328` |
| 输入注入 | `SIMULATE_USER_INPUT` 已声明已授予但**零使用**；注入 API 需 `INJECT_INPUT_EVENT`；dsh 侧有 root 的 `/bin/uitest` 实操先例（phone-use-harmonyos skill） | `module.json5:77`、`tools/skills-device/phone-use-harmonyos-SKILL.md` |
| 备忘录数据 | DSH (root) 直读华为备忘录 SQLite 数据库（无需公开 API，已实测验证） | `/data/app/el2/100/database/com.huawei.hmos.notepad/rdb/notepad.db-dwr` |
| 短信数据 | DSH (root) 直读 Telephony SQLite 数据库 + `READ_MESSAGES` 声明 | `/data/app/el2/100/database/com.ohos.telephonydataability/rdb/sms_mms.db` |
| 通知感知 | `NOTIFICATION_CONTROLLER`（`system_core` ACL 静态授权）系统级即时通知感知 | `msdpdemo-system-core-profile.json`、`module.json5` |
| 图库/文管 | `READ_IMAGEVIDEO` / `READ_WRITE_DOCUMENTS_DIRECTORY`（user_grant + ACL） | `module.json5`、profile allowed-acls |

**数据源与权限体系建设**：联系人/日历/备忘录/短信/通知/图库/文管等 7 项数据源授权与读取通道、magic-cue 会话与 prompt、胶囊 UI、
注入通道、memo 查询参数与 SQLite 数据库直读桥接。

## 2. 总体流程

```
双击 avatar (FloatWindowPage.handleTap)
  ├─ 屏幕感知关闭/Magic Cue 关关未开 → 现有行为（记忆流程），流程结束
  └─ MagicCueController.run()
       1. MsdpScreenAwarenessManager.triggerSmartEdge()      → 屏幕文本+应用名
       2. chat.send(sessionKey='system:magic-cue', prompt, 附件=屏幕文本)
          └─ dsh agent（ephemeral，标准 preset）
               ├─ 判定"是否有人在询问 X"（无 → 直接返回空 cues，不调工具）
               ├─ 调取已授权数据源工具：
               │    - contacts.search / calendar.events / memo_list
               │    - DSH 直读 SQLite 备忘录 / 短信库
               │    - 通知感知事件
               │    （node.invoke.request → app 新 handler / DSH 本地直读 → node.invoke.result）
               └─ 严格 JSON: {"cues":[{"kind","title","content"}]}   ≤3 条
       3. app 收 chat final → 解析 JSON
          ├─ cues 空 → 气泡"没发现朋友在问什么～"，结束
          └─ 有 → FloatWindowManager 动态加宽窗口 → 渲染侧边胶囊
       4. 用户点击胶囊 → CueInjector.apply(content)
          ├─ 主路径: gateway RPC 'cue.inject' → bridge(root) exec /bin/uitest
          │     点击输入框(校准点) → 输入文本 → 点击发送键
          └─ 降级: pasteboard 复制 + 气泡"已复制，长按粘贴发送"
       5. 12s 超时/点击后 → 收起胶囊 → 窗口还原 300×348
```

## 3. 模块设计

### 3.1 App：`MagicCueController`（新增，`node/MagicCueController.ets`）

仿 `CompanionMemoryController`：
- `run(screenPayload: string): Promise<Cue[]>` —— 发 `chat.send`（sessionKey `system:magic-cue`，
  thinking low，idempotencyKey `magic-cue-<ts>`），在 `handleGatewayEvent` 里按 sessionKey 过滤
  `chat` final，解析 `parseCues()`（brace-slice JSON，容错同 companion-memory）。
- prompt 构造见 §3.3；屏幕文本放正文，不传截图（文本缺失才附截图，复用 companion-memory 的附件路径）。
- driver 侧对 `system:magic-cue` 与 companion-memory 同样按 ephemeral 处理
  （`driver.ts` `_run` 的 ephemeral 条件加入该 key）。

### 3.2 App / DSH：数据源实现（7 项核心系统数据源）

新增 `node/handlers/ContactsHandlerImpl.ets`、`CalendarHandlerImpl.ets`，结合 DSH root 底层直接数据库访问，注册进
`InvokeDispatcher.handleInvoke()`、`ProtocolConstants.ets`、`ConnectionManager.buildInvokeCommands()`
（各数据源经用户授权开启后才广播对应命令，未授权时 agent 自然收不到能力广播或收 `UNSUPPORTED_COMMAND`，prompt 已约束兜底）。

1. **`contacts.search`（通讯录）**：`{query: string, limit?: number=5}` → `{contacts: [{name, phones: string[], org?, emails?}]}`
   - `@ohos.contact.queryContacts()` 全量拉取后本地按姓名/拼音前缀/包含匹配；
   - 权限 `ohos.permission.READ_CONTACTS`（NORMAL 级 user_grant），在自定义页面 Toggle 开启时标准弹窗授权。
2. **`calendar.events`（日历）**：`{fromTs?, toTs?, titleQuery?, limit?=10}` → `{events: [{title, startTs, endTs, allDay, location?}]}`
   - `@ohos.calendarManager.getCalendarManager(ctx)` → `Calendar.getEvents(EventFilter.filterByTime / filterByTitle)`；
   - 默认时间窗：今天起 ±7 天；titleQuery 命中时放宽到 ±90 天；
   - 权限 `ohos.permission.READ_CALENDAR`（NORMAL 级 user_grant）。
3. **备忘录（便签待办）**：
   - **Bonio 本地 memo**：`memo_store.listMemos` + `memo_list` 工具；
   - **华为系统备忘录（2026-09-05 全面解封）**：在 root 设备上，DSH 守护进程直接读取 SQLite 数据库文件：
     `/data/app/el2/100/database/com.huawei.hmos.notepad/rdb/notepad.db-dwr`；
     无需依赖未开放的系统 API，彻底打通系统备忘录检索。
4. **短信（读取与检索）**：
   - **需求确认为读取短信**（非发短信）；
   - 权限 `ohos.permission.READ_MESSAGES`（`system_basic`，已写入 profile `allowed-acls` 与 `restricted-permissions`）；
   - 底层由 DSH 直接读取 Telephony SQLite 数据库：
     `/data/app/el2/100/database/com.ohos.telephonydataability/rdb/sms_mms.db`，
     实现验证码、业务通知、历史短信的快速结构化检索。
5. **通知感知**：
   - 权限 `ohos.permission.NOTIFICATION_CONTROLLER`（`system_core` ACL 静态授权）；
   - 系统级即时通知监听与感知，支持各应用即时消息与系统通知语义提取。
6. **图库（相册多媒体）**：
   - 权限 `ohos.permission.READ_IMAGEVIDEO`（user_grant），标准运行时授权，支持读取相册图片与媒体数据。
7. **文管（本地文件与文档）**：
   - 权限 `ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY`（user_grant / ACL），支持访问本地文档与下载目录。

### 3.3 Prompt 契约（`system:magic-cue`）

```
你是 Bonio 的 Magic Cue 助手。以下是手机当前屏幕的内容（应用：{bundleName}，标题：{title}）：
<屏幕文本>

判断屏幕上的对话是否有人在【询问】以下类别的信息：
- 联系人（某人的电话/公司/邮箱）
- 日程安排（某天/某个活动的时间和地点）
- 记忆（以前记下的内容，如某家餐厅、某个订单、某个地址）

规则：
1. 只处理"询问"，不是陈述。没人问 → cues 为空数组。
2. 需要数据时调用工具取真实数据：contacts.search（联系人）、calendar.events（日历）、
   memo_list（记忆，用 query 关键词过滤）。工具查不到 → 不产出该 cue，禁止编造。
3. 排除：验证码、密码、支付/银行卡信息 —— 一律忽略。
4. 最多 3 条。content 是准备直接发给对方的完整答案文本（如"张三：138xxxx8888"），
   不是入口或"去日历查看"。
5. 只输出 JSON：{"cues":[{"kind":"contact|calendar|memo","title":"…","content":"…"}]}
```

### 3.4 Bridge：memo 查询增强

- `memo_store.listMemos(limit, query?)`：title/content/tags 不区分大小写子串匹配（与 MemoryTab 一致）。
- `gateway.ts` `handleMemoList` 透传 `query`；`memo_list` 工具加 `query` 参数。
- 顺带修正 `bonio_node_invoke` 描述，命令列表与实际一致（去掉 `input.type`/`system.notify` 等虚报）。

### 3.5 Bridge：`cue.inject` RPC（新增 gateway 方法）

`cue.inject {text: string}` → bridge（root）执行注入序列，返回 `{ok, detail?}`：

```
/bin/uitest uiInput click <inputX> <inputY>     # 校准过的输入框点
sleep ~400ms
/bin/uitest uiInput inputText ...               # 精确子命令以 spike 为准（文本注入）
sleep ~300ms
/bin/uitest uiInput click <sendX> <sendY>       # 发送键 = 输入点右侧偏移
```

- 注入坐标由 app 端传入（app 维护校准点，见 §3.6），bridge 只执行。
- 文本含空格/引号 → 参数转义或走临时文件。
- 超时 10s；失败返回明确 code（`UITEST_FAILED`），app 走降级路径。
- 备选实现（spike 二选一）：app 内直接用 `@ohos.multimodalInput.inputEventClient` 键盘事件
  （剪贴板写入 + Ctrl+V 注入 + Enter），需补 `INJECT_INPUT_EVENT` 权限声明。**优先 uitest**
  （无需新权限、phone-use 已验证 root 下可用；中文输入剪贴板+粘贴在微信的兼容性是主要不确定点）。

### 3.6 App：胶囊 UI（`FloatWindowPage` 扩展）

- `MagicCueState`：`cues[]`、`visible`、`side: 'left'|'right'`、`inputPoint: {x, y}`。
- 弹出时 `FloatWindowManager` 动态加宽：胶囊宽 `CAPSULE_W=420px`（物理 px，与现有常量同单位）
  - side=right（avatar 在左）：window 原点不变，宽 300→300+gap+420；
  - side=left（avatar 在右）：原点 x -= (gap+420)，宽同上，clamp ≥0；
  - avatar 定位于窗口内**固定锚点**，视觉不移动；收起时还原 300×348。
- side 判定：`windowX + 150 < screenWidth / 2 ? 'right' : 'left'`（屏幕中线与 avatar 中心比较）。
- 胶囊条目：类别图标 + 标题（如"张三的电话"）+ content 摘要（单行截断，长按看全文可后置）；
  信息胶囊最多 2 条、总胶囊数 ≤3，**上下垂直堆叠**；整体 12s 自动收起。
- **日历类双胶囊（app 侧派生，不改 prompt 契约）**：`kind === 'calendar'` 的 cue 渲染为一组两条：
  1. 信息胶囊（时间+地点+标题），点击 → `cue.inject`（§3.5），成功气泡"已发送～"，失败走降级；
  2. 紧随其下的"查看日历"跳转胶囊，点击 → 打开系统日历应用（§3.6.1），不注入不发送。
  联系人/记忆类默认只有信息胶囊；跳转胶囊计入总数（如 1 条日历信息 + 1 条跳转 + 1 条联系人 = 3）。
- 长按胶囊 2s → 校准模式：气泡"点一下聊天输入框的位置"，下一次屏幕点击记录绝对坐标存
  SecurePrefs（`magicCue.inputPoint`），默认 `screenWidth/2, screenHeight-120`。
- 拖动 avatar / 新的双击发生时立即收起胶囊并还原窗口。

#### 3.6.1 跳转系统日历

- 主路径：app 内 `UIAbilityContext.startAbility(Want)`：
  `bundleName: 'com.huawei.hmos.calendar'`（真机 `bm dump -a` 实测确认，M1 任务），
  尽力携带目标日期参数（日历深链格式若不支持则打开主页）。
- 悬浮窗点击时 app 在后台 → 需声明 `ohos.permission.START_ABILITIES_FROM_BACKGROUND`
  （system_basic，ACL；现有 system_core profile 可覆盖）。
- 备选路径（权限受阻时）：bridge（root）执行 `/bin/aa start -b <bundle> -a <ability>`
  （ohos-cli-tool skill 已验证的 shell 路径），封装为现有 `cue.inject` 同级的 `cue.open` RPC。
- 跳转后胶囊组整体收起。

#### 3.7 权限体系重构与自定义页面数据授权（7 项数据源集中管控）

**架构与产品口径（2026-09-05 演进与 PRD FR6 一致）：** 
Magic Cue 是默认系统级能力（`magicCue.enabled` 默认 `true`，双击先跑 Magic Cue，无命中静默降级为原记忆流程），**无需也不设全局功能开关**。为了让用户对个人敏感数据拥有清晰透明的掌控权，原先分散在设置页的数据源权限现已彻底解耦并升级为**自定义页面（Tab 2, SkillsTab）底部的“系统数据授权访问范围”**。

#### 3.7.1 页面职责划分与极简规范
1. **自定义页面（Tab 2, SkillsTab）**：
   - 定位：用户个性化与数据授权中心；
   - 移除所有顶部冗余文字说明，直接展示功能主体；
   - 顶部包含 Avatar 皮肤下拉选择器（精简横向空间）、大模型配置卡片、WeChat 通道连接、Skills 技能扩展；
   - 底部集中设立**系统数据授权访问范围（7 项数据开关）**：通讯录、短信、通知、日历、备忘录、图库、文管。
2. **设置页面（Tab 3, SettingsTab）**：
   - 定位：底层基础运行设置；
   - 顶部无文字说明，移除冗余的 Node Info 区域；
   - 包含 DSH 后端连接配置、全局桌面宠物悬浮窗开关（默认启动关闭，默认坐标置于右下方：距底 1/4、距右 1/5）；
   - 底层基础硬件权限（定位、语音唤醒、相机、录屏、屏幕感知）。

#### 3.7.2 7 项系统数据源访问方案
1. **通讯录（Contacts）**：授权 `ohos.permission.READ_CONTACTS`（NORMAL user_grant），`contacts.search` 模糊匹配。
2. **短信（SMS）**：确认为**读取短信**（`ohos.permission.READ_MESSAGES`，system_basic，加入 profile ACL）。底层由 DSH 守护进程直接读取 SQLite 数据库（`/data/app/el2/100/database/com.ohos.telephonydataability/rdb/sms_mms.db`），彻底规避普通应用弹窗受限与 PrivacyCenter 阻断。
3. **通知（Notifications）**：授权 `ohos.permission.NOTIFICATION_CONTROLLER`（system_core ACL 静态授权），系统级感知即时通知流。
4. **日历（Calendar）**：授权 `ohos.permission.READ_CALENDAR`（NORMAL user_grant），`calendar.events` 检索前后日程，支持信息与跳转双胶囊。
5. **备忘录（Notepad/Memo）**：**2026-09-05 全面解封启用**。支持 Bonio memo 及 DSH 直接读取华为备忘录 SQLite 数据库（`/data/app/el2/100/database/com.huawei.hmos.notepad/rdb/notepad.db-dwr`），打破无公开 API 限制。
6. **图库（Gallery）**：授权 `ohos.permission.READ_IMAGEVIDEO`（user_grant），读取相册多媒体。
7. **文管（Documents）**：授权 `ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY`（user_grant / ACL），支持读取本地文件与文档。

#### 3.7.3 ArkTS 异步授权响应式 UI 缺陷修复（`SettingToggleRow`）
- **原生 Switch 缺陷**：ArkTS 原生 `Toggle({ type: ToggleType.Switch })` 在触发异步权限弹窗（`requestPermissionsFromUser`）时，若用户点击“拒绝”，系统权限未变，但由于手势触发 Switch 已经在视觉上拨动为开启，且无法通过外部简单传参强制回弹，导致界面显示已开启但实际无权限。
- **解决方案**：独立封装 `@Component struct SettingToggleRow`：
  - 使用 `@Prop @Watch('onPropChange') isOn: boolean` 维护外部与内部 `@State toggleState: boolean` 的同步；
  - 将 `onChange` 回调规范化为 `(nextVal: boolean) => Promise<boolean>` 异步处理管道；
  - 若开启处理异步返回 `false`（例如权限被拒绝或取消），组件内部触发平滑回弹复位，确保 UI 视觉永远与实际系统授权绝对一致；
  - 应用冷启动零弹窗：冷启动时不自动请求任何 user_grant 权限，完全由用户按需在自定义页面开启。

#### 3.7.4 特权签名与 Profile ACL
- `ohos.permission.READ_MESSAGES` 与 `ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY` 扩充写入 `msdpdemo-system-core-profile.json` 的 `allowed-acls` 与 `restricted-permissions`；
- 使用 `tools/hapsigner` 签署 `system_core` profile 与全量 HAP 包；
- NORMAL 级权限（`READ_CONTACTS`/`READ_CALENDAR`/`READ_IMAGEVIDEO`）绝不写入 `allowed-acls`，保持标准的运行时弹窗与系统设置可撤销特性。

## 4. 序列图（命中场景）

```
用户        FloatWindowPage   MagicCueController   dsh(magic-cue)      app handlers     bridge / sqlite
 │ 双击          │                  │                  │                   │               │
 ├──────────────>│ triggerSmartEdge │                  │                   │               │
 │               │──屏幕文本───────>│ chat.send        │                   │               │
 │               │                  ├────────────────>│ 判定+取数          │               │
 │               │                  │                  ├─ contacts.search ─> queryContacts │
 │               │                  │                  │<─ node.invoke.result ─────────────│
 │               │                  │                  ├─ read sqlite db ─────────────────>│ notepad.db / sms.db
 │               │                  │                  │<─ db results ─────────────────────│
 │               │                  │                  ├─ memo_list(query) ───────────────>│
 │               │                  │                  │<─ tools result ───────────────────│
 │               │                  │<─ chat final(JSON)│                  │               │
 │               │<─cues────────────│                  │                   │               │
 │  <== 胶囊 ==  │ 加宽窗口+渲染     │                  │                   │               │
 │  点击胶囊      │                  │                  │                   │               │
 ├──────────────>│ cue.inject(text, point) ──────────────────────────────────────────────>│ uitest
 │  <== 输入框已填并发送 ==          │                  │                   │               │
```

## 5. 风险与 Spike（开工前置）

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R1 | **uitest 中文文本注入**进微信输入框的可行性/稳定性 | 高 | **Spike M0 必做**：真机手动跑 `/bin/uitest` 序列验证；不通则换剪贴板+键事件方案；再不通则 V1 降级为"复制+引导粘贴" |
| R2 | 发送键位置（输入点偏移）因 app/键盘态不同而漂移 | 中 | 校准点含输入框点+发送点两点分别校准；默认值保守；失败不重试直接降级 |
| R3 | MSDP 文本在微信聊天页的覆盖度（部分控件拿不到文本） | 中 | Spike 里实测微信；不足时降级附截图走视觉 |
| R4 | 系统数据运行时授权被拒 | 低 | 封装 `SettingToggleRow` 异步回弹，未授权时该类 cue 静默跳过 |
| R5 | 误弹胶囊打扰 | 中 | 只响应“询问”句式；空结果不弹；12s 自动收起；Magic Cue 无开关（默认功能），数据源授权按需开启 |

## 6. 开发拆解与排期

| 里程碑 | 内容 | 产出 | 预估 |
|---|---|---|---|
| M0 | **Spike**：真机验证 uitest 注入微信 + MSDP 微信文本覆盖度 | 结论记录进本文档 §5 | 0.5–1d |
| M1 | `contacts.search` / `calendar.events` handler + 权限声明 + 确认日历应用 bundleName | 真机可查（smoke-tool 验证） | 1–1.5d |
| M2 | magic-cue 会话 + prompt + memo query + 工具描述修正 | one-shot 脚本跑出正确 JSON | 1d |
| M3 | 胶囊 UI + 窗口动态加宽 + side 判定 + 日历双胶囊（信息+跳转）+ 自动收起 | 真机可见可点、跳转胶囊可打开日历 | 1–1.5d |
| M4 | `cue.inject` RPC + 注入主路径 + 降级路径 + 校准 | 端到端点击→发送 | 1–1.5d |
| M5 | 权限交互重构 + 数据源集中至自定义页面 + 7 项数据源打通 + `SettingToggleRow` | 视觉与授权一致，拒绝平滑回弹 | 1d |
| M6 | 打磨：全页面极简去文字、全量 system_core 签名打包、HUAWEI Mate X7 真机验收 | 验收清单过一遍 | 0.5–1d |

## 7. 验证方式

- M1/M2：`dsh-plugins/bonio-bridge/test/one-shot.mjs` 扩展 `magic-cue.mjs`（发屏幕样例文本，断言 JSON cues）；`smoke-tool.mjs` 直接调 `contacts.search`/`calendar.events`。
- M3–M6：真机（HUAWEI Mate X7 / SGU-AL10）手动 + `snapshot_display` 截图确认；微信双人实测三类询问。
- 回归：双击记忆（`system:companion-memory`）与拖动 avatar 不受影响。

## 8. 后续版本（不在本次范围）

- 被动触发（前台应用变化钩子 + 节流）
- 跨应用动态校准记忆输入框
- 胶囊长按看全文、多 cue 翻页

## 9. 实现状态（2026-09-05 真机全量落地）

下述里程碑已在 HUAWEI Mate X7（SGU-AL10）真机全量编译、system_core 签名、安装并验证：

- **M0 注入 spike**：`/bin/uitest` 三连击注入（点输入框→输中文→点发送）验证可行；校准点由 bridge 学习后 app 缓存。
- **M1/M2 数据源与会话**：`ContactsHandlerImpl`、`CalendarHandlerImpl`；`MagicCueController`（`system:magic-cue` ephemeral chat.send + JSON cues 解析）；工具描述修正。
- **M3/M4 胶囊与注入**：`FloatWindowPage` 侧边胶囊条、日历双胶囊（信息 + 查看日历跳转）、12s 自动收起、`cue.inject`/`cue.open` RPC。
- **M5 权限体系重构与 7 项系统数据源集中管控**：
  - 数据源权限全面迁入**自定义页面（Tab 2, SkillsTab）底部的“系统数据授权访问范围”**；
  - 落地 7 项数据权限：通讯录、短信、通知、日历、备忘录、图库、文管；
  - 备忘录与短信通过已 root 设备 DSH 直接读取 SQLite 数据库文件落地；
  - 自定义封装 `SettingToggleRow`，彻底解决 ArkTS 原生 Switch 在权限拒绝时不回弹的视觉缺陷；
  - `msdpdemo-system-core-profile.json` 扩充 `READ_MESSAGES` 与 `READ_WRITE_DOCUMENTS_DIRECTORY` 并经由 `tools/hapsigner` 进行特权签名。
- **M6 UI 精简与细节打磨**：
  - 移除各 Tab 页面顶部冗余文字说明；
  - 右上角小喇叭统一为现代线框风格；
  - Avatar skin 改为下拉 Select 菜单，大幅节省纵向空间；
  - 悬浮窗默认位置调整至右下方（距底 1/4、距右 1/5）。
- **端到端实测**：
  - 7 项数据开关逐项验证：授权成功显示开启，拒绝授权平滑回弹复位；
  - 联系人、日历、备忘录（本地与数据库直读）、短信数据库直读均已通过真实数据验证。