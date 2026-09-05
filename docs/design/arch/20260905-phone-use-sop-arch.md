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
- `5` (`TIMEOUT`)：超出设定的 `--max-step` 步数（默认 35，上限 200）；
- `10` (`NETWORK_ERROR`)：HTTP 请求断开或超时；
- `11` (`INITIALIZATION_FAILED`)：平台组件初始化异常。

### 3.3 TaskExecutor 鲁棒性增强：多步动作周期死循环检测与纠偏
在真实应用交互（如微信小程序或多 Tab 界面）中，大模型陷入死循环往往不是单个动作连续点两次，而是由 3-4 个不同动作构成的闭环（如：`点击我的 -> 查看订单 -> 点击再来一单 -> 菜单购物车浮起 -> 未跳转结算页误以为未生效 -> 再次点击我的`）。

为彻底解决此类多步闭环死循环问题，`TaskExecutor` 实现了滑动窗口检测与主动纠偏机制：
1. **滑动窗口维护**：在执行循环中维护最近 16 步的动作序列 `recent_actions`；
2. **多步周期循环检测（Cycle Detection）**：
   - 自动检测周期长度 $L \in [2, 5]$ 的动作循环（如 A-B-A-B、A-B-C-A-B-C、A-B-C-D-A-B-C-D）；
   - 当最近 $2 \times L$ 步呈现严格的周期性重复时，立即判定陷入闭环；
3. **高频动作统计（Frequency Detection）**：
   - 统计最近 8 步窗口内同一动作出现的频次，若同一动作执行 $\ge 3$ 次（即便中间穿插等待或滑动），判定为疑似卡死；
