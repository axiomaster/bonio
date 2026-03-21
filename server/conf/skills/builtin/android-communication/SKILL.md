---
name: android-communication
description: Use when the user wants to read/search SMS, check call history, make phone calls, send messages, launch apps, open URLs, or manage running apps on Android.
---

# Android Communication

SMS, call logs, phone calls, app launching, and intent actions via shell commands.

---

## SMS Messages

### Read recent inbox

```bash
content query --uri content://sms/inbox --projection address:body:date --sort "date DESC" --limit 10
```

### Sent messages

```bash
content query --uri content://sms/sent --projection address:body:date --sort "date DESC" --limit 10
```

### All messages (type: 1=received, 2=sent)

```bash
content query --uri content://sms --projection address:body:date:type --sort "date DESC" --limit 20
```

### Search by phone number

```bash
content query --uri content://sms --projection address:body:date:type --where "address LIKE '%138001%'" --sort "date DESC" --limit 10
```

### Search for verification codes

```bash
content query --uri content://sms/inbox --projection address:body:date --where "body LIKE '%验证码%'" --sort "date DESC" --limit 5
```

### Unread messages

```bash
content query --uri content://sms/inbox --projection address:body:date --where "read=0" --sort "date DESC"
```

### Message count

```bash
content query --uri content://sms/inbox --projection "count(*) AS count"
```

### Open SMS compose screen

```bash
am start -a android.intent.action.SENDTO -d "sms:13800138000" --es sms_body "message text"
```

---

## Call Log

### Recent calls (type: 1=incoming, 2=outgoing, 3=missed, 5=rejected)

```bash
content query --uri content://call_log/calls --projection number:type:date:duration --sort "date DESC" --limit 20
```

### Missed calls

```bash
content query --uri content://call_log/calls --projection number:date:duration --where "type=3" --sort "date DESC" --limit 10
```

### Incoming / Outgoing calls

```bash
content query --uri content://call_log/calls --projection number:date:duration --where "type=1" --sort "date DESC" --limit 10
content query --uri content://call_log/calls --projection number:date:duration --where "type=2" --sort "date DESC" --limit 10
```

### Search by number

```bash
content query --uri content://call_log/calls --projection number:type:date:duration --where "number LIKE '%138001%'" --sort "date DESC" --limit 10
```

### With contact name

```bash
content query --uri content://call_log/calls --projection name:number:type:date:duration --sort "date DESC" --limit 15
```

### Count new missed calls

```bash
content query --uri content://call_log/calls --projection "count(*) AS count" --where "type=3 AND new=1"
```

---

## Making Phone Calls

### Open dialer with number

```bash
am start -a android.intent.action.DIAL -d "tel:13800138000"
```

### Direct call

```bash
am start -a android.intent.action.CALL -d "tel:13800138000"
```

## Sending Email

```bash
am start -a android.intent.action.SENDTO -d "mailto:user@example.com" --es android.intent.extra.SUBJECT "Subject" --es android.intent.extra.TEXT "Body"
```

## Sharing Text

```bash
am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "Hello world"
```

---

## Launching Apps

### By package/activity

```bash
am start -n com.android.settings/.Settings
```

### Common apps

| App | Command |
|-----|---------|
| Settings | `am start -n com.android.settings/.Settings` |
| Chrome | `am start -n com.android.chrome/com.google.android.apps.chrome.Main` |
| Camera | `am start -a android.media.action.STILL_IMAGE_CAMERA` |
| Clock | `am start -n com.android.deskclock/.DeskClock` |

### Find launch activity for any app

```bash
cmd package resolve-activity --brief -c android.intent.category.LAUNCHER com.tencent.mm
```

### Open URL

```bash
am start -a android.intent.action.VIEW -d "https://www.example.com"
```

## Managing Running Apps

### Force stop

```bash
am force-stop com.example.app
```

### Kill background processes

```bash
am kill-all
```

### Current foreground app

```bash
dumpsys activity top | grep ACTIVITY | tail -1
```

### Recent tasks

```bash
dumpsys activity recents | grep "Recent #" | head -10
```

## Key Events

| Key | Command |
|-----|---------|
| Home | `input keyevent KEYCODE_HOME` |
| Back | `input keyevent KEYCODE_BACK` |
| Recents | `input keyevent KEYCODE_APP_SWITCH` |
| Power | `input keyevent KEYCODE_POWER` |
| Enter | `input keyevent KEYCODE_ENTER` |

---

## Notes

- `date` columns are Unix timestamps in milliseconds.
- `duration` in call log is in seconds; 0 means not answered.
- `am start -a ACTION` uses intents; `am start -n PACKAGE/ACTIVITY` launches specific activities.
- SMS sending via `am start` opens the compose UI; user must tap send.
- Use `--limit` to keep output manageable.
