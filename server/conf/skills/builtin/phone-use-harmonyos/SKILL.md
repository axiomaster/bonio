---
name: phone-use-harmonyos
description: Use when you need to control a HarmonyOS device to perform UI automation tasks using natural language commands
---

# Phone Use HarmonyOS

HarmonyOS 设备 GUI 自动化工具，通过自然语言控制手机执行任务。

## When to Use

**Use this skill when:**
- 需要在 HarmonyOS 设备上执行 UI 自动化任务
- 需要通过自然语言控制手机操作
- 需要启动应用、点击、滑动、输入文本等操作
- 需要让 AI 根据屏幕内容自动规划操作步骤

**Examples of valid use cases:**
- "打开微信发送消息给张三"
- "在美团上搜索附近的火锅店"
- "滴滴打车去机场"
- "打开设置调整亮度"
- "在淘宝上搜索商品并加入购物车"

## Prerequisites

1. **设备连接**: HarmonyOS 设备已通过 HDC 连接
2. **部署**: `phone-use-agent` 已部署到 `/data/local/bin/`
3. **配置**: GLM API 密钥已配置

## How to Use

### Basic Command

```bash
/data/local/bin/phone-use-agent --apikey "sk-xxx" --task "你的任务描述"
```

### Command Line Options

| 参数 | 说明 | 必需 |
|------|------|------|
| `--apikey` | GLM API 密钥 | 是（或配置文件中设置） |
| `--task` | 任务描述（中文） | 是 |
| `--max-step` | 最大执行步数 [默认: 20] | 否 |
| `--verbose` | 详细输出模式 | 否 |
| `--help` | 显示帮助信息 | 否 |

### Exit Codes

| 代码 | 名称 | 含义 |
|------|------|------|
| 0 | SUCCESS | 任务成功完成 |
| 1 | GENERAL_FAILURE | 通用错误 |
| 2 | INVALID_ARGS | 参数无效 |
| 4 | TASK_FAILED | 任务执行失败 |
| 5 | TIMEOUT | 超时（超过最大步数） |
| 10 | NETWORK_ERROR | 网络错误 |
| 11 | INITIALIZATION_FAILED | 初始化失败 |

### Supported Actions

| 操作 | 命令 |
|------|------|
| Tap | `/bin/uitest uiInput click x y` |
| Type | `/bin/uitest uiInput text "text"` |
| Swipe | `/bin/uitest uiInput swipe x1 y1 x2 y2 duration` |
| Long Press | `/bin/uitest uiInput longClick x y` |
| Double Tap | `/bin/uitest uiInput doubleClick x y` |
| Back | `/bin/uitest uiInput keyEvent Back` |
| Home | `/bin/uitest uiInput keyEvent Home` |
| Launch | `aa start -a Ability -b Bundle` |
| Screenshot | `snapshot_display -w 660 -h 1424 -f path` |

## Supported Apps

### 社交通讯

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 微信 | `com.tencent.wechat` | EntryAbility |
| QQ | `com.tencent.mqq` | EntryAbility |
| 微博 | `com.sina.weibo.stage` | EntryAbility |
| 企业微信 | `com.tencent.wework.hmos` | EntryAbility |

### 电商购物

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 淘宝 | `com.taobao.taobao4hmos` | Taobao_mainAbility |
| 京东 | `com.jd.hm.mall` | EntryAbility |
| 拼多多 | `com.xunmeng.pinduoduo.hos` | EntryAbility |
| 小红书 | `com.xingin.xhs_hos` | EntryAbility |
| 得物 | `com.dewu.hos` | HomeAbility |
| 闲鱼 | `com.taobao.idlefish4ohos` | EntryAbility |
| 唯品会 | `com.vip.hosapp` | EntryAbility |
| 转转 | `com.zhuanzhuan.hmoszz` | EntryAbility |

### 生活服务

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 美团 | `com.sankuai.hmeituan` | EntryAbility |
| 美团外卖 | `com.meituan.takeaway` | EntryAbility |
| 大众点评 | `com.sankuai.dianping` | EntryAbility |
| 滴滴出行 | `com.sdu.didi.hmos.psnger` | EntryAbility |
| 支付宝 | `com.alipay.mobile.client` | EntryAbility |
| 海底捞 | `com.haidilao.haros` | EntryAbility |

