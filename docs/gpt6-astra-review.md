# Bonio HarmonyOS：PRD、架构与代码审查

日期：2026-09-08  
审查基线：`dsh` 分支，提交 `4fc848e`  
范围：HarmonyOS App、`dsh-plugins/bonio-bridge`、相关 PRD/架构文档和本仓库可见的 phone-use 集成。  
结论性质：本文件只记录静态代码审查和少量本地隔离复现；没有修改业务代码、编译、签名、安装或重新执行真机验收。

## 1. 当前定位与完成度

当前 HarmonyOS 主线已经由“移动端连接 HiClaw”转为本机 Agent：

```text
Avatar / Chat UI
       │
       ▼
bonio-bridge (127.0.0.1:10724) ──► DSH Agent ──► 模型 / 本机工具
       │
       ├── operator session：聊天、历史、memo RPC、Magic Cue RPC
       └── node session：联系人、日历、屏幕、相机等设备能力
```

业务会话又分为主聊天、`system:companion-memory` 和 `system:magic-cue`。连接角色与业务会话是两个维度，后续文档和状态机应明确区分。

| 模块 | 代码可确认的进展 | 不能据此直接宣称完成的部分 |
|---|---|---|
| DSH 接入 | 本机连接、流式聊天、会话映射、历史恢复、node 工具桥接已实现 | 认证、角色隔离、断线恢复与跨版本兼容仍有漏洞 |
| 屏幕记忆 | MSDP 采集、摘要、memo 入库、封面/原图、标签与详情页已有实现 | 关闭能力后的在途任务、主动记忆可靠性、纠错和复用闭环需补齐 |
| Magic Cue | 双击识别、答案胶囊、日历跳转、输入注入的主调用链已接入 | 数据授权约束、失败降级、发送确认、截图降级和真实时限未达可验收状态 |
| 七项系统数据源 | `SkillsTab` 已出现七项开关，联系人/日历 handler 已实现 | UI 开关不等于后端能力受控；其余能力的完整执行链路不足 |
| Phone-use SOP | 仓库中有技能包装和部署记录，文档记录历史真机成功 | 核心执行器来自独立仓库，当前 App 的任务展示、停止、接管和收尾不能由本仓库证明 |
| Avatar | 当前为四套官方预置 spritesheet 皮肤 | Avatar Creator 已挂起，不能按旧 PRD 统计为已交付 |
| 阅读搭子 | 现有屏幕理解和记忆能力可以复用 | 阅读 PRD 中的分屏、编辑笔记、转录字幕等没有形成鸿蒙端产品闭环 |

## 2. 产品与 PRD 审查

### 2.1 双击 Avatar 的产品语义应固定为“自动记忆，顺带提供帮助”

Avatar 的点击、长按、拖动等交互已分配，不能继续增加复杂手势，也不应让用户在“记忆”和“帮我回复”之间选择。产品决策建议如下：

1. 双击永远触发一次屏幕采集，并且**必定启动自动记忆**；两条分析链路复用同一份采集结果。
2. 并行运行 Magic Cue。命中后弹出答案胶囊；不命中时以眨眼、甩尾、单击同类的调皮反馈收尾即可。
3. 无 Cue 不等于失败，更不应提示“暂时不能帮你”，因为用户的核心动作“记住此刻”可能已经完成。
4. 只有记忆保存失败、屏幕能力不可用或内容被安全规则排除时，才明确说明未保存，不能用动画掩盖事实。
5. 密码、验证码、完整私信等仍不能写入记忆；支付相关信息只能保存必要的订单摘要，不能把支付凭据或验证码写入。

建议的状态序列：

```text
双击 → 单次屏幕采集 → 并行：伴随记忆 / Magic Cue
                         ├─ 记忆成功：轻量“记住啦”反馈
                         ├─ Cue 命中：展示答案胶囊
                         ├─ Cue 未命中：调皮互动反馈
                         └─ 记忆失败：明确说明可重试
```

这也修正了当前逻辑：无 Cue 时如果 bundle 名包含 `wechat`、`mms`、`msg` 或 `chat`，会直接显示“暂无未回复的提问”并返回，导致微信小程序订单等页面没有进入主动记忆路径。见 [FloatWindowPage.ets](../harmonyos/entry/src/main/ets/pages/FloatWindowPage.ets) 第 521 行。

### 2.2 Magic Cue 的“快速发送”需要用户可理解、可恢复

