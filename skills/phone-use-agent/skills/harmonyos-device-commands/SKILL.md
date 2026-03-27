---
name: harmonyos-device-commands
description: Use when working with HarmonyOS device - for app management (install/uninstall/start), input simulation (touch/keyboard), screenshots, detecting current app, or accessing device storage paths. Runs directly on device.
---

# HarmonyOS Device Commands

## Overview

Commands for interacting with HarmonyOS device. Runs directly on device.

## Quick Reference

| Task | Command |
|------|---------|
| Start app | `aa start -a <ability> -b <bundle>` |
| Open URL | `aa start -A ohos.want.action.viewData -U '<url>'` |
| Current app | `aa dump -l \| grep -A1 "state #FOREGROUND"` |
| Screen size | `file /data/local/tmp/screen.jpeg` (after screenshot) |
| Install app | `bm install <app.hap>` |
| Uninstall app | `bm uninstall -n <bundle>` |
| Screenshot | `snapshot_display -f /data/local/tmp/screen.jpeg` |
| Touch tap | `uitest uiInput click <x> <y>` |
| Touch swipe | `uitest uiInput swipe <x1> <y1> <x2> <y2> <duration>` |
| Key press | `uitest uiInput keyEvent <Home\|Back\|keycode>` |
| Type text | `uitest uiInput text "文本"` |

## App Management (aa/bm tools)

### Start Application
```bash
# Start ability
aa start -a EntryAbility -b com.example.app

# Open URL in browser
aa start -A ohos.want.action.viewData -U 'https://example.com'

# Force stop
aa force-stop com.example.app
```

### Get Current Foreground App
```bash
# List running abilities and find foreground
aa dump -l | grep -B5 "state #FOREGROUND"

# Parse bundle name from output
aa dump -l | grep "app name \[" | head -1
```

Output format:
```
Mission ID #139
mission name #[#com.bundle:EntryAbility]
app name [com.bundle]
bundle name [com.bundle]
ability type [PAGE]
state #FOREGROUND
```

### Common Apps Reference

| App | Bundle | Ability |
|-----|--------|---------|
| **Social** |||
| 微信 | `com.tencent.wechat` | `EntryAbility` |
| QQ | `com.tencent.mqq` | `EntryAbility` |
| 微博 | `com.sina.weibo.stage` | `EntryAbility` |
| 小红书 | `com.xingin.xhs_hos` | `EntryAbility` |
| 知乎 | `com.zhihu.hmos` | `EntryAbility` |
| **Video** |||
| 抖音 | `com.ss.hm.ugc.aweme` | `MainAbility` |
| 哔哩哔哩 | `yylx.danmaku.bili` | `EntryAbility` |
| 快手 | `com.kuaishou.hmapp` | `EntryAbility` |
| 腾讯视频 | `com.tencent.videohm` | `EntryAbility` |
| 爱奇艺 | `com.qiyi.video.hmy` | `EntryAbility` |
| 剪映 | `com.lemon.hm.lv` | `MainAbility` |
| **E-commerce** |||
| 淘宝 | `com.taobao.taobao4hmos` | `EntryAbility` |
| 京东 | `com.jd.hm.mall` | `EntryAbility` |
| 拼多多 | `com.xunmeng.pinduoduo.hos` | `EntryAbility` |
| 美团 | `com.sankuai.hmeituan` | `EntryAbility` |
| 大众点评 | `com.sankuai.dianping` | `EntryAbility` |
| **Maps/Travel** |||
| 高德地图 | `com.amap.hmapp` | `EntryAbility` |
| 百度地图 | `com.baidu.hmmap` | `EntryAbility` |
| 滴滴出行 | `com.sdu.didi.hmos.psnger` | `EntryAbility` |
| **Music/Audio** |||
| QQ音乐 | `com.tencent.hm.qqmusic` | `EntryAbility` |
| 喜马拉雅 | `com.ximalaya.ting.xmharmony` | `EntryAbility` |
| **Tools** |||
| 飞书 | `com.ss.feishu` | `EntryAbility` |
| 支付宝 | `com.alipay.mobile.client` | `EntryAbility` |
| 豆包 | `com.larus.nova.hm` | `EntryAbility` |
| **System** |||
| 浏览器 | `com.huawei.hmos.browser` | `EntryAbility` |
| 相机 | `com.huawei.hmos.camera` | `MainAbility` |
| 相册 | `com.huawei.hmos.photos` | `EntryAbility` |
| 设置 | `com.huawei.hmos.settings` | `MainAbility` |
| 文件 | `com.huawei.hmos.files` | `EntryAbility` |
| 应用市场 | `com.huawei.hmsapp.appgallery` | `EntryAbility` |
| 音乐 | `com.huawei.hmsapp.music` | `EntryAbility` |
| 视频 | `com.huawei.hmsapp.himovie` | `EntryAbility` |
| 天气 | `com.huawei.hmsapp.totemweather` | `EntryAbility` |

