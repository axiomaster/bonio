---
name: android-file-manager
description: Use when the user wants to find files, check storage space, list directories, or manage files on the Android device. Covers search, disk usage, downloads, and file operations.
---

# Android File Manager

File system operations via shell commands on Android.

## Common Paths

| Path | Description |
|------|-------------|
| `/sdcard/` or `/storage/emulated/0/` | Internal storage root |
| `/sdcard/Download/` | Downloads |
| `/sdcard/DCIM/` | Camera photos/videos |
| `/sdcard/Pictures/` | Screenshots and saved images |
| `/sdcard/Documents/` | Documents |
| `/sdcard/Music/` | Music files |
| `/sdcard/Movies/` | Video files |

## Searching Files

### By name

```bash
find /sdcard -maxdepth 4 -name "*.pdf" 2>/dev/null | head -20
```

### By name (case-insensitive)

```bash
find /sdcard -maxdepth 4 -iname "*report*" 2>/dev/null | head -20
```

### Recently modified (last 7 days)

```bash
find /sdcard -maxdepth 3 -type f -mtime -7 2>/dev/null | head -30
```

### Large files (>100MB)

```bash
find /sdcard -maxdepth 4 -type f -size +100M 2>/dev/null -exec ls -lh {} \;
```

## Listing Directories

### Downloads

```bash
ls -lhS /sdcard/Download/ | head -30
```

### Camera photos (latest)

```bash
ls -lht /sdcard/DCIM/Camera/ 2>/dev/null | head -20
```

## Storage Space

### Overall disk usage

```bash
df -h /sdcard
```

### Directory sizes

```bash
du -sh /sdcard/*/ 2>/dev/null | sort -rh | head -15
```

### Specific directory size

```bash
du -sh /sdcard/Download/
```

## File Details

```bash
stat /sdcard/Download/example.pdf
```

```bash
ls -lh /sdcard/Download/example.pdf
```

## File Operations

### Copy

```bash
cp /sdcard/Download/file.pdf /sdcard/Documents/
```

### Move / Rename

```bash
mv /sdcard/Download/old_name.pdf /sdcard/Documents/new_name.pdf
```

### Delete

```bash
rm /sdcard/Download/unwanted_file.pdf
```

### Create directory

```bash
mkdir -p /sdcard/Documents/MyFolder
```

## MediaStore Query (indexed media)

### Recent images

```bash
content query --uri content://media/external/images/media --projection _display_name:_size:date_modified --sort "date_modified DESC" --limit 10
```

### Recent videos

```bash
content query --uri content://media/external/video/media --projection _display_name:_size:duration:date_modified --sort "date_modified DESC" --limit 10
```

## Notes

- Always use `2>/dev/null` with `find` to suppress permission errors.
- Use `head` or `--limit` to keep output manageable.
- Use `-maxdepth` with `find` to avoid scanning too deeply.
- Confirm with the user before deleting files.