当前胶囊只显示被截断的内容，却允许点击整个卡片直接发送。用户可能没有看见完整电话、地址、日程备注便已经外发。并且失败时卡片被立即移除，只能重新双击、重新检索。

建议：

- 胶囊显示全文预览入口；只有明确的“发送”区域触发发送。
- 执行前确认采集时的应用和当前应用/会话一致；不一致时改为复制或要求重新分析。
- 失败后保留答案，提供“重试”“复制”，不要只显示“发送失败”。
- “已发送”必须建立在可核验的结果上，不能只以模拟点击返回作为成功。
- 将“没有提问”“无匹配数据”“数据未授权”“识别失败”“请求超时”分别反馈。当前错误、超时、JSON 解析失败都可能表现为无 Cue。

相关实现：Magic Cue 总空闲超时为 90 秒，且收到 agent 流事件会续期，和 PRD 的 15 秒验收目标不一致；见 [MagicCueController.ets](../harmonyos/entry/src/main/ets/node/MagicCueController.ets) 第 21、61 行。

### 2.3 权限的信息架构与状态表达需要重做

现在“自定义”页同时放皮肤、模型、微信、Skills 和七类敏感数据开关，而屏幕感知等又在设置页。用户无法直接理解 Bonio 目前可访问什么，以及一个开关表示“用户允许”“系统已授权”还是“DSH 可实际读取”。

建议设立“数据与隐私”作为统一入口，每项数据源至少展示：

| 状态 | 含义 |
|---|---|
| 用户允许 | 用户在 Bonio 中选择允许该类用途 |
| 系统授权 | HarmonyOS 权限/ACL 当前真实授予状态 |
| 执行可用 | App handler 或 root DSH 数据通道已经验证可访问 |

关闭开关必须在 App handler、bridge、本地 memo/数据库读取三个位置都生效，不能只减少 `commands` 广播。

### 2.4 记忆应支持核对、修正、再利用

Memory 详情已有封面、原图和来源，但原图固定区域显示、摘要只读。对于订单规格、店铺、金额等高价值数据，用户没有就地纠错的途径，也没有明确从某条记忆发起“再来一单”或对话检索的入口。

建议补充原图缩放、摘要编辑、来源/采集时间、基于该记忆提问以及携带 memo ID 的复购入口。这样才能把“记住”变成可验证和可重复使用的个人数据资产。

### 2.5 Phone-use 的任务收尾必须以“用户接管”表达

“到免密支付页”不是泛化的“任务完成”。任务卡需要明确显示饮品、规格、门店、金额和当前步骤，最终态应为“已到付款页，等待你核对支付”。Stop 后还应回报设备执行器已经停止，避免用户误以为后台仍在点击。

文档应记录实际使用的执行器版本、SOP 版本、目标 App 版本及真机回归日期，避免将一次历史 CLI 成功泛化为当前 App 的端到端保证。

## 3. 架构审查与调整建议

### 3.1 建立单一的“用户授权策略”执行点

当前客户端在 `ConnectionManager.buildInvokeCommands()` 中只在联系人和日历开启时广播命令；bridge 和 handler 却没有统一的策略对象来验证每次读取请求。接口发现能力与实际权限不一致，会造成关闭开关仍有读取路径、开启开关却未实际可用。

建议引入 `DataAccessPolicy`：由权限状态、用户偏好、能力实现状态生成短时策略快照；node handler 和 DSH 本地工具都在执行前检查该快照；bridge 根据同一策略生成工具描述与命令列表。策略应返回明确的 `USER_DISABLED`、`SYSTEM_PERMISSION_DENIED`、`BACKEND_UNAVAILABLE`，而不是笼统的未支持。

### 3.2 分离 Agent 的权限与生命周期

主聊天、屏幕摘要、Magic Cue 的风险不同。当前 bridge 对自有 Agent 的审批请求直接授予，屏幕分析也装配 `standard` preset；这让“分析一屏内容”的 Agent 具备比实际需要更多的能力。

建议：

- 主聊天：按正常工具集和用户确认策略执行。
- 伴随记忆：无工具或严格只读工具集，且不持久化原始敏感输入。
- Magic Cue：仅可访问已授权的检索工具；注入/外发由独立 RPC 处理，不能由模型直接决定。
- 每种运行都使用显式生命周期策略。当前所谓 ephemeral 只是不复用 agent，仍创建 DSH session 并在完成后 `flush`，不能保证不落盘。

### 3.3 统一任务状态与取消协议

