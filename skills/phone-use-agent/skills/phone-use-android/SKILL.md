---
name: phone-use-android
description: Use when you need to control an Android device to perform UI automation tasks using natural language commands
---

# Phone Use Android

Android 设备 GUI 自动化工具，通过自然语言控制手机执行任务。

## When to Use

**Use this skill when:**
- 需要在 Android 设备上执行 UI 自动化任务
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

1. **设备连接**: Android 设备已通过 ADB 连接
2. **部署**: `phone-use-agent` 已部署到 `/data/local/tmp/`
3. **权限**: 需要必要的 shell 权限
4. **配置**: GLM API 密钥已配置

## How to Use

### Basic Command

```bash
/data/local/tmp/phone-use-agent --apikey "sk-xxx" --task "你的任务描述"
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
| Tap | `input tap x y` |
| Type | `input text "text"` |
| Swipe | `input swipe x1 y1 x2 y2 duration` |
| Long Press | `input swipe x y x y 500` |
| Double Tap | Two quick taps |
| Back | `input keyevent KEYCODE_BACK` |
| Home | `input keyevent KEYCODE_HOME` |
| Launch | `am start -n package/activity` |
| Screenshot | `screencap -p path` |

## Supported Apps

### 社交通讯

| 应用 | 包名 |
|------|------|
| 微信 | `com.tencent.mm` |
| QQ | `com.tencent.mobileqq` |
| 微博 | `com.sina.weibo` |
| Telegram | `org.telegram.messenger` |
| WhatsApp | `com.whatsapp` |
| Twitter/X | `com.twitter.android` |

### 电商购物

| 应用 | 包名 |
|------|------|
| 淘宝 | `com.taobao.taobao` |
| 淘宝闪购 | `com.taobao.taobao` |
| 京东 | `com.jingdong.app.mall` |
| 京东秒送 | `com.jingdong.app.mall` |
| 拼多多 | `com.xunmeng.pinduoduo` |
| 小红书 | `com.xingin.xhs` |
| Temu | `com.einnovation.temu` |

### 生活服务

| 应用 | 包名 |
|------|------|
| 美团 | `com.sankuai.meituan` |
| 大众点评 | `com.dianping.v1` |
| 饿了么 | `me.ele` |
| 肯德基 | `com.yek.android.kfc.activitys` |
| 麦当劳 | `com.mcdonalds.app` |

### 地图导航

| 应用 | 包名 |
|------|------|
| 高德地图 | `com.autonavi.minimap` |
| 百度地图 | `com.baidu.BaiduMap` |
| Google Maps | `com.google.android.apps.maps` |
| Osmand | `net.osmand` |

### 出行旅游

| 应用 | 包名 |
|------|------|
| 携程 | `ctrip.android.view` |
| 铁路12306 | `com.MobileTicket` |
| 去哪儿旅行 | `com.Qunar` |
| 滴滴出行 | `com.sdu.didi.psnger` |
| Booking | `com.booking` |
| Expedia | `com.expedia.bookings` |

### 视频娱乐

| 应用 | 包名 |
|------|------|
| 抖音 | `com.ss.android.ugc.aweme` |
| TikTok | `com.zhiliaoapp.musically` |
| 快手 | `com.smile.gifmaker` |
| bilibili | `tv.danmaku.bili` |
| 腾讯视频 | `com.tencent.qqlive` |
| 爱奇艺 | `com.qiyi.video` |
| 优酷视频 | `com.youku.phone` |
| 芒果TV | `com.hunantv.imgo.activity` |
| 红果短剧 | `com.phoenix.read` |
| VLC | `org.videolan.vlc` |

### 音乐音频

| 应用 | 包名 |
|------|------|
| 网易云音乐 | `com.netease.cloudmusic` |
| QQ音乐 | `com.tencent.qqmusic` |
| 汽水音乐 | `com.luna.music` |
| 喜马拉雅 | `com.ximalaya.ting.android` |

### 资讯阅读

| 应用 | 包名 |
|------|------|
| 番茄小说 | `com.dragon.read` |
| 番茄免费小说 | `com.dragon.read` |
| 七猫免费小说 | `com.kmxs.reader` |
| 豆瓣 | `com.douban.frodo` |
| 知乎 | `com.zhihu.android` |
| 腾讯新闻 | `com.tencent.news` |
| 今日头条 | `com.ss.android.article.news` |
| Quora | `com.quora.android` |
| Reddit | `com.reddit.frontpage` |

### 办公工具

| 应用 | 包名 |
|------|------|
| 飞书 | `com.ss.android.lark` |
| QQ邮箱 | `com.tencent.androidqqmail` |
| Joplin | `net.cozic.joplin` |

### AI & 工具

| 应用 | 包名 |
|------|------|
| 豆包 | `com.larus.nova` |
| Chrome | `com.android.chrome` |

### 健康运动

| 应用 | 包名 |
|------|------|
| Keep | `com.gotokeep.keep` |
| 美柚 | `com.lingan.seeyou` |

### 房产

| 应用 | 包名 |
|------|------|
| 贝壳找房 | `com.lianjia.beike` |
| 安居客 | `com.anjuke.android.app` |

### 金融

| 应用 | 包名 |
|------|------|
| 同花顺 | `com.hexin.plat.android` |

### 游戏

| 应用 | 包名 |
|------|------|
| 星穹铁道 | `com.miHoYo.hkrpg` |
| 崩坏：星穹铁道 | `com.miHoYo.hkrpg` |
| 恋与深空 | `com.papegames.lysk.cn` |

### Google 应用

| 应用 | 包名 |
|------|------|
| Gmail | `com.google.android.gm` |
| Google Drive | `com.google.android.apps.docs` |
| Google Docs | `com.google.android.apps.docs.editors.docs` |
| Google Slides | `com.google.android.apps.docs.editors.slides` |
| Google Calendar | `com.google.android.calendar` |
| Google Contacts | `com.google.android.contacts` |
| Google Keep | `com.google.android.keep` |
| Google Tasks | `com.google.android.apps.tasks` |
| Google Chat | `com.google.android.apps.dynamite` |
| Google Fit | `com.google.android.apps.fitness` |
| Google Play Store | `com.android.vending` |
| Google Play Books | `com.google.android.apps.books` |
| Google Files | `com.google.android.apps.nbu.files` |

### Android 系统应用

| 应用 | 包名 |
|------|------|
| Settings | `com.android.settings` |
| Clock | `com.android.deskclock` |
| Contacts | `com.android.contacts` |
| Files | `com.android.fileexplorer` |
| Audio Recorder | `com.android.soundrecorder` |

## Examples

### Example 1: 打开应用

```bash
/data/local/tmp/phone-use-agent --apikey "sk-xxx" --task "打开微信"
```

### Example 2: 搜索并操作

```bash
/data/local/tmp/phone-use-agent --apikey "sk-xxx" --task "在美团搜索附近的火锅店"
```

### Example 3: 带详细输出

```bash
/data/local/tmp/phone-use-agent --apikey "sk-xxx" --task "滴滴打车去锦业路127号" --verbose
```

### Example 4: 复杂多步骤任务

```bash
/data/local/tmp/phone-use-agent --apikey "sk-xxx" --task "在淘宝上搜索iPhone手机壳并加入购物车" --max-step 60 --verbose
```

### Example 5: 国际应用

```bash
/data/local/tmp/phone-use-agent --apikey "sk-xxx" --task "Open Chrome and search for best restaurants nearby"
```

## How It Works

1. **截图**: 使用 `screencap` 捕获当前屏幕
2. **AI 分析**: 将截图发送到 GLM 视觉模型，AI 分析屏幕内容并规划下一步操作
3. **执行操作**: 使用 `input` 命令执行 UI 操作
4. **循环**: 重复上述过程直到任务完成或达到最大步数限制

## Deployment

### 构建

```bash
./build_android.sh Release
```

### 部署

```bash
adb push build/android/bin/phone-use-agent /data/local/tmp/
adb shell 'chmod +x /data/local/tmp/phone-use-agent'
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

1. **任务描述清晰**: 使用简洁明了的描述任务目标
2. **一次一个任务**: 每次执行一个明确的任务，避免复合任务
3. **使用 verbose 模式**: 调试时使用 `--verbose` 查看详细执行过程
4. **Ctrl+C 中断**: 可以使用 Ctrl+C 中断正在执行的任务
5. **中英文支持**: 支持中文和英文任务描述

## Limitations

- 默认最大执行步数: 20 步（可通过 `--max-step` 调整）
- 需要 GLM API 网络连接
- 部分敏感操作（支付、登录）可能需要用户手动确认
- 复杂的图形验证码可能无法自动处理
- 需要 ROOT 权限或 ADB shell 权限

## Troubleshooting

| 问题 | 解决方案 |
|------|----------|
| 网络错误 | 确保设备可以访问互联网 |
| 任务失败 | 使用 `--verbose` 查看详细日志 |
| 设备未连接 | 检查 ADB 连接状态： `adb devices` |
| 初始化失败 | 检查 API key 是否正确配置 |
| 权限不足 | 确保通过 ADB shell 执行或获取 ROOT 权限 |
