# BoJi (波机)

BoJi 是 [OpenClaw](https://github.com/openclaw/openclaw) 的跨平台移动端客户端，旨在将 AI 智能体能力拓展到您的掌上设备，并将手机/平板转化为具备物理世界感知能力的智能节点。同时，BoJi 创造性地提供了一个常驻桌面的“虚拟猫咪助手”，让 AI 交互变得更加生动、直观和随时随地。

目前，BoJi 原生支持 **Android** 和 **HarmonyOS (NEXT)** 两个主流平台。

## 🎯 核心定位与功能

1. **虚拟助手悬浮窗 (Desktop Agent)**
   - 桌面常驻的可爱猫咪动画（基于 Lottie）。
   - 能够反映 AI 的实时状态（如：发呆 Idle、聆听 Listening、思考 Thinking、说话 Speaking）。
   - 通过悬浮气泡直接在桌面展示 AI 的回复，无需频繁切回 App 主界面。

2. **OpenClaw 移动网关节点 (Edge Node)**
   - 完美兼容 OpenClaw 协议，稳定连接到您的私有或公共 Gateway。
   - 在后台静默运行，充当大模型的“眼睛”和“耳朵”。

3. **原生的硬件感知能力共享**
   - 授权后，BoJi 可以将以下底层系统能力暴露给后端的 AI 智能体：
     - **视觉能力**：实时屏幕截图、录屏流分享、前后置摄像头拍照/录像。
     - **听觉能力**：麦克风环境音采集与对话输入。
     - **位置感知**：获取精准或粗略的地理位置信息。
     - **通信拦截**：监听系统通知，并可执行读取或发送短信等操作。
     - **传感器数据**：步数、运动状态等设备指标（根据平台支持度）。

4. **现代化流畅 UI**
   - 全新的四大模块底座：Chat（聊天交互）、Screen（屏幕视图共享）、Server（节点与网关连接管理）、Settings（细粒度的设备权限管控）。
   - 提供暗色/亮色主题完美适配的现代沉浸式视觉体验。

---

## 💻 平台特定指南

### 🤖 Android 版本

*   **环境要求**：Android 12 (API 31) 或更高版本。
*   **开发技术**：Kotlin + Jetpack Compose + CameraX + 现代前台服务。
*   **关键权限说明**：由于 BoJi 定位于“虚拟桌面助手”，应用在**启动时会强制引导用户授予“显示在其他应用上层” (SYSTEM_ALERT_WINDOW) 权限**。针对 Android 14+，已重点适配了 `FOREGROUND_SERVICE_SPECIAL_USE` 等严格的后台生存与前台服务安全规约。

### 🌺 HarmonyOS (NEXT) 版本

*   **环境要求**：HarmonyOS 6.0 (NEXT) / API 12。
*   **开发技术**：ArkTS + ArkUI + Next 原生能力。
*   **关键权限说明 (必看)**：
     HarmonyOS 对于悬浮窗权限管控极严。`ohos.permission.SYSTEM_FLOAT_WINDOW` 属于受限权限（system_basic）。
    - 代码中已在 `module.json5` 声明该权限，以便系统设置中显示授权开关。
    - **开发者注意**：如果要在这台真机上编译安装，您**必须**在 DevEco Studio / AppGallery Connect 的签名 Profile 配置中，将 `ohos.permission.SYSTEM_FLOAT_WINDOW` 加入到 **ACL（允许的访问控制列表）白名单** 中。如果不配置 ACL 直接安装，将会遇到 `Code: 9568289 - grant request permissions failed` 的报错。

---

## 🚀 快速开始开发

1. **获取代码**
   ```bash
   git clone <你的仓库地址>
   cd boji
   ```

2. **Android 编译**
   - 使用最新版的 Android Studio (Ladybug 或更高) 打开 `android` 目录。
   - 等待 Gradle 同步完成后，点击 Run 部署到测试机。

3. **HarmonyOS 编译**
   - 使用 DevEco Studio (5.0.3.900+) 打开 `harmonyos` 目录。
   - 配置好带有 ACL 权限的 Automatic Signature。
   - 点击 Run 部署到鸿蒙真机或模拟器。

## 🛡️ 隐私与安全

由于 BoJi 作为 OpenClaw 的边缘节点会获取大量的系统敏感权限（屏幕、相机、短信等），请确保您连接的 Gateway 是可信的安全服务器。App 内部的 `Settings` 页面提供了针对单项能力的快速开关，您可以随时切断某项能力对 AI 的授权。