聊天、Magic Cue、伴随记忆、phone-use 分别管理 timeout、runId、取消与 UI 状态，导致用户回答 agent 问题、切换页面、断线和停止时出现不同步。

建议定义统一状态：`queued`、`capturing`、`analyzing`、`awaiting_user`、`executing`、`awaiting_handoff`、`succeeded`、`failed`、`cancelled`。每个任务拥有 taskId/runId 和取消代次；取消沿 UI → bridge → Agent → node tool → phone-use 执行器传播，并由执行端确认最终停止。

### 3.4 固化协议契约与版本边界

HarmonyOS 客户端既兼容旧 HiClaw wire protocol，又依赖 DSH bridge 的特殊行为，外部 phone-use 执行器也独立演进。建议为 `connect`、`chat.send`、流式事件、`node.invoke`、Cue RPC、memo RPC 建立契约测试，明确“累计文本/增量文本”语义、鉴权要求和错误码；部署产物中固定 App、bridge、DSH、执行器、SOP 的兼容版本。

## 4. 代码问题

以下“已复现”仅指本地隔离、内存模拟验证，没有连接手机、调用模型或访问真实用户数据。

| 优先级 | 证据 | 问题与影响 | 建议 |
|---|---|---|---|
| P0 | 已复现；[gateway.ts](../dsh-plugins/bonio-bridge/src/gateway.ts) 第 323 行 | 配置 token 后，未发送 `connect` 的 socket 仍可直接调用 `chat.history` 读取历史。 | 在 RPC 分发入口统一认证；再校验角色和会话访问范围。 |
| P0 | 已复现；[sessions.ts](../dsh-plugins/bonio-bridge/src/sessions.ts) 第 35 行 | operator 断开时会取消仍由在线 node 执行的 pending invoke，并返回“node session disconnected”。 | 给 pending invoke 绑定 node `connId`，只有断开所属 node 时才取消。 |
| P0 | 已复现；[driver.ts](../dsh-plugins/bonio-bridge/src/driver.ts) 第 179 行 | 用户回答“不同意”会同时匹配“同意”和“不同意”，可能错误确认敏感操作。 | 使用 optionId/questionId；自由文本只精确匹配，歧义时回传原文。 |
| P0 | [SkillsTab.ets](../harmonyos/entry/src/main/ets/pages/SkillsTab.ets) 第 1085、1157 行 | 短信、文管即使拒绝系统权限也直接写入开启状态。 | 依据真实结果回弹；root 降级通道单独显示并先验证可用。 |
| P0 | [ConnectionManager.ets](../harmonyos/entry/src/main/ets/node/ConnectionManager.ets) 第 128 行；[ContactsHandlerImpl.ets](../harmonyos/entry/src/main/ets/node/handlers/ContactsHandlerImpl.ets) 第 32 行 | 联系人/日历关闭只影响命令广播，handler 未执行用户开关检查；memo 开关也未约束 bridge RPC、工具或后台保存。 | 将用户策略校验下沉到每个执行入口，并约束 root DSH 数据读取。 |
| P1 | [ChatTab.ets](../harmonyos/entry/src/main/ets/pages/ChatTab.ets) 第 173 行；[driver.ts](../dsh-plugins/bonio-bridge/src/driver.ts) 第 218、432 行 | DSH 等待 `ask_user_question` 的答案时，UI 因仍处于 sending 状态拒绝发送下一条消息，最终只能等待超时或 Stop。 | 加入 `awaiting_user` 状态，允许发送回答并关联原 run。 |
| P1 | [FloatWindowPage.ets](../harmonyos/entry/src/main/ets/pages/FloatWindowPage.ets) 第 521 行 | 无 Cue 时微信包名页面直接返回，主动记忆被阻断；微信小程序订单受影响。 | 双击始终启动记忆；Cue 仅作为并行增强。 |
| P1 | [NodeRuntime.ets](../harmonyos/entry/src/main/ets/node/NodeRuntime.ets) 第 412 行；[inject.ts](../dsh-plugins/bonio-bridge/src/inject.ts) 第 150 行 | Cue 注入缓存全局坐标，切应用/键盘/屏幕布局后可能点错；模拟点击后即报成功，未确认内容真的发送。 | 坐标按 app 与布局保存；执行前后验证，失败保留复制/重试。 |
| P1 | [NodeRuntime.ets](../harmonyos/entry/src/main/ets/node/NodeRuntime.ets) 第 550 行 | 连接后设定的 500ms node connect timer 在 `disconnect()`/Ability 销毁后不取消，可能重新连接。 | 保存 timer，断开时取消；用连接代次使陈旧回调无效。 |
| P1 | [MagicCueController.ets](../harmonyos/entry/src/main/ets/node/MagicCueController.ets) 第 98 行 | 新请求取消旧请求时只丢弃 resolve，不取消后台运行；旧 Promise 可能永不结束，迟到响应也会干扰状态。 | 用 AbortController/请求代次管理，确保每个 Promise 都结算。 |
| P1 | [NodeRuntime.ets](../harmonyos/entry/src/main/ets/node/NodeRuntime.ets) 第 398 行 | 屏幕采集可以拥有图片，但 Magic Cue 只传 JSON 文本，未实现 PRD 规定的视觉降级。 | 文本不足时传受控尺寸图片附件；在隐私策略中明确其云端传输。 |
| P2 | [NodeRuntime.ets](../harmonyos/entry/src/main/ets/node/NodeRuntime.ets) 第 491 行 | 语音“截图/总结”只显示“截图中/总结中”气泡，随后记录 TODO，没有实际采集或总结。 | 复用 MSDP/截图与 chat 附件链路，成功返回结果，失败完整收尾。 |
| P2 | [ChatController.ets](../harmonyos/entry/src/main/ets/node/chat/ChatController.ets) 第 269 行 | 快速从会话 A 切到 B 时，A 的迟到历史可能覆盖 B 的消息；随后发送仍进入 B。 | 历史请求带加载代次与 sessionKey 校验，过期回包不得写状态。 |
| P2 | [async_agent.cpp](../server/src/net/async_agent.cpp) 第 181 行；[ChatController.ets](../harmonyos/entry/src/main/ets/node/chat/ChatController.ets) 第 370 行 | 旧 C++ server 流式结构与客户端读取字段不一致，可能只有 final 后才看到回复。 | 统一协议；或客户端兼容两种字段且明确累计/增量语义。 |
| P2 | [FeatureManager.ets](../harmonyos/entry/src/main/ets/intent/FeatureManager.ets) 第 57 行 | 有通知处理器，但未找到系统通知订阅与 `feedNotification()` 的实际调用入口。 | 先补订阅生命周期和权限/开关校验，再对外宣称通知感知已交付。 |
| P2 | [CompanionMemoryController.ets](../harmonyos/entry/src/main/ets/node/CompanionMemoryController.ets) 第 270、344 行 | 损坏 JSON 与显式记忆兜底、队列溢出时的 Promise 结算需要补充覆盖，存在用户主动记录丢失或一直等待的风险。 | 给每个队列项明确成功/失败结算；溢出优先拒绝新任务或持久队列，不静默丢弃显式操作。 |

