---
name: android-system-control
description: Use when the user wants to manage system settings (brightness, timeout, battery, device info), control media (volume, playback, screenshots), manage network/Bluetooth connectivity, or manage installed apps (list, permissions, clear data) on Android.
---

# Android System Control

Comprehensive system control via shell commands. Covers settings, media, connectivity, and app management.

---

## Screen & Display

### Brightness (0-255)

```bash
settings get system screen_brightness
settings put system screen_brightness 200
```

### Auto-brightness (0=manual, 1=auto)

```bash
settings get system screen_brightness_mode
settings put system screen_brightness_mode 0
```

### Screen timeout (milliseconds)

```bash
settings get system screen_off_timeout
settings put system screen_off_timeout 60000
```

Common values: 15000 (15s), 30000 (30s), 60000 (1min), 120000 (2min), 300000 (5min).

---

## Battery & Device Info

```bash
dumpsys battery
```

Key fields: `level` (%), `status` (2=charging, 3=discharging, 5=full), `temperature` (tenths of °C).

### CPU / Memory

```bash
dumpsys cpuinfo | head -20
dumpsys meminfo | head -15
dumpsys meminfo com.tencent.mm | head -10
```

### Device info

```bash
echo "$(getprop ro.product.brand) $(getprop ro.product.model), Android $(getprop ro.build.version.release), SDK $(getprop ro.build.version.sdk)"
uptime
```

### Do Not Disturb (0=off, 1=priority, 2=silence, 3=alarms)

```bash
settings get global zen_mode
```

---

## Volume Control

Stream IDs: 0=voice call, 1=system, 2=ring, 3=music, 4=alarm, 5=notification.

```bash
media volume --show --stream 3 --set 10
media volume --show --stream 2 --set 5
media volume --show --stream 4 --set 7
```

### Current volumes

```bash
dumpsys audio | grep -A 1 "STREAM_MUSIC" | head -3
```

## Music Playback

```bash
cmd media_session dispatch pause
cmd media_session dispatch play
cmd media_session dispatch next
cmd media_session dispatch previous
```

### Active sessions

```bash
dumpsys media_session | grep "Session " | head -5
```

## Screenshot & Screen Recording

```bash
screencap -p /sdcard/Pictures/screenshot_$(date +%Y%m%d_%H%M%S).png
screenrecord --time-limit 10 /sdcard/Movies/recording_$(date +%Y%m%d_%H%M%S).mp4
```

---

## WiFi

```bash
dumpsys wifi | grep -E "SSID|mIpAddress|linkSpeed|rssi" | head -6
cmd wifi set-wifi-enabled enabled
cmd wifi set-wifi-enabled disabled
cmd wifi list-networks
ip addr show wlan0 | grep "inet "
```

## Bluetooth

```bash
settings get global bluetooth_on
svc bluetooth enable
svc bluetooth disable
dumpsys bluetooth_manager | grep -A 2 "name:" | head -20
```

## Network Test

```bash
ping -c 3 -W 2 8.8.8.8
settings get global mobile_data
settings get global airplane_mode_on
dumpsys connectivity | grep "Active default network" | head -1
```

---

## App Management (pm)

### List installed apps

```bash
pm list packages -3          # third-party
pm list packages -s          # system
pm list packages | grep -i wechat
```

### App details

```bash
dumpsys package com.tencent.mm | grep -E "versionName|versionCode|firstInstallTime|lastUpdateTime"
pm path com.tencent.mm
```

### Clear app data (**destructive — confirm first**)

```bash
pm clear com.example.app
```

### Permissions

```bash
pm grant com.example.app android.permission.CAMERA
pm revoke com.example.app android.permission.CAMERA
dumpsys package com.tencent.mm | grep -A 50 "granted=true" | head -30
```

### Disable/Enable apps

```bash
pm disable-user --user 0 com.example.bloatware
pm enable com.example.bloatware
pm list packages -d    # list disabled
```

---

## Notes

- `settings put` changes take effect immediately.
- Volume range varies by device (typically 0-15 for media).
- `pm clear` removes ALL app data. Always confirm with the user.
- Some commands may vary by Android version and manufacturer.
