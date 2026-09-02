---
name: ohos-cli-tool
description: "Control this HarmonyOS device through its built-in system CLI suite (/system/bin/cli_tool, 23 executables): query battery/storage/time/usage stats, manage WiFi/Bluetooth/NFC/NearLink, control audio volume/devices/brightness/vibration, publish/cancel notifications, read/write pasteboard, start/stop apps, query location, subscribe geofence/movement events. Every call returns structured JSON. Use whenever the user wants to inspect or manipulate this phone (its state, radios, media, apps, sensors, notifications) via direct device commands — no hdc needed because the agent runs on the device itself."
whenToUse: "The user asks to query or change something on this HarmonyOS device — battery level, storage, WiFi scan/connect, Bluetooth state, volume/mute/audio devices, screen brightness, NFC/NearLink, notifications, pasteboard, app start/stop, installed bundles, location, usage statistics, system time, power modes, vibration — and any of the 23 cli_tool executables covers it. This agent runs on the device, so invoke the executables directly."
---

# OHOS cli_tool — device system CLI suite (on-device invocation)

This agent runs **on the HarmonyOS device itself**, so the system-service CLIs under `/system/bin/cli_tool/executable/` are invoked **directly** (no `hdc shell` wrapper needed). Each tool is a JSON-in/JSON-out wrapper over an OHOS system service; a matching schema descriptor lives at `/system/bin/cli_tool/configs/<name>.json`.

## Invocation

```bash
/system/bin/cli_tool/executable/<tool> <subcommand> [--flag value ...]

# list available tools
ls /system/bin/cli_tool/executable/

# show usage for any tool/subcommand
/system/bin/cli_tool/executable/<tool> --help
/system/bin/cli_tool/executable/<tool> <subcommand> --help
```

Consult `<tool> <subcommand> --help` or the matching config JSON before guessing parameters.

## Output format

Success: `{"type":"result","status":"success","data":{...}}`
Failure: `{"type":"result","status":"failed","errCode":"ERR_...","errMsg":"...","suggestion":"..."}`

- Ignore interleaved `[LOG] ...` / `[INFO] ...` / `{"level":"info",...}` stdout lines; the JSON payload is the result.
- Missing params return `status:failed` + `ERR_ARG_MISSING`/`ERR_PARAM_INVALID` and a `suggestion` naming the flag to add.
- `data` may contain JSON-looking strings (e.g. `ohos-nfcManager get-state`); parse accordingly.

## Tool catalog (23 tools)

### System state & queries
| Tool | Subcommands | Notes |
|---|---|---|
| `ohos-queryTime` | `get-wall-time`, `get-boot-time`, `get-monotonic-time`, `get-time-zone` | ms since epoch/boot; timezone like `Asia/Shanghai` |
| `ohos-batteryManager` | `capacity`, `total-energy`, `remain-energy` | capacity %, energies mAh |
| `ohos-storageManager` | `get-total-size`, `get-free-size`, `get-system-size`, `get-user-storage-stats`, `get-bundle-stats`, `get-current-bundle-stats` | `--packageName <bundle>` for per-app |
| `ohos-usageStatsQuery` | `check-bundle-idle`, `check-bundle-period`, `query-stats-interval`, `query-events`, `query-app-group`, `query-high-freq-bundle`, `query-module-records`, `query-notification-stats`, `query-high-freq-period`, `query-latest-used-time` | `--bundle <name>` per-app; time ms |
| `ohos-displayManager` | `set-brightness` | `--value` 0–255, `--continuous` |
| `ohos-powerManager` | `suspend`, `wakeup`, `set-power-mode`, `override-screen-off-time`, `restore-screen-off-time` | `--mode normal|powerSave` |
| `ohos-a11yManager` | 25 accessibility subcommands | set/get pairs take `--state true|false` |

### Radios & connectivity
| Tool | Subcommands | Notes |
|---|---|---|
| `ohos-wifiManager` | `sta-enable`, `sta-disable`, `scan-start`, `scan-list`, `sta-connect`, `sta-getLinkedInfo` | `sta-connect --ssid <s> [--preSharedKey <k>]` |
| `ohos-bluetoothTool` | `enable-bt`, `disable-bt`, `get-state`, `get-paired-devices`, `get-device-name`, `connect-profiles`, `disconnect-profiles` | MAC `XX:XX:XX:XX:XX:XX`; `--transport bredr|ble` |
| `ohos-nfcManager` | `get-state`, `turn-on`, `turn-off`, `is-available` | |
| `ohos-nearlinkControl` | `enable`, `disable` | `--autoConnPolicy 0|1|2` |
| `ohos-networkShare` | `is-supported`, `is-sharing`, `start`, `stop` | `--type wifi|usb|bluetooth` |
| `ohos-location` | `is-enabled`, `enable`, `disable`, `get-last-approximate-location`, `get-last-precise-location`, `get-current-approximate-location`, `get-current-precise-location` | current: `--priority accuracy|speed --timeout <ms>` |
| `hms-geofence` | `subscribe`, `unsubscribe` | async — wrap in `timeout` |
| `hms-movementAwareness` | `subscribe`, `unsubscribe` | async — wrap in `timeout` |