## 5. 推荐修复顺序与验收标准

### 第一轮：可信行为与数据控制

先修复鉴权、用户授权执行、拒绝权限回弹、会话断开、确认文本解析、`awaiting_user` 状态和 Cue 发送确认。验收至少覆盖：未认证 RPC、拒绝短信/文管权限、关闭联系人/日历/memo 后的直接工具调用、回答“不同意”、operator 断开但 node 继续运行、切换应用后 Cue 发送。

### 第二轮：双击语义与记忆闭环

实现“单次采集 + 自动记忆 + 并行 Magic Cue”。验收：聊天页、微信小程序订单、纯图片页面、无 Cue、记忆失败、内容被安全规则排除；每种场景都验证用户看到的反馈与真实保存状态一致。

### 第三轮：任务化自动化与体验打磨

将 phone-use 以任务卡接入，支持步骤、接管、停止确认、待支付收尾；补 Memory 纠错和再利用。最后做全量协议回归、HarmonyOS 构建、system_core 签名、HDC 安装和真机验收。

## 6. 文档维护建议

- 把“已实现”拆为“源码接入”“模拟验证”“当前版本真机端到端验收”，每项带日期、设备、版本和场景。
- 以 `docs/design/arch/20260902-dsh-msdp-memory-current.md` 作为鸿蒙 DSH 主线基准，明确它和旧 HiClaw/桌面 PRD 的边界。
- 标注 Avatar Creator 为挂起，避免旧文档中的入口和流程继续影响范围判断。
- Phone-use 文档应引用独立执行器的确切版本与部署来源，并把 CLI 验证和 App 验收分开记录。