### 地图导航

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 高德地图 | `com.amap.hmapp` | EntryAbility |
| 百度地图 | `com.baidu.hmmap` | EntryAbility |
| 华为地图 | `com.huawei.hmos.maps.app` | EntryAbility |

### 出行旅游

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 铁路12306 | `com.chinarailway.ticketingHM` | EntryAbility |
| 同程旅行 | `com.tongcheng.hmos` | EntryAbility |

### 视频娱乐

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 抖音 | `com.ss.hm.ugc.aweme` | MainAbility |
| 快手 | `com.kuaishou.hmapp` | EntryAbility |
| 快手极速版 | `com.kuaishou.hmnebula` | EntryAbility |
| bilibili | `yylx.danmaku.bili` | EntryAbility |
| 腾讯视频 | `com.tencent.videohm` | AppAbility |
| 爱奇艺 | `com.qiyi.video.hmy` | EntryAbility |
| 芒果TV | `com.mgtv.phone` | EntryAbility |

### 音乐音频

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| QQ音乐 | `com.tencent.hm.qqmusic` | EntryAbility |
| 汽水音乐 | `com.luna.hm.music` | MainAbility |
| 喜马拉雅 | `com.ximalaya.ting.xmharmony` | MainBundleAbility |
| 华为音乐 | `com.huawei.hmsapp.music` | MainAbility |

### 资讯阅读

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 今日头条 | `com.ss.hm.article.news` | MainAbility |
| 知乎 | `com.zhihu.hmos` | PhoneAbility |
| 百度 | `com.baidu.baiduapp` | EntryAbility |
| 华为阅读 | `com.huawei.hmsapp.books` | MainAbility |

### 办公工具

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 飞书 | `com.ss.feishu` | EntryAbility |
| WPS | `cn.wps.mobileoffice.hap` | DocumentAbility |
| 豆包 | `com.larus.nova.hm` | MainAbility |
| UC浏览器 | `com.uc.mobile` | EntryAbility |
| 迅雷 | `com.xunlei.thunder` | EntryAbility |

### 工具应用

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 美图秀秀 | `com.meitu.meitupic` | MainAbility |
| 扫描全能王 | `com.intsig.camscanner.hap` | EntryAbility |
| 搜狗输入法 | `com.sogou.input` | EntryAbility |

### 金融银行

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 建设银行 | `com.ccb.mobilebank.hm` | CcbMainAbility |
| 国家税务总局 | `cn.gov.chinatax.gt4.hm` | EntryAbility |

### 运营商

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 中国移动 | `com.droi.tong` | EntryAbility |
| 中国联通 | `com.sinovatech.unicom.ha` | EntryAbility |

### HarmonyOS 系统应用

#### 工具类

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 设置 | `com.huawei.hmos.settings` | MainAbility |
| 浏览器 | `com.huawei.hmos.browser` | MainAbility |
| 相机 | `com.huawei.hmos.camera` | MainAbility |
| 相册/图库 | `com.huawei.hmos.photos` | MainAbility |
| 文件管理器 | `com.huawei.hmos.filemanager` | MainAbility |
| 计算器 | `com.huawei.hmos.calculator` | CalculatorAbility |
| 日历 | `com.huawei.hmos.calendar` | MainAbility |
| 时钟 | `com.huawei.hmos.clock` | phone |
| 录音机 | `com.huawei.hmos.soundrecorder` | MainAbility |
| 笔记/备忘录 | `com.huawei.hmos.notepad` | MainAbility |
| 邮件 | `com.huawei.hmos.email` | ApplicationAbility |
| 云盘/云空间 | `com.huawei.hmos.clouddrive` | MainAbility |
| 查找设备 | `com.huawei.hmos.finddevice` | EntryAbility |

