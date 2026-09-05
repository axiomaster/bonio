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

**需要新建**：联系人/日历 handler（app 侧完全没有）、magic-cue 会话与 prompt、胶囊 UI、
注入通道、memo 查询参数。另：`bonio_node_invoke` 工具描述宣称了多个不存在的命令
（`input.type`/`system.notify`/`calendar.events`/`contacts.search`），本次落地其中两个并修正描述。

## 2. 总体流程

```
双击 avatar (FloatWindowPage.handleTap)
  ├─ 屏幕感知关闭/Magic Cue 关关未开 → 现有行为（记忆流程），流程结束
  └─ MagicCueController.run()
       1. MsdpScreenAwarenessManager.triggerSmartEdge()      → 屏幕文本+应用名
       2. chat.send(sessionKey='system:magic-cue', prompt, 附件=屏幕文本)
          └─ dsh agent（ephemeral，标准 preset）
               ├─ 判定"是否有人在询问 X"（无 → 直接返回空 cues，不调工具）
               ├─ contacts.search / calendar.events / memo_list(query)
               │    （node.invoke.request → app 新 handler → node.invoke.result）
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

### 3.2 App：新 node 命令（联系人 / 日历）

新增 `node/handlers/ContactsHandlerImpl.ets`、`CalendarHandlerImpl.ets`，注册进
`InvokeDispatcher.handleInvoke()`、`ProtocolConstants.ets`、`ConnectionManager.buildInvokeCommands()`
（权限已授予才广播该命令，未授予时 agent 端自然收 `UNSUPPORTED_COMMAND`，prompt 已约束兜底）。

**`contacts.search`** `{query: string, limit?: number=5}` →
`{contacts: [{name, phones: string[], org?, emails?}]}`
- `@ohos.contact.queryContacts()` 全量拉取后本地按姓名/拼音前缀/包含匹配（联系人量级下可接受；
  若慢再换 `queryContactsByPhoneNumber` 反查）。
- 权限 `ohos.permission.READ_CONTACTS`（user_grant）：入口 Ability 用
  `requestPermissionsFromUser` 首次触发时引导。

**`calendar.events`** `{fromTs?, toTs?, titleQuery?, limit?=10}` →
`{events: [{title, startTs, endTs, allDay, location?}]}`
- `@ohos.calendarManager.getCalendarManager(ctx)` → `Calendar.getEvents(EventFilter.filterByTime / filterByTitle)`。
- 默认时间窗：今天起 ±7 天；titleQuery 命中时放宽到 ±90 天。
- 权限 `READ_CALENDAR`（normal 级）。读取为空时提示用户日历源问题，不重试。

**短信**：无 API，不做。**备忘录**：用 memo（§3.4）。

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

### 3.7 权限与设置

`module.json5` 新增：
- `ohos.permission.READ_CONTACTS`（system_basic user_grant ACL）
- `ohos.permission.READ_CALENDAR`（normal user_grant）
- `ohos.permission.START_ABILITIES_FROM_BACKGROUND`（system_basic system_grant ACL；悬浮窗点击跳转日历用，若走 bridge `aa start` 备选则不需要）

设置页新增 Magic Cue 开关（`magicCue.enabled`，SecurePrefs，默认关）；开启时统一
`requestPermissionsFromUser`。`EntryAbility` ACL 自检清单补两项。
（`INJECT_INPUT_EVENT` 仅在 spike 选择 app 内注入备选方案时才加。）

## 4. 序列图（命中场景）

```
用户        FloatWindowPage   MagicCueController   dsh(magic-cue)      app handlers     bridge
 │ 双击          │                  │                  │                   │             │
 ├──────────────>│ triggerSmartEdge │                  │                   │             │
 │               │──屏幕文本───────>│ chat.send        │                   │             │
 │               │                  ├────────────────>│ 判定+取数          │             │
 │               │                  │                  ├─ contacts.search ─> queryContacts│
 │               │                  │                  │<─ node.invoke.result ───────────│
 │               │                  │                  ├─ memo_list(query) ─────────────>│
 │               │                  │                  │<─ tools result ─────────────────│
 │               │                  │<─ chat final(JSON)│                  │             │
 │               │<─cues────────────│                  │                   │             │
 │  <== 胶囊 ==  │ 加宽窗口+渲染     │                  │                   │             │
 │  点击胶囊      │                  │                  │                   │             │
 ├──────────────>│ cue.inject(text, point) ────────────────────────────────────────────>│ uitest
 │  <== 输入框已填并发送 ==          │                  │                   │             │
```

## 5. 风险与 Spike（开工前置）

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R1 | **uitest 中文文本注入**进微信输入框的可行性/稳定性 | 高 | **Spike M0 必做**：真机手动跑 `/bin/uitest` 序列验证；不通则换剪贴板+键事件方案；再不通则 V1 降级为"复制+引导粘贴" |
| R2 | 发送键位置（输入点偏移）因 app/键盘态不同而漂移 | 中 | 校准点含输入框点+发送点两点分别校准；默认值保守；失败不重试直接降级 |
| R3 | MSDP 文本在微信聊天页的覆盖度（部分控件拿不到文本） | 中 | Spike 里实测微信；不足时降级附截图走视觉 |
| R4 | 联系人/日历运行时授权被拒 | 低 | 明确引导+设置跳转，未授权时该类 cue 静默跳过 |
| R5 | 误弹胶囊打扰 | 中 | 只响应"询问"句式；空结果不弹；12s 自动收起；总开关默认关 |

## 6. 开发拆解与排期

| 里程碑 | 内容 | 产出 | 预估 |
|---|---|---|---|
| M0 | **Spike**：真机验证 uitest 注入微信 + MSDP 微信文本覆盖度 | 结论记录进本文档 §5 | 0.5–1d |
| M1 | `contacts.search` / `calendar.events` handler + 权限声明 + 设置开关 + 确认日历应用 bundleName（`bm dump -a`） | 真机可查（smoke-tool 验证） | 1–1.5d |
| M2 | magic-cue 会话 + prompt + memo query + 工具描述修正 | one-shot 脚本跑出正确 JSON | 1d |
| M3 | 胶囊 UI + 窗口动态加宽 + side 判定 + 日历双胶囊（信息+跳转）+ 自动收起 | 真机可见可点、跳转胶囊可打开日历 | 1–1.5d |
| M4 | `cue.inject` RPC + 注入主路径 + 降级路径 + 校准 | 端到端点击→发送 | 1–1.5d |
| M5 | 打磨：文案、回归双击记忆、多 cue、异常路径、签名安装 | 验收清单过一遍 | 0.5–1d |

合计约 **5.5–7.5 人日**。每个里程碑独立可验证、可提交。

## 7. 验证方式

- M1/M2：`dsh-plugins/bonio-bridge/test/one-shot.mjs` 扩展 `magic-cue.mjs`（发屏幕样例文本，
  断言 JSON cues）；`smoke-tool.mjs` 直接调 `contacts.search`/`calendar.events`。
- M3–M5：真机（5MQ0125716000138）手动 + `snapshot_display` 截图确认；微信双人实测三类询问。
- 回归：双击记忆（`system:companion-memory`）与拖动 avatar 不受影响。

## 8. 后续版本（不在本次范围）

- 被动触发（通知/前台应用变化钩子 + 节流）
- 系统备忘录（root 变通或华为后续开放）
- 短信源（等公开 API）
- 胶囊长按看全文、多 cue 分页、按应用记忆校准点