4. **主动注入破环 Prompt**：
   - 检测到循环时，向 `conversation_history` 注入系统级提示：
     ```text
     Notice: Loop detected! You seem to be repeating a sequence of actions without making progress.
     Please carefully inspect the current screen:
     1. Check if the previous action has ALREADY succeeded (e.g. items added to cart, or a '去结算' / '结算' / '确定' / '提交' button is already visible).
     2. DO NOT navigate back or repeatedly re-add items if the desired button is already on screen!
     3. If a checkout or next-step button (e.g. '去结算') is present, click it directly. If the target page is reached, call finish().
     ```

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
   - `luckin_coffee_reorder`：瑞幸咖啡小程序历史订单再来一单直达免密支付；
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
      "instruction": "使用 do(action=\"Launch\", app=\"微信\") 启动微信，若已在微信内请确认处于微信主界面",
      "expected_screen": "微信主界面"
    },
    {
      "step_idx": 2,
      "name": "搜索并进入瑞幸小程序",
      "instruction": "点击微信首页顶部搜索框；当搜索框激活或键盘弹起时，使用 do(action=\"Type\", text=\"瑞幸咖啡\") 输入；在搜索结果列表中点击带有'小程序'标识的'瑞幸咖啡'条目进入其主页",
      "expected_screen": "瑞幸咖啡小程序主页"
    },
    {
      "step_idx": 3,
      "name": "处理权限与营销弹窗",
      "instruction": "若出现'获取位置信息'或'微信授权'系统弹窗，点击'允许'；若出现营销红包优惠弹窗，点击右上角或底部的'X'或'关闭'按钮",
      "expected_screen": "瑞幸咖啡小程序主页（无弹窗阻碍）"
    },
    {
      "step_idx": 4,
      "name": "进入我的页面定位历史订单",
      "instruction": "瑞幸小程序底部导航栏为[首页|菜单|即享|会员卡|我的]，无独立'订单'标签。请点击底部最右侧的'我的'导航进入个人中心查看历史订单",
      "expected_screen": "个人中心页面（含最近订单或我的订单）"
    },
    {
      "step_idx": 5,
      "name": "触发再来一单",
      "instruction": "在'我的'页面找到目标饮品订单卡片（或点击'我的订单'查找），点击该订单右下角的'再来一单'按钮。若弹出'请确认自提门店'或'在买过的门店下单'弹窗，直接点击确认或选择该门店",
      "expected_screen": "跳转至点单菜单页且底部浮起已选购商品购物车栏"
    },
    {
      "step_idx": 6,
      "name": "点击底部购物车去结算",
      "instruction": "【进行中，非终点】点击'再来一单'后页面会自动跳转至点单菜单页，且屏幕底部会升起购物车栏（显示已选购商品及价格），右下角有高亮的蓝色'去结算'按钮。'去结算'仅仅是中间步骤，绝对不算任务完成！严禁在此处停下调用 finish，也严禁返回'我的'或重复点击'再来一单'；必须立即点击右下角蓝色的'去结算'按钮进入确认订单页！",
      "expected_screen": "正在进入确认订单结算页面"
    },
    {
      "step_idx": 7,
      "name": "到达确认订单并停在免密支付页面",
      "instruction": "【终点页面】点击'去结算'后将进入'确认订单'页面。必须一直执行到页面展示【免密支付】（或【立即支付】）按钮这一步才能停止！注意：若页面弹出'超值换购'或推荐加购糕点饼干（如猫爪饼干、慕斯蛋糕等）的营销弹窗，这属于营销推荐加价购，原咖啡订单就在背景层中，切勿误以为买错商品而点击返回！可点击弹窗底部白圈'X'关闭换购弹窗；只要页面已显示【免密支付】（或【立即支付】）按钮，即代表任务圆满达成！严禁点击'免密支付'或'立即支付'发起实际扣款，必须立即调用 finish(message=\"已成功到达瑞幸咖啡免密支付页面，请核对自提门店与金额后手动确认支付\") 结束任务！",
      "expected_screen": "包含'确认订单'标题与'免密支付'按钮的待支付界面"
    }
  ],
  "traps_and_rules": [
    "【核心完成条件】下单任务必须一直执行到展示【免密支付】（或【立即支付】）按钮这一步才能停止并调用 finish！'去结算'只是将购物车送入结算流程的中间步骤，绝对不算完成！",
    "【营销换购弹窗防误退】进入确认订单页时若弹出'超值换购'（推荐猫爪饼干、慕斯蛋糕、大福等），这是平台推荐的加价换购营销弹窗，绝对不是你的商品买错了！严禁点击返回！可点击弹窗底部圆圈'X'关闭弹窗，或者只要页面底部已露出【免密支付】按钮，必须直接调用 finish(...) 停在免密支付这一步。",
    "【支付安全红线】严禁点击【免密支付】或【立即支付】按钮，因为免密支付会立即扣费！任务必须停在免密支付按钮展示的界面交由用户手动确认支付。",
    "【防重复加车】点击'再来一单'后只要页面进入菜单并显示购物车浮层或'去结算'，商品已在车内，严禁再次返回'我的'去重复点击'再来一单'，必须直接点'去结算'。",
    "瑞幸小程序底部导航栏只有[首页|菜单|即享|会员卡|我的]，寻找订单必须点击最右侧的'我的'，没有独立的'订单'标签栏。",
    "点击搜索框后必须使用 do(action=\"Type\", text=\"瑞幸咖啡\") 输入搜索词，并在结果中点击带有'小程序'标签的条目。",
    "若小程序有弹窗阻碍（如优惠券、位置授权），必须先点击关闭'X'或允许，严禁盲点。"
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

### 6.4 端到端全流程验证（直达免密支付）
在已连接的 HarmonyOS 真机执行实测任务：
```bash
hdc shell "/data/local/bin/phone-use-harmonyos --task '帮我再买一杯上次的咖啡' --sop luckin_coffee_reorder --verbose"
```
实测验证指标：
- **步骤效率**：10 步精准收敛（Exit code 0）；
- **行为轨迹**：启动微信 → 进入瑞幸小程序 → 点击“我的” → 定位“埃塞瑰夏冷萃”订单并点击“再来一单” → 商品详情点击“立即购买”推进结算 → 进入确认订单页遇到“超值换购”营销弹窗主动点击“X”关闭 → 准确识别到底部【免密支付】按钮；
- **安全守卫**：停在“确认订单”页面，未触发代扣，立即调用 `finish(...)` 结束任务交由用户确认，购物车商品严格为 1 杯无重复加车。
