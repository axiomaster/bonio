# phone-use-harmonyos — on-device HarmonyOS GUI agent skill

DSH skill wrapping the on-device GUI agent CLI built from
[github.com/axiomaster/phone-use-harmonyos](https://github.com/axiomaster/phone-use-harmonyos).

## What it does

Runs a native GUI-agent loop **on the HarmonyOS device**: screenshot → GLM vision model
(autoglm-phone) → planned UI action (tap/type/swipe/launch/back/home) → execute via uitest → repeat
until the natural-language task is done. No PC-side control loop.

## Status (this machine)

- Built: `aarch64-linux-ohos` ELF from the local OHOS NDK (`/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/native`).
- Deployed: `/data/local/bin/phone-use-harmonyos` on device `5MQ0125716000138`; `--help` verified.
- Device config written to `/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf` with a **valid** GLM key.
- E2E verified: real UI task executed on device (screenshot → GLM 200 OK → tap/swipe actions); success path returns exit 0, step-limit exit 5.

## Files

| Path | Purpose |
|---|---|
| `SKILL.md` | Skill definition (DSH-callable) |
| `scripts/run.sh` | `./scripts/run.sh --task '...'` → hdc shell on-device CLI |
| `scripts/deploy.sh` | Redeploy built binary to device |
| `config/phone-use-harmonyos.conf` | Config template (GLM key/endpoint/model) |

## Build & deploy (quick)

```bash
cd /Users/ohci/code/phone-use-harmonyos
export OHOS_NDK=/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/native
export PATH="$OHOS_NDK/build-tools/cmake/bin:$OHOS_NDK/llvm/bin:$PATH"
cmake -B build -G Ninja -DCMAKE_MAKE_PROGRAM="$OHOS_NDK/build-tools/cmake/bin/ninja"
ninja -C build
cd -
./skills/phone-use-harmonyos/scripts/deploy.sh
```