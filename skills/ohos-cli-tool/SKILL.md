---
name: ohos-cli-tool
description: "Control a connected HarmonyOS/OpenHarmony device through its built-in system CLI suite (/system/bin/cli_tool, 23 executables): query battery/storage/time/usage stats, manage WiFi/Bluetooth/NFC/NearLink, control audio volume/devices/brightness/vibration, publish/cancel notifications, read/write pasteboard, start/stop apps, query location, subscribe geofence/movement events. Invoked over hdc; every call returns structured JSON. Use this whenever the user wants to inspect or manipulate the connected HarmonyOS phone (its state, radios, media, apps, sensors, notifications)."
whenToUse: "The user asks to query or change something on the connected HarmonyOS device — battery level, storage, WiFi scan/connect, Bluetooth state, volume/mute/audio devices, screen brightness, NFC/NearLink, notifications, pasteboard, app start/stop, installed bundles, location, usage statistics, system time, power modes, vibration — and any of the 23 cli_tool executables covers it."
---

# OHOS cli_tool — HarmonyOS Device System CLI Suite

The connected HarmonyOS device ships a suite of system-service CLI executables under `/system/bin/cli_tool/executable/`. Each tool is a thin JSON-in/JSON-out wrapper over an OHOS system service. Every tool has a matching JSON schema descriptor under `/system/bin/cli_tool/configs/<name>.json` that fully documents its subcommands, parameters, permissions and output shape.

## Prerequisites

1. **HDC available and a device connected.**
   ```bash
   HDC=/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc
   "$HDC" list targets   # must print a device serial, e.g. 5MQ0125716000138
   ```
2. **Shell access.** `hdc shell` runs as root (uid=0) on this device, which is enough for every tool below. Some tools additionally require system-granted permissions (declared in their configs); if a call fails with a permission error, report the `errCode`/`errMsg` and the tool's `requirePermissions` from its config.

## How to invoke

Preferred — the bundled wrapper (keeps quoting correct and hdc path central):

```bash
cd skills/ohos-cli-tool
./scripts/ohos-cli.sh <tool> <subcommand> [--flag value ...]
./scripts/ohos-cli.sh list                        # list available tools
./scripts/ohos-cli.sh <tool> --help               # show a tool's usage
```

Direct equivalent (works from anywhere):

```bash
HDC=/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc
"$HDC" shell /system/bin/cli_tool/executable/<tool> <subcommand> [--flag value ...]
"$HDC" shell /system/bin/cli_tool/executable/<tool> <subcommand> --help
```

Every tool supports `<tool> --help` and `<tool> <subcommand> --help`, which print exact usage, flags, defaults and examples — **consult the help or the config JSON before guessing parameters**.

## Output format

Success:
```json
{"type":"result","status":"success","data":{ ...tool-specific fields... }}
```
Failure:
```json
{"type":"result","status":"failed","errCode":"ERR_...","errMsg":"...","suggestion":"..."}
```

Notes:
- Some tools interleave `[LOG] ...` / `[INFO] ...` / `{"level":"info",...}` lines on stdout before the final JSON — ignore them; the JSON payload is the result.
- Missing required parameters return `status:failed` with `ERR_ARG_MISSING`/`ERR_PARAM_INVALID` and a `suggestion` that names the exact flag to add.
- `data` may itself contain strings that look like JSON (e.g. `ohos-nfcManager get-state` returns `data.state` as a JSON string) — parse accordingly.

## Tool catalog (23 tools)

### System state & queries
| Tool | Subcommands | Notes |
|---|---|---|
| `ohos-queryTime` | `get-wall-time`, `get-boot-time`, `get-monotonic-time`, `get-time-zone` | all ms since epoch/boot; timezone like `Asia/Shanghai` |
| `ohos-batteryManager` | `capacity`, `total-energy`, `remain-energy` | capacity %, energies in mAh |
| `ohos-storageManager` | `get-total-size`, `get-free-size`, `get-system-size`, `get-user-storage-stats`, `get-bundle-stats`, `get-current-bundle-stats` | `get-bundle-stats --packageName <bundle>`; sizes in bytes + human-readable |
| `ohos-usageStatsQuery` | `check-bundle-idle`, `check-bundle-period`, `query-stats-interval`, `query-events`, `query-app-group`, `query-high-freq-bundle`, `query-module-records`, `query-notification-stats`, `query-high-freq-period`, `query-latest-used-time` | needs `--bundle <name>` for per-app; time args in ms; may fail if BundleActiveService/perm missing |
| `ohos-displayManager` | `set-brightness` | `--value` 0–255, `--continuous` bool |
| `ohos-powerManager` | `suspend`, `wakeup`, `set-power-mode`, `override-screen-off-time`, `restore-screen-off-time` | `set-power-mode --mode normal|powerSave`; screen-off time in ms |
| `ohos-a11yManager` | 25 accessibility subcommands (screen reader, magnification, high contrast, color inversion, mono audio, balance, daltonization, click timing...) | set/get pairs take `--state true|false`; permissions are `ohos.permission.cli.*` |

