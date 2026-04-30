# Cross-Platform App Architecture & UI Design (Phase 2.5)

根据需求，我们需要将 Android 端的 UI 形态调整为与 HarmonyOS 端完全一致的架构，并在两端都实现“桌面萌宠”形式。优先在 Android 项目上完成开发。

## 1. 核心结构目标 (两端通用)
应用默认进入主页，包含底部导航栏 (Tabs)，分别为：`Canvas`, `Chat`, `Voice`, `Settings` 四个 Tab。
- **取消独立登录页**：连接网关的能力（Host、Port、Token 等配置）合并至 `Settings` Tab 中。
- **App 默认入口与焦点**：启动应用后直接进入主页，并默认选中第 3 个 Tab（`Voice` 萌宠页）。
- **后台悬浮窗切换机制**：
  - 当应用处于前台时：系统悬浮窗隐藏，萌宠在 App 内的 `Voice` Tab 中全屏/沉浸式显示，并承担交互功能。
  - 当应用被退到后台（如按 Home 键或切换应用）时：在桌面显示系统级的萌宠悬浮窗（维持原先 Phase 1/Phase 2 我们实现的效果和状态）。
  - 当点击桌面悬浮窗时：唤醒 App 回到前台 `Voice` Tab，并在桌面上隐藏悬浮窗。

---

## 2. 页面与组件改造规划 (重点针对 Android 端首发)

### 2.1 引入 Navigation 与界面的改动
- 因为目前 Android 端还是一个只有单页面的骨架，我们需要在 Compose 中引入 `BottomNavigation` (NavigationBar)。
- 创建四个 Tab 的 Compose 页面结构。

### 2.2 改造 Settings Tab
- 实现配置与连接表单：手动输入 Gateway Host, Port, Token 和 Enable TLS 开关。
- 具有 `Connect` / `Connecting...` / `Disconnect` 三态按钮。

### 2.3 重塑 Voice Tab 与状态同步
- 将原有的 `MainActivity` 中简单的 "Start Agent" 改为真正的 `VoiceScreen`。
- `VoiceScreen` 中居中显示 `LottieAnimationView` (或 Compose Lottie) 与气泡，绑定到现有的 `AgentStateManager`。
- 生命周期联动：监听 Android Activity 的 `onStart`/`onStop` (或 Compose 的 `LifecycleEventObserver`)：
  - `onStop` (退到后台)：调用 `startFloatingWindowService()` 弹出我们在 Phase 2 写的系统悬浮窗。
  - `onStart` (回到前台)：停止/隐藏悬浮窗服务，由 `VoiceScreen` 内部直接渲染相同状态的 Lottie 角色。

---

## 3. 实现路标 (Roadmap for Phase 2.5)

优先在 Android 完成以下两步走的重构：

**Step 1: App 骨架与结构重构 (UI 调整)**
- [ ] 引入 `androidx.navigation.compose` 依赖。
- [ ] 构建带有底边栏(Bottom Navigation)的 `MainScreen`，配置四个 Tab。
- [ ] 完成 `SettingsScreen` UI，提供输入框连接配置形态（纯 UI 占位预留给 Phase 3）。
- [ ] App 启动直接跳入 `MainScreen` 并默认激活 `Voice` Tab。

**Step 2: Voice Tab 与桌面悬浮窗的生命周期联动 (逻辑调整)**
- [ ] 完成 `VoiceScreen` UI（大号居中萌宠与气泡）。
- [ ] 在 `MainActivity` 或根级 Compose 监听应用的前后台状态。
- [ ] 退后台时触发悬浮窗显示，回前台时隐藏悬浮窗。
- [ ] 修改悬浮窗的点击事件：点击悬浮窗唤起 `MainActivity` 至前台。