### Media & UX
| Tool | Subcommands | Notes |
|---|---|---|
| `ohos-audioManager` | `get-volume`, `set-volume`, `get-max-volume`, `is-mute`, `set-mute`, `get-devices`, `select-output-device`, `help` | volume types `STREAM_MUSIC` etc. |
| `ohos-avsession-manager` | `list-sessions`, `get-playback-state`, `get-metadata`, `get-valid-commands`, `send-control-command-to-session` | needs `--session-id` |
| `ohos-vibratorControl` | `startVibrator`, `isSupportEffect` | `--effectId haptic.clock.timer` etc. |
| `ohos-pasteboard` | `set-data`, `get-data`, `clear-data`, `has-data`, `has-data-type`, `has-remote-data` | `set-data --text|--html|--uri <v>` |
| `ohos-notificationManager` | `publish`, `cancelById`, `cancelByBundle`, `batchCancel`, `enableNotification`, `setSlotFlags`, `listAllNotification` | `publish --notificationContent '<json>'` |

### Apps & bundles
| Tool | Subcommands | Notes |
|---|---|---|
| `ohos-aa` | `start`, `force-stop` | `start --abilityname <A> --bundlename <b> [--uri ...] [--pi/--pb/--ps '<json>']` |
| `ohos-bm` | `uninstall`, `dump`, `dump-dependencies`, `dump-shared`, `clean`, `set-disposed-rule`, `delete-disposed-rule`, `get-recoverable-apps`, `recover`, `create-cli-sandbox-app`, `destroy-cli-sandbox-app` | `dump --bundleName <n>` prints app JSON |
| `ohos-arkTSScript` | (no subcommands) | `--abcPath <abc> --functionName <fn> [--args '<json>']` |

## Worked examples

```bash
# Battery + storage + time
/system/bin/cli_tool/executable/ohos-batteryManager capacity
/system/bin/cli_tool/executable/ohos-storageManager get-free-size
/system/bin/cli_tool/executable/ohos-queryTime get-time-zone

# WiFi scan + connect
/system/bin/cli_tool/executable/ohos-wifiManager sta-enable
/system/bin/cli_tool/executable/ohos-wifiManager scan-start && sleep 3
/system/bin/cli_tool/executable/ohos-wifiManager scan-list
/system/bin/cli_tool/executable/ohos-wifiManager sta-connect --ssid MyNet --preSharedKey mypass
/system/bin/cli_tool/executable/ohos-wifiManager sta-getLinkedInfo

# Media
/system/bin/cli_tool/executable/ohos-audioManager get-volume --type STREAM_MUSIC
/system/bin/cli_tool/executable/ohos-audioManager set-volume --volume 12 --type STREAM_MUSIC
/system/bin/cli_tool/executable/ohos-vibratorControl startVibrator --effectId haptic.clock.timer

# Notification + pasteboard
/system/bin/cli_tool/executable/ohos-notificationManager publish --notificationContent '{"type":"basic","title":"Test","text":"Hello"}'
/system/bin/cli_tool/executable/ohos-pasteboard set-data --text "hello"
/system/bin/cli_tool/executable/ohos-pasteboard get-data

# Apps
/system/bin/cli_tool/executable/ohos-bm dump --bundleName com.huawei.hmos.camera
/system/bin/cli_tool/executable/ohos-aa start --abilityname EntryAbility --bundlename com.example.app

# Location
/system/bin/cli_tool/executable/ohos-location get-current-approximate-location --timeout 5000
```

## Pitfalls

- **Async subscriptions** (`hms-geofence subscribe`, `hms-movementAwareness subscribe`) keep running/streaming — always wrap with `timeout 10 <cmd> ...`.
- **Permissions:** tools declare `requirePermissions` in their configs; failures like `BussinessError 201` / `ERR_*_PERMISSION_DENIED` mean the service refused — report rather than retry blindly.
- **Harmful side effects:** `ohos-bm uninstall`, `ohos-aa force-stop`, `ohos-powerManager suspend`, `ohos-bluetoothTool disable-bt`, `ohos-wifiManager sta-disable`, `ohos-location disable`, `ohos-notificationManager batchCancel` change device state — confirm with the user before destructive calls.
- Reference schemas live in `/system/bin/cli_tool/configs/<name>.json` on this device — read one when in doubt.
