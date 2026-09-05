# Phone-Use（端侧 GUI Agent）与 SOP 架构设计与规范

> 日期：2026-09-05  
> 分支：`dsh`  
> 状态：已实现并在 HarmonyOS 设备端部署验证  
> 关联：[20260826-dsh-refactor-arch.md](20260826-dsh-refactor-arch.md), [20260902-dsh-msdp-memory-current.md](20260902-dsh-msdp-memory-current.md)

---

## 1. 总体背景与设计目标

### 1.1 为什么需要端侧原生 GUI Agent
传统的移动端 GUI-Agent（如基于 PC 端运行的 Open-AutoGLM）依赖电脑与手机通过 HDC/ADB 建立调试链路：
`PC (LLM 决策) -> HDC 抓图 -> 网络传输回 PC -> PC 调用 HDC 模拟点击`。
该架构存在严重痛点：
1. **脱离 PC 无法运行**：用户离开电脑就无法使用手机端自动化；
2. **高通信延迟**：每次截图与操作指令往返 PC 耗时可达数秒；
3. **架构臃肿**：无法与手机本地的常驻 AI 伴侣（Bonio Avatar / DSH）形成无缝内循环。

**`phone-use-harmonyos`** 实现了**端侧原生 C++ GUI Agent**：
- 编译为原生 AArch64 ELF 命令行可执行程序，直接运行在 HarmonyOS 设备的 Linux 用户态环境（`/data/local/bin/phone-use-harmonyos`）；
- 本地直接调用系统 `/bin/snapshot_display` 截屏与 `/bin/uitest` 模拟操作；
- 结合大模型视觉理解（GLM `autoglm-phone`），形成端侧全闭环的 UI 自主规划与执行能力。

---

## 2. 总体架构与协作链路

在 Bonio 的系统体系中，`phone-use-harmonyos` 位于**设备底层执行层**，与端侧 Agent（DSH）和 UI 层（HarmonyOS 客户端）紧密配合：

```text
┌────────────────────────────────────────────────────────┐
│             HarmonyOS 客户端 (com.example.msdpdemo)     │
│       Avatar 猫咪 / 气泡交互 / 双击主动记忆 / Chat 界面    │
└───────────────────────────┬────────────────────────────┘
                            │ WebSocket (127.0.0.1:10724)
                            ▼
┌────────────────────────────────────────────────────────┐
│             端侧 DSH Daemon (Node.js / Cordis)         │
│             + bonio-bridge 网关协议适配器                │
│                                                        │
│  ├── 会话管理: main (对话) / companion-memory (记忆)    │
│  └── 技能体系 (Skills Catalog):                         │
│       ├── ohos-cli-tool (系统设置/查询/状态控制)          │
│       ├── phone-use-harmonyos (宏观 GUI Agent 调度)     │
│       └── 应用专项 SOP (如 cap-cut 剪同款)                │
└───────────────────────────┬────────────────────────────┘
                            │ Shell 调用 (exec)
                            ▼
┌────────────────────────────────────────────────────────┐
│         phone-use-harmonyos 原生二进制 CLI              │
│                 (/data/local/bin/)                     │
│                                                        │
│  ├── UIInspector   ──> /bin/snapshot_display 截屏       │
│  ├── AutoGLMClient ──> libcurl 动态加载 ──> 视觉模型     │
│  ├── TaskExecutor  ──> 决策与动作解析循环               │
│  └── AppManager    ──> /bin/aa & /bin/uitest 执行输入   │
└────────────────────────────────────────────────────────┘
```

---

## 3. phone-use-harmonyos 核心技术实现

### 3.1 模块架构与职责

| 模块 | 关键文件 | 职责 |
|---|---|---|
| **CLI 解析** | `src/main.cpp`, `src/CliArgs.cpp` | 解析 `--task`, `--apikey`, `--max-step`, `--verbose`，处理信号（SIGINT/SIGTERM） |
| **配置管理** | `src/ConfigManager.cpp` | 加载与维护 `/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf` |
| **任务循环** | `src/TaskExecutor.cpp` | 驱动 Agent Loop：截图 -> 传图 -> 解析 Action -> 执行 -> 判断完成 |
| **屏幕捕获** | `src/UIInspector.cpp` | 调用系统 `snapshot_display` 输出 JPEG（按 0.5x 压缩保存到 `/data/local/tmp/`） |
| **视觉通信** | `src/AutoGLMClient.cpp` | 构造 OpenAI 兼容格式的多模态对话历史，Base64 转码截图，调用 API |
| **网络层** | `src/HttpClient.cpp` | 动态加载系统 `/system/lib64/platformsdk/libcurl_shared.z.so`，执行 HTTPS POST |
| **应用与操作** | `src/AppManager.cpp`, `src/AccessibilityHelper.cpp` | 映射常用 App 中文名至系统 Bundle Name，调用 `aa start` 与 `uitest` |