### Special Abilities (Not EntryAbility)
```bash
# These apps use MainAbility instead
aa start -a MainAbility -b com.ss.hm.ugc.aweme     # 抖音
aa start -a MainAbility -b com.ss.hm.article.news  # 今日头条
aa start -a MainAbility -b com.huawei.hmos.camera  # 相机
aa start -a MainAbility -b com.huawei.hmos.settings # 设置
aa start -a MainAbility -b com.lemon.hm.lv         # 剪映
```

### Install/Uninstall
```bash
# Install app
bm install /path/to/app.hap

# Uninstall
bm uninstall -n com.example.app

# List installed apps
bm dump -a

# Query app ability name
bm dump -n <bundle> | grep -i "ability"
```

### Debug Commands
```bash
aa help     # aa tool help
bm help     # bm tool help
bm get -u   # Get device UDID
```

## Input Simulation (uitest uiInput)

### Touch Events
```bash
# Tap at coordinates
uitest uiInput click 500 500

# Double tap
uitest uiInput doubleClick 500 500

# Long press
uitest uiInput longClick 500 500

# Swipe from (x1,y1) to (x2,y2) with duration in ms
uitest uiInput swipe 100 500 900 500 300
```

### Keyboard Events
```bash
# Press Home
uitest uiInput keyEvent Home

# Press Back
uitest uiInput keyEvent Back

# Press key by code (2054 = Enter, 2055 = Delete)
uitest uiInput keyEvent 2054
```

### Text Input
```bash
# Type text (input field must be focused)
uitest uiInput text "hello world"

# Escape special characters
uitest uiInput text "hello \"world\""
```

## Screenshots & Screen Info

```bash
# Take screenshot
snapshot_display -f /data/local/tmp/screen.jpeg

# Alternative method
screenshot /data/local/tmp/screen.jpeg

# Get screen size from screenshot
snapshot_display -f /data/local/tmp/screen.jpeg
file /data/local/tmp/screen/screen.jpeg
# Output: ... 1080 x 2400, ...
```

## Storage Paths

| Content | Path |
|---------|------|
| Photos | `/storage/media/100/local/files/Photo/` |
| Videos | `/storage/media/100/local/files/Videos/` |
| Documents | `/storage/media/100/local/files/Docs/` |
| Downloads | `/storage/media/100/local/files/data/` |
| Temp | `/data/local/tmp/` |
| Tools | `/data/local/` (writable) |

## Common Mistakes

- **Wrong input tool**: Use `uitest uiInput` not `uinput` for reliable input
- **Wrong help flag**: Use `aa help` not `aa -h`
- **File permissions**: Use `/data/local/` for writable storage
- **Touch coordinates**: Origin (0,0) is top-left corner
- **Special abilities**: 抖音/相机/设置 use `MainAbility` not `EntryAbility`
- **uitest output**: "No Error" means success

## Getting Help

```bash
aa help           # App management
bm help           # Bundle management
uitest --help     # UI test commands
snapshot_display  # Screenshot options
```
