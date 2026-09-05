# Phone-Use（端侧 GUI Agent）与 SOP 架构设计与实现规范

> 日期：2026-09-05  
> 分支：`dsh`  
> 状态：代码已合并最新实现并在 HarmonyOS 设备端部署验证  
> 关联：[20260826-dsh-refactor-arch.md](20260826-dsh-refactor-arch.md), [20260902-dsh-msdp-memory-current.md](20260902-dsh-msdp-memory-current.md)

---

## 1. 总体背景与设计目标

### 1.1 端侧原生 GUI Agent
传统的移动端 GUI-Agent（如基于 PC 运行的 Open-AutoGLM）必须通过电脑与手机通过 HDC/ADB 建立调试通道，存在通信延迟高、离开 PC 即失效的严重瓶颈。

**`phone-use-harmonyos`**（跨平台抽象统一为 `phone-use-agent` 架构）实现了**端侧原生 C++ GUI Agent**：
- 编译为原生 AArch64 ELF 可执行程序，直接运行在 HarmonyOS 设备的 Linux 用户态环境（`/data/local/bin/phone-use-harmonyos`）；
- 本地直接通过平台抽象层（`HarmonyOSPlatform`）调用系统 `/bin/snapshot_display` 截屏与 `/bin/uitest uiInput` 模拟操作；
- 结合大模型视觉理解（GLM `autoglm-phone`），形成端侧自主闭环的 UI 规划与执行能力。

---

## 2. 系统分层架构与协作链路

在 Bonio 的系统体系中，`phone-use-harmonyos` 位于**设备底层执行层**：

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
│  ├── 会话管理: main (对话) / companion-memory (伴随记忆) │
│  └── 技能体系 (Skills Catalog):                         │
│       ├── ohos-cli-tool (系统能力与状态直接控制)          │
│       ├── phone-use-harmonyos (宏观 GUI Agent 调度)     │
│       └── 应用专项 SOP (如 cap-cut 剪映剪同款)            │
└───────────────────────────┬────────────────────────────┘
                            │ Shell 调用 (exec)
                            ▼
┌────────────────────────────────────────────────────────┐
│         phone-use-harmonyos 原生二进制 CLI              │
│                 (/data/local/bin/)                     │
│                                                        │
│  ├── SopManager    ──> 加载内置 SOP + 动态扫描 JSON SOP   │
│  ├── PlatformLayer ──> IPlatform (HarmonyOSPlatform)   │
│  │    ├── 截图捕获 ──> /bin/snapshot_display           │
│  │    └── 输入模拟 ──> /bin/uitest uiInput & aa start  │
│  ├── AutoGLMClient ──> libcurl 动态加载 ──> GLM 视觉模型 │
│  └── TaskExecutor  ──> 决策、动作解析、步进与状态循环      │
└────────────────────────────────────────────────────────┘
```

---

## 3. phone-use-harmonyos 核心模块实现

### 3.1 平台抽象层（Platform Abstraction Layer）
代码重构采用 `IPlatform` 纯虚接口定义设备能力，彻底解耦业务调度与底层平台特性：
- **`HarmonyOSPlatform`**：
  - 屏幕截图：`snapshot_display -f /data/local/tmp/screenshot_<timestamp>.jpeg`（支持按 0.5x 压缩保存）；
  - 屏幕尺寸：调用平台 Display 服务或缺省 `1320x2848`（支持归一化 0~1000 坐标映射）；
  - 点击/双击/长按：`/bin/uitest uiInput click / doubleClick / longClick`；
  - 滑动：`/bin/uitest uiInput swipe <x1> <y1> <x2> <y2> <duration>`；
  - 文本输入：`/bin/uitest uiInput text "<text>"`；
  - 按键模拟：`/bin/uitest uiInput keyEvent Back / Home`；
  - 应用启动：`aa start -a <Ability> -b <Bundle>`；
  - 线程休眠：针对 musl libc 特性采用 `usleep()`。
- **`PlatformFactory`**：
  - 编译期依据宏定义（`__OHOS__` / `__ANDROID__`）动态派发创建单例。

### 3.2 动作空间与退出码规范

| 动作 | 格式 | 底层实现 |
|---|---|---|
| 点击 | `do(action="Tap", element=[x,y])` | `/bin/uitest uiInput click <x> <y>` |
| 双击 | `do(action="Double Tap", element=[x,y])` | `/bin/uitest uiInput doubleClick <x> <y>` |
| 长按 | `do(action="Long Press", element=[x,y])` | `/bin/uitest uiInput longClick <x> <y>` |
| 滑动 | `do(action="Swipe", start=[x1,y1], end=[x2,y2])` | `/bin/uitest uiInput swipe <x1> <y1> <x2> <y2> 1000` |
| 输入 | `do(action="Type", text="文本")` | `/bin/uitest uiInput text "文本"` |
| 启动应用 | `do(action="Launch", app="微信")` | `aa start -a EntryAbility -b com.tencent.wechat` |
| 返回/主页 | `do(action="Back")` / `do(action="Home")` | `/bin/uitest uiInput keyEvent Back / Home` |
| 任务完成 | `finish(message="完成说明")` | 正常终止循环，返回退出码 0 |

退出码（Exit Codes）：
- `0` (`SUCCESS`)：任务顺利完成；
- `1` (`GENERAL_FAILURE`)：通用未知错误或用户 Ctrl+C 中断；
- `2` (`INVALID_ARGS`)：缺少必选参数；
- `4` (`TASK_FAILED`)：大模型判断失败或不可恢复的流程错误；
- `5` (`TIMEOUT`)：超出设定的 `--max-step` 步数（默认 20，上限 200）；
- `10` (`NETWORK_ERROR`)：HTTP 请求断开或超时；
- `11` (`INITIALIZATION_FAILED`)：平台组件初始化异常。

---

## 4. SOP（标准操作流程）架构与加载机制

最新重构落地了完备的 **`SopManager`** 体系，将领域的专业操作知识结构化，彻底消除模型在复杂交互中的盲目试探。

### 4.1 SOP 核心数据结构

```cpp
struct SopStep {
    int step_idx = 0;              // 步骤序号
    std::string name;             // 步骤名称（如"打开微信"、"定位目标订单"）
    std::string instruction;      // 具体操作指引（包含建议的 do(...) 动作）
    std::string expected_screen;  // 预期界面特征
};