### 3.2 动作集（Action Set）定义
大模型在每一步返回标准化动作指令，由 `TaskExecutor` 逐帧解析并驱动设备：
- `do(action="Launch", app="应用名称")`：通过 `aa start -a EntryAbility -b <bundle>` 启动应用；
- `do(action="Tap", element=[x, y])`：基于百分比归一化坐标（0~999），通过 `uitest uiInput click` 点击；
- `do(action="Type", text="输入文本")`：通过 `uitest uiInput text` 键入字符；
- `do(action="Swipe", start=[x1, y1], end=[x2, y2])`：通过 `uitest uiInput swipe` 实现滑动手势；
- `do(action="Back")` / `do(action="Home")`：模拟物理返回键与主页键；
- `do(action="Wait", duration="2 seconds")`：控制页面加载等待；
- `finish(message="任务完成说明")`：终止任务并返回退出码 0。

### 3.3 退出码设计（Exit Codes）

| 退出码 | 标识符 | 说明 |
|---|---|---|
| `0` | `SUCCESS` | 任务正常执行完成（大模型调用了 finish） |
| `1` | `GENERAL_FAILURE` | 未知或通用执行异常 |
| `2` | `INVALID_ARGS` | 缺少必须参数（如未传 task 或未配置有效 api_key） |
| `4` | `TASK_FAILED` | 大模型返回失败或操作链路异常终止 |
| `5` | `TIMEOUT` | 超出最大步数限制（默认 20 步，最大 200 步） |
| `10` | `NETWORK_ERROR` | 网络连接中断或 HTTP 请求超时 |
| `11` | `INITIALIZATION_FAILED` | 系统工具链初始化失败（缺少 uitest 或 snapshot_display） |

---

## 4. SOP（标准操作流程）体系设计

### 4.1 为什么必须建立 SOP
在移动端 GUI-Agent 执行自动化任务时，单纯依赖视觉大模型的“自由发散式探索”存在显著弊端：
1. **成功率不可控**：不同应用的交互层级深（弹窗、Picker、复杂列表），模型容易在无关区域反复试探；
2. **Token 与步数浪费**：每一步都需要高分辨率截屏与大模型多轮推理，步骤过多极易导致超时（Step > 20）；
3. **关键边界失控**：涉及隐私、支付、确认提交等高危行为需要明确的约束边界。

因此，**SOP（Standard Operating Procedure）** 旨在为大模型提供经过验证的高效操作范式与领域知识。

### 4.2 SOP 的分层设计

系统将 SOP 分为两层：

```text
┌───────────────────────────────────────────────────────────┐
│ 1. 宏观 Agent 调度层 SOP (DSH Skill 规范)                 │
│    - 定义：任务是否适合转派给 phone-use                   │
│    - 关注：任务分解、参数约束、前置条件自检、异常诊断          │
└─────────────────────────────┬─────────────────────────────┘
                              │ 驱动
                              ▼
┌───────────────────────────────────────────────────────────┐
│ 2. 微观应用操作层 SOP (App 专项流程规范)                   │
│    - 定义：特定 App 的高成功率最佳操作路径 (如"剪同款"优先) │
│    - 关注：组件特征、系统 Picker 选择规则、容错与状态跳转      │
└───────────────────────────────────────────────────────────┘
```

### 4.3 核心应用 SOP 实践规范

#### SOP 案例 A：剪映（CapCut）视频剪辑规范
- **首选策略**：**优先使用“剪同款”功能**。相比多轨道自由剪辑，“剪同款”模板成功率提高 80% 以上。
- **操作标准步骤**：
  1. 点击底部 Tab 2【剪同款】；
  2. 搜索框键入目标主题（如“春节”、“美食”）；
  3. 选取模板后点击【剪同款】按钮；
  4. 触发系统相册选择器（System Picker）。
