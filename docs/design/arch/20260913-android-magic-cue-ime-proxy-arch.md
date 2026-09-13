# Android 平台 Magic Cue 架构设计：双 Window 解耦防抖与免键盘静默注入

- **日期**：2026-09-13
- **状态**：已落地实施（Phase 1 双 Window 稳定化已完成，Phase 2 IME Proxy 架构已定义）
- **涉及工程**：`android/`
- **关联 PRD**：[20260913-android-magic-cue-ime-proxy-prd.md](../prd/20260913-android-magic-cue-ime-proxy-prd.md)

---

## 1. 架构演进与技术背景

### 1.1 摒弃 hiclaw 与统一 DSH 架构

随着项目整体技术架构重构演进，Android 端与 HarmonyOS 端全面看齐，**彻底摒弃历史遗留的 C++ hiclaw 本地网关**。
所有大模型推理、意图分析、工具调度全面由设备端本地或局域网运行的 **DSH（DeepSeek Harness）** 统一承接，遵循统一的 Gateway 协议。

### 1.2 旧架构痛点剖析

```
旧方案（单 Window）：
┌────────────────── FloatingAgentLayout (wrap_content) ──────────────────┐
│ [头顶气泡: "思考中..."]                                                 │
│ [Avatar 100dp] ─── (文本变长 / 胶囊弹出) ───> [胶囊 CardView: "139..."] │
└────────────────────────────────────────────────────────────────────────┘
问题 1: wrap_content 随子 view 宽度剧烈变化，触发 addOnLayoutChangeListener 异步负向补偿，WMS IPC 抖动导致 Avatar 左右漂移死循环。
问题 2: 双击截屏前 View.INVISIBLE 导致 300-500ms 视觉黑屏/闪烁。
```

---

## 2. Phase 1：双 Window 解耦架构（已实现）

### 2.1 物理架构拓扑

```
新架构（双 Window 彻底解耦）：
Window 1 (常驻 Avatar Overlay Window, 160dp x 140dp 固定尺寸):
┌──────────────────────────────────────────────┐
│        [居中头顶状态 Pill (maxWidth=150dp)]    │
│                                              │
│             [Avatar 100dp x 100dp]           │
│             锚点固定在 (30dp, 36dp)           │
└──────────────────────────────────────────────┘
  * 头顶文字无论多长，居中扩展，Avatar 坐标 0 像素漂移！
  * 双击时 View 保持常驻，零闪烁直接过渡 Thinking 动画！

Window 2 (独立按需挂载 Capsule Overlay Window, wrap_content):
┌──────────────────────────────────────────────┐
│  [图标] [建议标题 / 文本]        [发送 Button]  │
└──────────────────────────────────────────────┘
  * 位于 Avatar 侧边独立悬浮展示；
  * 根据 Avatar 处于屏幕左/右半屏，自动挂载在右侧或左侧；
  * 绝不干扰 Window 1 的任何布局测算。
```

### 2.2 核心代码实现映射

- **固定布局**：[`android/app/src/main/res/layout/floating_agent_layout.xml`](file:///d:/projects/bonio/android/app/src/main/res/layout/floating_agent_layout.xml)
  采用固定 `160dp x 140dp` 的 `RelativeLayout`，头顶 `bubble_label` 使用 `alignParentTop="true"` + `centerHorizontal="true"`，Avatar 实体固定在 `marginTop="36dp"`。
- **独立胶囊布局**：[`android/app/src/main/res/layout/magic_cue_capsule_layout.xml`](file:///d:/projects/bonio/android/app/src/main/res/layout/magic_cue_capsule_layout.xml)
  使用轻量 `CardView` 构建高圆角（`cardCornerRadius="20dp"`）侧边胶囊，包含标题、内容与直发按钮。
- **服务层解耦调度**：[`android/app/src/main/java/ai/axiomaster/bonio/FloatingWindowService.kt`](file:///d:/projects/bonio/android/app/src/main/java/ai/axiomaster/bonio/FloatingWindowService.kt)
  - 维护独立的 `capsuleView` 与 `capsuleLayoutParams`；
  - 移除所有 `addOnLayoutChangeListener` 和位移补偿代码；
  - 双击 `runMagicCue()` 移除 `View.INVISIBLE` 隐藏，保持常驻无缝并行截屏；
  - `AgentStateManager.kt` 在 `Listening` / `Thinking` 时统一调用 `clearBubble()`，杜绝思考时在侧边弹出杂质气泡。

---

## 3. Phase 2：免弹软键盘静默注入（IME Proxy 方案）

### 3.1 技术选型对比

| 方案 | 注入延迟 | 是否拉起全屏键盘 | 微信等 App 兼容性 | 实现难度 |
|---|---|---|---|---|
| **A. 无障碍节点直接赋值 (`ACTION_SET_TEXT`)** | <50ms | 否 | 差（未聚焦编辑框直接拒绝） | 低 |
| **B. 模拟点击 + 剪贴板粘贴浮窗** | 500-1000ms | 否/偶发弹起 | 中（手势位置受机型影响大） | 中 |
| **C. 虚拟输入法代理 (`BonioImeService`)** | **<50ms** | **绝不拉起软键盘** | **100% 完美原生支持** | 中 |

### 3.2 架构设计与数据流

```
用户在微信聊天界面
       │
       ▼ 双击 Avatar
[MagicCueController] ──> 截图 Vision / 结构文本 ──> [DSH / LLM] ──> 解析得到回复建议
       │
       ▼ 侧边滑出 Magic Cue 胶囊 ("13912345678", [发送])
用户点击 [发送]
       │
       ▼ 广播/Binder 触发
┌─────────────────────────────────────────────────────────────┐
│ BonioImeService : InputMethodService (透明代理输入法)         │
│  - onEvaluateInputViewShown() = false (不展示实体键盘布局)     │
│  - currentInputConnection.commitText(cueText, 1)            │
│  - currentInputConnection.performEditorAction(IME_ACTION_SEND)│
└─────────────────────────────────────────────────────────────┘
       │
       ▼
微信聊天输入框瞬间填入文字并直接触发网络发出！全程 0 毫秒界面抖动、无软键盘遮挡！
```

### 3.3 详细设计规范

1. **Service 声明**：
   在 `AndroidManifest.xml` 中注册 `BonioImeService`，声明 `android.permission.BIND_INPUT_METHOD` 及 `android.view.InputMethod` action。
2. **输入代理通信协议**：
   通过 Service 静态实例或本地 IPC 接收 `injectAndSend(text: String, autoSend: Boolean)` 指令。
3. **输入法透明化**：
   - 重写 `onEvaluateInputViewShown(): Boolean = false`，确保系统呼出输入法时仅提供底层 `InputConnection` 通道，不占用屏幕底部任何像素高度；
   - 提供浮动切换手柄，当用户需要实体打字时，一键调起用户的默认输入法（如 Gboard、搜狗输入法），实现无感协同。