struct SopDefinition {
    std::string name;                          // 唯一标识名（如 luckin_coffee_reorder）
    std::vector<std::string> keywords;         // 自动匹配关键词集合
    std::string target_app;                    // 目标应用中文名
    std::string description;                   // 流程描述
    std::vector<SopStep> steps;                // 步骤序列
    std::vector<std::string> traps_and_rules;  // 关键禁忌与安全红线规则
};
```

### 4.2 SOP 加载与发现路径
`SopManager::initialize()` 会按照以下优先级统一加载 SOP：
1. **内置 SOP（C++ 编译期固化）**：
   - `luckin_coffee_reorder`：瑞幸咖啡小程序历史订单再来一单；
   - `capcut_template`：剪映“剪同款”模板制作流程；
   - `wechat_send_message`：微信查找联系人并发送消息。
2. **设备端外部配置目录（核心部署位置）**：
   ```bash
   /data/local/.phone-use-harmonyos/sops/
   ```
   启动时会自动扫描该目录下所有的 `*.json` 文件并动态注册。
3. **工程相对配置目录**：`config/sops/`。
4. **CLI 指定的自定义目录或文件**：通过 `--sop <NAME_OR_PATH>` 直接指定。

### 4.3 动态 JSON SOP 规范定义
任何新增的应用 SOP 只需编写 JSON 格式文件并推送至设备端 `sops/` 目录即可，示例如下（`luckin_coffee_reorder.json`）：

```json
{
  "name": "luckin_coffee_reorder",
  "keywords": ["瑞幸", "咖啡", "再来一单", "点咖啡", "喝咖啡", "下单咖啡"],
  "target_app": "微信",
  "description": "微信瑞幸咖啡小程序历史订单复购（再来一单）标准操作流程",
  "steps": [
    {
      "step_idx": 1,
      "name": "打开微信",
      "instruction": "使用 do(action=\"Launch\", app=\"微信\") 启动微信",
      "expected_screen": "微信主界面"
    },
    {
      "step_idx": 2,
      "name": "进入瑞幸小程序",
      "instruction": "在微信首页下拉拉出小程序列表并点击'瑞幸咖啡'；或在搜索框输入'瑞幸咖啡'进入小程序",
      "expected_screen": "瑞幸咖啡小程序主页"
    },
    {
      "step_idx": 3,
      "name": "关闭营销弹窗",
      "instruction": "若界面出现新客红包、促销活动弹窗，寻找右上角或底部的'X'或'关闭'按钮并点击",
      "expected_screen": "瑞幸咖啡小程序主页（无弹窗）"
    },
    {
      "step_idx": 4,
      "name": "进入订单页面",
      "instruction": "点击底部导航栏中的'订单'标签页（通常为倒数第二个图标）",
      "expected_screen": "历史订单列表页面"
    },
    {
      "step_idx": 5,
      "name": "定位目标订单",
      "instruction": "在历史订单列表中寻找符合名称的饮品条目（若未在首屏看到，向上滑动屏幕继续查找）",
      "expected_screen": "目标订单卡片处于屏幕视野内"
    },
    {
      "step_idx": 6,
      "name": "点击再来一单",
      "instruction": "点击该订单卡片右下角的'再来一单'按钮，饮品及规格将加入购物车并跳转至确认结算页",
      "expected_screen": "订单结算确认页面"
    },
    {
      "step_idx": 7,
      "name": "核对门店与规格",
      "instruction": "在确认订单页核对自提门店名称与杯型规格。到达待支付结算页面即完成目标，调用 finish(message=\"已成功进入瑞幸确认订单页面，请核对自提门店并完成支付\")",
      "expected_screen": "待支付结算页"
    }
  ],
  "traps_and_rules": [
    "若小程序主页有弹窗阻碍，严禁直接盲点底部导航栏",
    "进入订单列表后请确认是否处于'历史订单'标签而非'当前订单'",
    "严禁自动点击最终的'立即支付'或输入密码，到达确认订单界面即视为成功"
  ]
}
```

### 4.4 智能匹配与 Prompt 注入机制
1. **显式指定模式**：用户可通过 `--sop <NAME_OR_PATH>` 指定；
2. **关键词自动模糊匹配**：若未显式指定，`SopManager::matchSopForTask(user_command)` 会遍历关键词库，根据用户自然语言任务自动关联；
3. **两阶段 Prompt 注入**：
   - **首轮 Prompt**：在初始用户输入中注入完整 SOP 引导块：
     ```text
     --- STANDARD OPERATING PROCEDURE (SOP) GUIDANCE ---
     [SOP: luckin_coffee_reorder] 微信瑞幸咖啡小程序历史订单复购（再来一单）标准操作流程
     Target Application: 微信
     STEP-BY-STEP WORKFLOW:
       Step 1: [打开微信] 使用 do(action="Launch", app="微信") 启动微信 (Expected: 微信主界面)
       ...
     CRITICAL RULES & TRAPS TO AVOID:
       ! 若小程序主页有弹窗阻碍，严禁直接盲点底部导航栏
       ! 严禁自动点击最终的'立即支付'或输入密码，到达确认订单界面即视为成功
     --- END OF SOP GUIDANCE ---
     ```
   - **后续步（Loop Steps）简明警示**：每一步截屏分析请求附带动态提醒：
     `[SOP Reminder] Follow the standard procedure for luckin_coffee_reorder. Do not skip required verification steps or violate safety rules.`

---

## 5. 手机设备端目录部署全景

在真机（HarmonyOS）环境中的目录与文件结构严格规范如下：

```text
/data/local/
├── bin/
│   ├── phone-use-harmonyos               # 核心原生二进制 (chmod +x)
│   ├── phone-use-agent                   # 软链接指向 phone-use-harmonyos
│   └── dsh-daemon.sh                     # DSH 守护进程脚本
│
├── .phone-use-harmonyos/
│   ├── phone-use-harmonyos.conf          # 主配置文件 (GLM_API_KEY, GLM_ENDPOINT, GLM_MODEL)
│   └── sops/                             # 【SOP 配置文件标准部署目录】
│       └── luckin_coffee_reorder.json    # 动态业务 SOP JSON 定义
│
├── home/.dsh/skills/                     # DSH 宏观技能目录
│   ├── phone-use-harmonyos/SKILL.md      # DSH 调度 phone-use CLI 规范
│   └── ohos-cli-tool/                    # 系统原生指令技能
│
└── tmp/
    └── screenshot_<timestamp>.jpeg       # 运行期临时截屏 (0.5x 压缩 JPEG)
