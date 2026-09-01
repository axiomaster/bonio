---
name: phone-use-harmonyos
description: "Drive a connected HarmonyOS device through natural-language UI automation. Runs the on-device GUI agent binary phone-use-harmonyos (built from github.com/axiomaster/phone-use-harmonyos), which screenshots the screen, sends it to the GLM vision model (autoglm-phone), and plans/executes UI actions (tap/type/swipe/launch app/back/home) until the task finishes. Use this when the user asks to operate apps on the HarmonyOS phone by describing what they want done — e.g. open WeChat and send a message, search Meituan for hotpot, make a DiDi ride booking, edit a video in CapCut."
whenToUse: "The user wants something done on the connected HarmonyOS phone via natural language — launching and driving apps, tapping/swiping/typing in any UI, reading and reacting to what is on screen — and a plain cli_tool query (see ohos-cli-tool skill) is not enough because the task needs multi-step UI interaction and visual understanding."
---

# Phone Use HarmonyOS — on-device GUI agent

A native GUI-agent CLI that runs **on the HarmonyOS device itself** (no PC-side control loop): it captures the screen, sends the image to the GLM vision model, gets a next-action plan, and executes taps / swipes / text input / app launches through `uitest` until the task completes.

## Prerequisites

1. **Device connected via HDC** (one serial in `hdc list targets`).
2. **Binary deployed** to the device: `/data/local/bin/phone-use-harmonyos` (aarch64-linux-ohos ELF; see `scripts/deploy.sh`).
3. **Config with a valid GLM API key** at `/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf`:
   ```
   GLM_API_KEY=<your-bigmodel-api-key>
   GLM_ENDPOINT=https://open.bigmodel.cn/api/paas/v4/chat/completions
   GLM_MODEL=autoglm-phone
   ```
   (or pass `--apikey` per call).
4. On-device system tools used by the agent: `/bin/snapshot_display`, `/bin/uitest`, `/bin/aa` (all present on this device).
5. Accessibility service: the agent works best with the OpenClaw accessibility service enabled; without it it logs a warning and continues in a limited mode via uitest.

## How to invoke

Via hdc (use this from the DSH bash tool):

```bash
HDC=/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc
"$HDC" shell "/data/local/bin/phone-use-harmonyos --task '你的任务描述' [--max-step N] [--verbose]"
```

Wrapper included in this skill bundle (keeps quoting correct):

```bash
cd skills/phone-use-harmonyos
./scripts/run.sh --task '打开微信' --max-step 20
```

## CLI reference

| Option | Meaning | Required |
|---|---|---|
| `--task <COMMAND>` | Task description in Chinese (natural language) | yes |
| `--apikey <KEY>` | GLM API key (optional if set in config file) | no |
| `--max-step <NUM>` | Max execution steps, default 20, max 200 | no |
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
| 5 | Timeout (exceeded max steps) |
| 10 | Network error |
| 11 | Initialization failed |

## What the agent can do (action set)

- `launch <app>` — start an app (via `aa start`); known bundles: 剪映 `com.lemon.hm.lv`, 图库 `com.huawei.hmos.photos`, 抖音 `com.ss.hm.ugc.aweme`, 微信 `com.tencent.wechat`, 美团 `com.sankuai.meituan`
- `tap [x,y]` — click at coordinates
- `type <text>` — input text
- `swipe [x1,y1] → [x2,y2]` — swipe
- `long press [x,y]`, `double tap [x,y]`
- `back`, `home`, `wait <duration>`
- `finish(message)` — task complete

## Worked examples

```bash
# Simple: open WeChat
"$HDC" shell "/data/local/bin/phone-use-harmonyos --task '打开微信'"

# Multi-step with more steps allowed
"$HDC" shell "/data/local/bin/phone-use-harmonyos --task '打开美团搜索附近的火锅店' --max-step 40"

# Verbose for debugging
"$HDC" shell "/data/local/bin/phone-use-harmonyos --task '打开设置' --verbose"

# Long creative pipeline
"$HDC" shell "/data/local/bin/phone-use-harmonyos --task '帮我在图库中查找春节期间拍摄的照片，使用剪映剪辑并配乐，剪成春节短片，并发布在抖音上' --max-step 60 --verbose"
```

## Tips

- **One task per call.** Describe a single clear objective in Chinese; avoid compound tasks unless `--max-step` is raised.
- **Default 20 steps**; raise with `--max-step` (≤200) for long flows. A step is screenshot→GLM→action.
- **Screenshots** are saved under `/data/local/tmp/screenshot_*.jpeg` on the device (0.5x to save bandwidth).
- **Failure diagnosis:** run with `--verbose`; watch for `[AutoGLMClient]` HTTP status (401 = bad/expired API key, network errors = 10).
- The GLM call needs internet access from the device.

## Pitfalls

- **API key validity** — a 401 `身份验证失败` means the key in the device config is invalid/expired; update `/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf` (or pass `--apikey`) before retrying.
- **Real device side effects** — this agent performs real taps/swipes/launches on the user's phone; confirm with the user before running potentially destructive flows (payments, logins, sending messages).
- **Accessibility warning** — if the log says `Accessibility service not enabled`, the agent continues with uitest but may be less robust; enabling the OpenClaw accessibility service in Settings improves reliability.
- **Long tasks** — a 20-step task can take a couple of minutes; use a generous bash timeout (e.g. 300000 ms) and consider running in the background.

## Rebuilding & redeploying (maintenance)

```bash
# Build (requires local OHOS NDK; override path with OHOS_NDK env)
cd /Users/ohci/code/phone-use-harmonyos
export OHOS_NDK=/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/native
export PATH="$OHOS_NDK/build-tools/cmake/bin:$OHOS_NDK/llvm/bin:$PATH"
cmake -B build -G Ninja -DCMAKE_MAKE_PROGRAM="$OHOS_NDK/build-tools/cmake/bin/ninja"
ninja -C build
# Output: build/bin/phone-use-harmonyos

# Deploy
./scripts/deploy.sh   # hdc file send → /data/local/bin/phone-use-harmonyos + chmod +x
```

## Bundle layout

- `SKILL.md` — this skill definition
- `scripts/run.sh` — wrapper for `hdc shell /data/local/bin/phone-use-harmonyos ...`
- `scripts/deploy.sh` — deploy freshly built binary to the device
- `config/phone-use-harmonyos.conf` — config template (GLM_API_KEY / ENDPOINT / MODEL)
