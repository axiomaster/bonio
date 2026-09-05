---
name: phone-use-harmonyos
description: "Drive this HarmonyOS device through natural-language UI automation. Runs the on-device GUI agent binary /data/local/bin/phone-use-harmonyos (built from github.com/axiomaster/phone-use-harmonyos), which screenshots the screen, sends it to the GLM vision model (autoglm-phone), and plans/executes UI actions (tap/type/swipe/launch app/back/home) until the task finishes. Use when the user asks to operate apps on this phone by describing what they want done — e.g. open WeChat and send a message, search Meituan for hotpot, make a DiDi booking, edit a video in CapCut."
whenToUse: "The user wants something done on this HarmonyOS phone via natural language — launching and driving apps, tapping/swiping/typing in any UI, reading and reacting to what is on screen — and a plain cli_tool query is not enough because the task needs multi-step UI interaction and visual understanding. The agent runs on-device, so invoke the binary directly."
---

# Phone Use HarmonyOS — on-device GUI agent

A native GUI-agent CLI that runs **on this device**: it captures the screen, sends the image to the GLM vision model, gets a next-action plan, and executes taps / swipes / text input / app launches through `uitest` until the task completes. No PC-side loop and no hdc needed.

## Prerequisites

1. Binary deployed: `/data/local/bin/phone-use-harmonyos` (verify with `ls -la /data/local/bin/phone-use-harmonyos`).
2. Config with a valid GLM API key at `/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf`:
   ```
   GLM_API_KEY=<your-bigmodel-api-key>
   GLM_ENDPOINT=https://open.bigmodel.cn/api/paas/v4/chat/completions
   GLM_MODEL=autoglm-phone
   ```
   (or pass `--apikey` per call).
3. On-device system tools the agent uses: `/bin/snapshot_display`, `/bin/uitest`, `/bin/aa` (all present).
4. Accessibility service: best with the OpenClaw accessibility service enabled; without it the agent continues in a limited uitest mode.

## How to invoke (on-device)

```bash
/data/local/bin/phone-use-harmonyos --task '你的任务描述' [--max-step N] [--verbose]

# quick sanity checks
/data/local/bin/phone-use-harmonyos --help
/data/local/bin/phone-use-harmonyos --version
```

## CLI reference

| Option | Meaning | Required |
|---|---|---|
| `--task <COMMAND>` | Task description in Chinese (natural language) | yes |
| `--sop <NAME_OR_PATH>` | Target SOP procedure name or JSON file (e.g. `luckin_coffee_reorder`) | no |
| `--apikey <KEY>` | GLM API key (optional if set in config file) | no |
| `--max-step <NUM>` | Max execution steps, default 35, max 200 | no |
| `--verbose` | Verbose output | no |
| `--help` / `-h` | Show help | no |
| `--version` | Show version | no |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Task completed |
| 1 | General failure |
| 2 | Invalid arguments |
| 4 | Task execution failed |
| 5 | Timeout (exceeded max steps, default 35) |
| 10 | Network error |
| 11 | Initialization failed |

## Action set the agent can perform

- `launch <app>` — start an app via `aa start`; known bundles: 剪映 `com.lemon.hm.lv`, 图库 `com.huawei.hmos.photos`, 抖音 `com.ss.hm.ugc.aweme`, 微信 `com.tencent.wechat`, 美团 `com.sankuai.meituan`
- `tap [x,y]`, `type <text>`, `swipe [x1,y1]→[x2,y2]`, `long press`, `double tap`
- `back`, `home`, `wait <duration>`
- `finish(message)` — task complete

## Worked examples

```bash
# Simple: open WeChat
/data/local/bin/phone-use-harmonyos --task '打开微信'

# Multi-step
/data/local/bin/phone-use-harmonyos --task '打开美团搜索附近的火锅店' --max-step 40

# Verbose debug
/data/local/bin/phone-use-harmonyos --task '打开设置' --verbose

# Long creative pipeline
/data/local/bin/phone-use-harmonyos --task '帮我在图库中查找春节期间拍摄的照片，使用剪映剪辑并配乐，剪成春节短片，并发布在抖音上' --max-step 60 --verbose
```

## Tips

- **One task per call.** Describe a single clear objective in Chinese; raise `--max-step` (≤200) for long flows.
- **Default 20 steps** — screenshot → GLM → action per step. Long tasks can take minutes; use generous timeouts.
- **Screenshots** land in `/data/local/tmp/screenshot_*.jpeg` (0.5x).
- **Failure diagnosis:** run with `--verbose`; watch `[AutoGLMClient]` HTTP status (401 = bad/expired API key; 10 = network error).
- The GLM call needs internet access from the device.

## Pitfalls

- **API key validity** — a 401 `身份验证失败` means the key in `/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf` is invalid/expired; update it (or pass `--apikey`) before retrying.
- **Real device side effects** — performs real taps/swipes/launches on the user's phone; confirm before destructive flows (payments, logins, sending messages).
- **Accessibility warning** — if the log says `Accessibility service not enabled`, the agent continues with uitest but may be less robust.
- **Long tasks** — a 20-step task can take a couple of minutes; use a generous bash timeout and consider background execution.