```

---

## 6. 构建与真机部署验证 Checklist

### 6.1 编译命令（macOS 环境）
```bash
export OHOS_NDK=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
export CMAKE=$OHOS_NDK/build-tools/cmake/bin/cmake
export NINJA=$OHOS_NDK/build-tools/cmake/bin/ninja

cd /Users/ohci/code/phone-use-harmonyos
$CMAKE -B build -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA" -DBUILD_HARMONYOS=ON -DBUILD_TESTS=OFF
$NINJA -C build
```

### 6.2 部署到真机
```bash
export HDC_SERVER_PORT=8710
HDC=/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc

# 1. 部署二进制与软链
"$HDC" file send build/bin/phone-use-harmonyos /data/local/bin/phone-use-harmonyos
"$HDC" shell "chmod +x /data/local/bin/phone-use-harmonyos && ln -sf /data/local/bin/phone-use-harmonyos /data/local/bin/phone-use-agent"

# 2. 部署 SOP 配置文件
"$HDC" shell "mkdir -p /data/local/.phone-use-harmonyos/sops"
"$HDC" file send config/sops/luckin_coffee_reorder.json /data/local/.phone-use-harmonyos/sops/luckin_coffee_reorder.json
```

### 6.3 真机自检与 SOP 执行验证
1. **参数与选项自检**：
   ```bash
   hdc shell "/data/local/bin/phone-use-harmonyos --help"
   # 输出必须包含 --sop <NAME_OR_PATH> 选项说明
   ```
2. **SOP 显式指定执行**：
   ```bash
   hdc shell "/data/local/bin/phone-use-harmonyos --task '点一杯咖啡' --sop luckin_coffee_reorder --verbose --max-step 1"
   # 输出必须显示：
   # [SopManager] Loaded 3 built-in SOPs
   # [SopManager] Loaded 1 SOPs from /data/local/.phone-use-harmonyos/sops
   # [SOP] Using specified SOP: luckin_coffee_reorder
   ```
3. **SOP 关键词自动匹配执行**：
   ```bash
   hdc shell "/data/local/bin/phone-use-harmonyos --task '帮我喝咖啡' --max-step 1"
   # 输出必须显示：
   # [SOP] Auto-matched SOP: luckin_coffee_reorder for task: 帮我喝咖啡
   ```