- **系统 Picker 交互红线**：
  > [!IMPORTANT]
  > 系统图片/视频 Picker 采用宫格布局：
  > - **点击宫格中央是“预览”**，无法完成选图；
  > - **必须精准点击宫格右下角的“小圆点/勾选框”** 才能真正将素材选中加入编辑流！

#### SOP 案例 B：HarmonyOS 系统级指令规范 (`harmonyos-device-commands`)
- **前台感知**：`aa dump -l | grep -B5 "state #FOREGROUND"` 判定当前活跃页面；
- **免二次跳转**：支持直接通过 `aa start -A ohos.want.action.viewData -U '<url>'` 唤起浏览器；
- **状态探测**：在无无障碍服务时，优雅退化至纯 `uitest uiInput` 模式执行。

#### SOP 案例 C：生活服务订单与复购规范（如美团/瑞幸）
- **规格保真原则**：复购任务必须忠实提取并核对“品名 / 规格 / 冰量 / 甜度 / 数量 / 门店 / 取餐方式”；
- **安全拦截边界**：加购物车与选规格由 Agent 自动执行，**“点击支付 / 立即下单”必须停留在确认页**，交由真实用户确认。

---

## 5. 配置与文件目录部署规范

手机端（HarmonyOS 设备）涉及的所有组件部署路径严格遵循以下规范：

```text
/data/local/
├── bin/
│   ├── phone-use-harmonyos               # 核心 C++ 可执行文件 (chmod +x)
│   └── dsh-daemon.sh                     # DSH 守护进程脚本
│
├── .phone-use-harmonyos/
│   ├── phone-use-harmonyos.conf          # 基础运行配置文件 (API Key, Endpoint, Model, SystemPrompt)
│   └── sop/                              # [可选] 原生应用级 SOP 配置文件目录
│
├── home/.dsh/skills/                     # DSH Agent 技能加载根目录
│   ├── phone-use-harmonyos/
│   │   └── SKILL.md                      # phone-use CLI 调度 SOP 与使用手册
│   ├── ohos-cli-tool/
│   │   ├── SKILL.md                      # 系统命令 SOP 与参考指南
│   │   └── configs/                      # 20+ 个系统能力 Schema 配置文件 (*.json)
│   └── <app-sop-name>/
│       └── SKILL.md                      # [扩展] 独立应用专项 SOP (如 cap-cut)
│
└── tmp/
    ├── screenshot_*.jpeg                 # 运行时截取的 0.5x 压缩图像
    └── screen.jpeg                       # 调试快照
```

### 5.1 核心配置文件模板
文件路径：`/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf`
```ini
# phone-use-harmonyos 运行时配置
GLM_API_KEY=your_bigmodel_api_key_here
GLM_ENDPOINT=https://open.bigmodel.cn/api/paas/v4/chat/completions
GLM_MODEL=autoglm-phone

# [可选] 自定义系统级 System Prompt（覆盖默认 prompt）
# SYSTEM_PROMPT=...
```

---

## 6. 构建、部署与运维验证 Checklist

### 6.1 跨平台编译流程（Mac/Linux/Windows）
1. 配置环境：
   ```bash
   export OHOS_NDK=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
   export CMAKE=$OHOS_NDK/build-tools/cmake/bin/cmake
   export NINJA=$OHOS_NDK/build-tools/cmake/bin/ninja
   ```
2. 执行编译：
   ```bash
   cd /Users/ohci/code/phone-use-harmonyos
   $CMAKE -B build -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA"
   $NINJA -C build
   # 产物：build/bin/phone-use-harmonyos
   ```

### 6.2 一键部署与真机验证流程
1. **网络与设备准备**：
   - 当前测试真机编号：`018014257R000686`；
   - 必须设置 `HDC_SERVER_PORT=8710` 避免默认服务连接异常。
2. **部署脚本执行**：
   ```bash
   # 1. 部署原生可执行文件
   ./skills/phone-use-harmonyos/scripts/deploy.sh

   # 2. 部署技能与 SOP 到 DSH 根目录并热重启 DSH
   ./tools/deploy-dsh-skills-ohos.sh
   ```
3. **验证自检命令**：
   ```bash
   # 检查版本
   hdc shell "/data/local/bin/phone-use-harmonyos --version"

   # 检查帮助
   hdc shell "/data/local/bin/phone-use-harmonyos --help"

   # 检查配置读取与网络通路
   hdc shell "/data/local/bin/phone-use-harmonyos --task '打开微信' --verbose --max-step 1"
   ```
