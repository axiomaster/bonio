# ohos-cli-tool — HarmonyOS device system CLI suite skill

A DSH skill that turns the connected HarmonyOS/OpenHarmony phone's built-in system CLI suite
(`/system/bin/cli_tool/executable/`, 23 executables) into a callable capability for the DSH backend.

## What it does

The device ships JSON-in/JSON-out system-service CLIs under `/system/bin/cli_tool/executable/`,
each documented by a schema file in `/system/bin/cli_tool/configs/`. This skill teaches the agent
how to invoke them over `hdc` (which device is connected, how to call each tool, what JSON comes
back, and which subcommands exist), so the agent can query and control the phone on demand:

- System state: battery, storage, time/timezone, usage statistics, display brightness, power modes, accessibility
- Connectivity: WiFi (scan/connect), Bluetooth, NFC, NearLink, network sharing, location, geofence, movement awareness
- Media & UX: audio volume/devices/mute, AVSession playback control, vibrator, pasteboard, notifications
- Apps: start/stop abilities (`ohos-aa`), bundle management (`ohos-bm`), ArkTS script execution

## Files

| Path | Purpose |
|---|---|
| `SKILL.md` | Skill definition (frontmatter + full usage instructions) — the DSH-callable entry point |
| `scripts/ohos-cli.sh` | Wrapper: `./scripts/ohos-cli.sh <tool> <subcommand> [args]` (or `list` / `--help`) |
| `configs/` | The exact device JSON descriptors pulled from `/system/bin/cli_tool/configs/` — authoritative schemas |
| `REFERENCE.md` | Generated human-readable parameter cheat sheet for all 23 tools |
| `scripts/pull_configs.sh` | Re-pull fresh configs from the connected device (maintenance) |
| `scripts/gen_reference.js` | Regenerates `REFERENCE.md` from `configs/` (maintenance) |

## Registering the skill with DSH

DSH discovers skills from project/user skill roots. The canonical bundle lives in this repo's
`skills/` directory; register it into the project DSH root so the backend can load it:

```bash
mkdir -p .dsh/skills
ln -s ../../skills/ohos-cli-tool .dsh/skills/ohos-cli-tool
```

After registration the skill shows up as `ohos-cli-tool` in the session skill catalog and the agent
loads it via the `skill` tool, then executes the underlying CLIs through `hdc shell`.

## Prerequisites

- hdc on the host (default: `/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc`;
  override with env `HDC`)
- A HarmonyOS device connected (`hdc list targets` shows a serial)
- `hdc shell` runs as root on this device (su context), which the system-service tools require

## Quick check

```bash
./scripts/ohos-cli.sh list
./scripts/ohos-cli.sh ohos-batteryManager capacity
./scripts/ohos-cli.sh ohos-queryTime get-time-zone
```

## Maintenance

- Device firmware updated the tools? Re-pull the descriptors: `./scripts/pull_configs.sh`, then regenerate
  the cheat sheet: `node scripts/gen_reference.js configs`.
- hdc moved? Point `HDC` at it (or edit the default in `scripts/ohos-cli.sh` and `SKILL.md`).
