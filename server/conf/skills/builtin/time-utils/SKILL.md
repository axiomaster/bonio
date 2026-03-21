---
name: time-utils
description: Use when the user asks for the current date, time, or timezone information. Provides shell commands to query system time.
---

# Time Utilities

Get the current date and time using shell commands.

## How to Use

Run one of the following commands using the `shell` tool:

### Get current date and time (ISO 8601)

```bash
date -Iseconds
```

### Get current date only

```bash
date +%Y-%m-%d
```

### Get current UTC time

```bash
date -u -Iseconds
```

### Get timezone

```bash
date +%Z
```

## Notes

- On Android / Linux, `date` supports `-I` for ISO format.
- Combine with other tools as needed (e.g., store the result in memory).