#### 通讯类

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 电话/拨号 | `com.ohos.callui` | ServiceAbility |
| 联系人/通讯录 | `com.ohos.contacts` | MainAbility |
| 短信/信息 | `com.ohos.mms` | MainAbility |

#### 生活服务

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 健康/运动健康 | `com.huawei.hmos.health` | Activity_card_entryAbility |
| 钱包/华为钱包 | `com.huawei.hmos.wallet` | MainAbility |
| 智慧生活 | `com.huawei.hmos.ailife` | EntryAbility |
| 智能助手/小艺 | `com.huawei.hmos.vassistant` | AiCaptionServiceExtAbility |

#### 华为服务

| 应用 | 包名 (Bundle) | Ability |
|------|--------------|---------|
| 应用市场 | `com.huawei.hmsapp.appgallery` | MainAbility |
| 华为视频 | `com.huawei.hmsapp.himovie` | MainAbility |
| 天气/华为天气 | `com.huawei.hmsapp.totemweather` | MainAbility |
| 主题 | `com.huawei.hmsapp.thememanager` | MainAbility |
| 搜索/华为搜索 | `com.huawei.hmsapp.hisearch` | MainAbility |
| 游戏中心 | `com.huawei.hmsapp.gamecenter` | MainAbility |
| 会员中心/我的华为 | `com.huawei.hmos.myhuawei` | EntryAbility |
| 指南针 | `com.huawei.hmsapp.compass` | EntryAbility |

## Examples

### Example 1: 打开应用

```bash
/data/local/bin/phone-use-agent --apikey "sk-xxx" --task "打开微信"
```

### Example 2: 搜索并操作

```bash
/data/local/bin/phone-use-agent --apikey "sk-xxx" --task "在美团搜索附近的火锅店"
```

### Example 3: 带详细输出

```bash
/data/local/bin/phone-use-agent --apikey "sk-xxx" --task "滴滴打车去锦业路127号" --verbose
```

### Example 4: 复杂多步骤任务

```bash
/data/local/bin/phone-use-agent --apikey "sk-xxx" --task "帮我在图库中查找春节期间拍摄的照片" --max-step 60 --verbose
```

## How It Works

1. **截图**: 使用 `snapshot_display` 捕获当前屏幕（0.5x 尺寸以节省带宽）
2. **AI 分析**: 将截图发送到 GLM 视觉模型，AI 分析屏幕内容并规划下一步操作
3. **执行操作**: 使用 `/bin/uitest uiInput` 命令执行 UI 操作
4. **循环**: 重复上述过程直到任务完成或达到最大步数限制

## Deployment

### 构建

```bash
./build_harmonyos.sh Release
```

### 部署

```bash
hdc file send build-harmonyos/bin/phone-use-agent /data/local/bin/
hdc shell 'chmod +x /data/local/bin/phone-use-agent'
```

## Configuration

配置文件路径: `/data/local/.phone-use-agent/phone-use-agent.conf`

```json
{
  "glm_api_key": "your-bigmodel-api-key",
  "glm_endpoint": "https://open.bigmodel.cn/api/paas/v4/chat/completions"
}
```

## Tips for Best Results

1. **任务描述清晰**: 使用简洁明了的中文描述任务目标
2. **一次一个任务**: 每次执行一个明确的任务，避免复合任务
3. **使用 verbose 模式**: 调试时使用 `--verbose` 查看详细执行过程
4. **Ctrl+C 中断**: 可以使用 Ctrl+C 中断正在执行的任务
5. **图库选片**: 一键成片最多支持 50 张照片，避免使用"全选"

## Limitations

- 默认最大执行步数: 20 步（可通过 `--max-step` 调整）
- 需要 GLM API 网络连接
- 部分敏感操作（支付、登录）可能需要用户手动确认
- 复杂的图形验证码可能无法自动处理

## Troubleshooting

| 问题 | 解决方案 |
|------|----------|
| 网络错误 | 确保设备可以访问互联网 |
| 任务失败 | 使用 `--verbose` 查看详细日志 |
| 设备未连接 | 检查 HDC 连接状态：`hdc list targets` |
| 初始化失败 | 检查 API key 是否正确配置 |