### Radios & connectivity
| Tool | Subcommands | Notes |
|---|---|---|
| `ohos-wifiManager` | `sta-enable`, `sta-disable`, `scan-start`, `scan-list`, `sta-connect`, `sta-getLinkedInfo` | `sta-connect --ssid <ssid> [--preSharedKey <psk>]`; scan results: ssid/bssid/securityType/rssi/frequency |
| `ohos-bluetoothTool` | `enable-bt`, `disable-bt`, `get-state`, `get-paired-devices`, `get-device-name`, `connect-profiles`, `disconnect-profiles` | MAC addr format `XX:XX:XX:XX:XX:XX`; `--transport bredr|ble` |
| `ohos-nfcManager` | `get-state`, `turn-on`, `turn-off`, `is-available` | state string may be nested JSON |
| `ohos-nearlinkControl` | `enable`, `disable` | `--autoConnPolicy 0|1|2`; fails on devices without NearLink permission |
| `ohos-networkShare` | `is-supported`, `is-sharing`, `start`, `stop` | `start/stop --type wifi|usb|bluetooth`; some devices return ERR_NET_INTERNAL_ERROR (unsupported) |
| `ohos-location` | `is-enabled`, `enable`, `disable`, `get-last-approximate-location`, `get-last-precise-location`, `get-current-approximate-location`, `get-current-precise-location` | current-location: `--priority accuracy|speed --timeout <ms>`; precise needs GPS + permissions |
| `hms-geofence` | `subscribe`, `unsubscribe` | subscribe needs sessionId/ruleId/bundleName/type/lat/lng/status/code/interfaceToken/abilityName; async (may keep running) — use a timeout |
| `hms-movementAwareness` | `subscribe`, `unsubscribe` | subscribe needs type/sessionId/ruleId/bundleName/abilityName/code/interfaceToken; async — use a timeout |

### Media & UX
| Tool | Subcommands | Notes |
|---|---|---|
| `ohos-audioManager` | `get-volume`, `set-volume`, `get-max-volume`, `is-mute`, `set-mute`, `get-devices`, `select-output-device`, `help` | volume type enums: `STREAM_MUSIC` etc.; `set-volume --volume <n> [--type <t>]`; `set-mute --mute true|false` |
| `ohos-avsession-manager` | `list-sessions`, `get-playback-state`, `get-metadata`, `get-valid-commands`, `send-control-command-to-session` | control command enums: play/pause/stop/seek/set_loop_mode...; needs `--session-id` |
| `ohos-vibratorControl` | `startVibrator`, `isSupportEffect` | `--effectId haptic.clock.timer` etc. |
| `ohos-pasteboard` | `set-data`, `get-data`, `clear-data`, `has-data`, `has-data-type`, `has-remote-data` | `set-data --text|--html|--uri <value>`; `has-data-type --type text/plain|text/html|text/uri` |
| `ohos-notificationManager` | `publish`, `cancelById`, `cancelByBundle`, `batchCancel`, `enableNotification`, `setSlotFlags`, `listAllNotification` | `publish --notificationContent '<json>'` (type basic/long_text/multiline, see help); `--bundleOption '{"bundleName":"...","uid":...}'` |

### Apps & bundles
| Tool | Subcommands | Notes |
|---|---|---|
| `ohos-aa` | `start`, `force-stop` | `start --abilityname <Ability> --bundlename <bundle> [--modulename ...] [--uri ...] [--action ...] [--pi/--pb/--ps '<json>']`; `force-stop --bundlename <bundle>` |
| `ohos-bm` | `uninstall`, `dump`, `dump-dependencies`, `dump-shared`, `clean`, `set-disposed-rule`, `delete-disposed-rule`, `get-recoverable-apps`, `recover`, `create-cli-sandbox-app`, `destroy-cli-sandbox-app` | `dump --bundleName <name>` prints app JSON; `uninstall --bundleName <name>`; `clean --bundleName <name> [--cache|--data]` |
| `ohos-arkTSScript` | (no subcommands) | `--abcPath <abc> --functionName <fn> [--scriptPath ...] [--args '<json>']` — run a function from an ArkTS ABC file |

## Worked examples

```bash
# Battery + storage + time in one sweep
./scripts/ohos-cli.sh ohos-batteryManager capacity
./scripts/ohos-cli.sh ohos-storageManager get-free-size
./scripts/ohos-cli.sh ohos-queryTime get-time-zone

# WiFi: enable, scan, list, connect
./scripts/ohos-cli.sh ohos-wifiManager sta-enable
./scripts/ohos-cli.sh ohos-wifiManager scan-start && sleep 3
./scripts/ohos-cli.sh ohos-wifiManager scan-list
./scripts/ohos-cli.sh ohos-wifiManager sta-connect --ssid MyNet --preSharedKey mypass
./scripts/ohos-cli.sh ohos-wifiManager sta-getLinkedInfo

# Media: volume, mute, output device, vibration
./scripts/ohos-cli.sh ohos-audioManager get-volume --type STREAM_MUSIC
./scripts/ohos-cli.sh ohos-audioManager set-volume --volume 12 --type STREAM_MUSIC
./scripts/ohos-cli.sh ohos-audioManager set-mute --mute false
./scripts/ohos-cli.sh ohos-vibratorControl startVibrator --effectId haptic.clock.timer

# Notifications: publish, list, cancel
./scripts/ohos-cli.sh ohos-notificationManager publish --notificationContent '{"type":"basic","title":"Test","text":"Hello from DSH"}'
./scripts/ohos-cli.sh ohos-notificationManager listAllNotification

# Pasteboard
./scripts/ohos-cli.sh ohos-pasteboard set-data --text "hello"
./scripts/ohos-cli.sh ohos-pasteboard get-data

# Apps
./scripts/ohos-cli.sh ohos-bm dump --bundleName com.huawei.hmos.camera
./scripts/ohos-cli.sh ohos-aa start --abilityname EntryAbility --bundlename com.example.app
./scripts/ohos-cli.sh ohos-aa force-stop --bundlename com.example.app

# Location (approximate, sync)
./scripts/ohos-cli.sh ohos-location get-current-approximate-location --timeout 5000

# Usage stats (24h window)
./scripts/ohos-cli.sh ohos-usageStatsQuery query-stats-interval --interval 0 --begin <ms> --end <ms>
```

## Reference resources in this skill bundle

- `configs/` — the exact device JSON descriptors (`<tool>.json`): authoritative for subcommands, required/optional params (with enums/defaults/descriptions), permissions, and output schemas. **When in doubt, read the matching config or run `<tool> <subcommand> --help` on the device.**
- `REFERENCE.md` — generated human-readable parameter cheat sheet for all 23 tools.
- `scripts/ohos-cli.sh` — the invocation wrapper described above.

## Pitfalls

- **Async subscriptions** (`hms-geofence subscribe`, `hms-movementAwareness subscribe`) keep the process alive and stream events — always run them with a remote `timeout` (e.g. `hdc shell "timeout 10 <tool> subscribe ..."`) and capture the event lines as output.
- **Permissions:** tools declare `requirePermissions` in their configs; a call that fails with `BussinessError 201` / `ERR_*_PERMISSION_DENIED` means the service refused — report it rather than retrying blindly.
- **Quoting:** values with spaces/special characters must survive two shell layers (local bash → hdc → device shell). The wrapper uses `printf %q`; if invoking hdc directly, wrap the whole remote command in double quotes inside the `hdc shell "..."` argument.
- **Harmful side effects:** `ohos-bm uninstall`, `ohos-aa force-stop`, `ohos-powerManager suspend`, `ohos-bluetoothTool disable-bt`, `ohos-wifiManager sta-disable`, `ohos-location disable`, `ohos-notificationManager batchCancel` change device state — confirm with the user before destructive calls, and prefer read-only subcommands for diagnostics.
- **No config write-back:** these tools only affect the live device, they do not edit `hiclaw.json` or any project config.
