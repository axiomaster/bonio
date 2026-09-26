#!/usr/bin/env python3
"""make-skin-pack.py — Package a Bonio avatar skin (Android) into an importable zip.

Implements the skin package format v1 defined in
docs/design/prd/skin-import-prd-20260926.md:

    <id>.zip
    ├── manifest.json      # required
    ├── spritesheet.webp   # required (webp/png, exact grid size)
    └── preview.png        # optional, gallery preview

Usage:
    python3 tools/make-skin-pack.py \
        --id kun-demo --name "Kun Demo (小黄鸡试装)" --subtitle "示例皮肤包" \
        --sheet android/app/src/main/assets/avatars/kun-spritesheet.webp \
        --out dist/skins/kun-demo.skin.zip

Optional flags: --author --victory-quote --preview --cols --rows --frame-w --frame-h
The sprite sheet dimensions are verified against the grid when the image header
can be parsed (PNG and WebP are supported; unknown formats are skipped with a note).
"""

import argparse
import json
import re
import shutil
import struct
import sys
import zipfile
from pathlib import Path

ID_REGEX = re.compile(r"^[a-z0-9][a-z0-9_-]{1,31}$")
RESERVED_IDS = {"cat", "kun", "mario", "messi"}
MAX_ZIP_BYTES = 20 * 1024 * 1024


def fail(msg: str) -> "None":
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def image_size(path: Path):
    """Best-effort (width, height) for PNG and WebP; None when unknown."""
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        w, h = struct.unpack(">II", data[16:24])
        return w, h
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        chunk = data[12:16]
        if chunk == b"VP8X":
            w = 1 + int.from_bytes(data[24:27], "little")
            h = 1 + int.from_bytes(data[27:30], "little")
            return w, h
        if chunk == b"VP8L" and data[20] == 0x2F:
            bits = int.from_bytes(data[21:25], "little")
            return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
        if chunk == b"VP8 ":  # lossy
            if data[23] == 0x9D and data[24] == 0x01 and data[25] == 0x2A:
                w = struct.unpack("<H", data[26:28])[0] & 0x3FFF
                h = struct.unpack("<H", data[28:30])[0] & 0x3FFF
                return w, h
    return None


def main() -> None:
    ap = argparse.ArgumentParser(description="Package a Bonio skin zip (format v1).")
    ap.add_argument("--id", required=True, help="skin id: ^[a-z0-9][a-z0-9_-]{1,31}$, not a built-in id")
    ap.add_argument("--name", required=True, help="display name (<= 24 chars)")
    ap.add_argument("--subtitle", required=True, help="one-line description (<= 32 chars)")
    ap.add_argument("--sheet", required=True, help="sprite sheet file (webp/png)")
    ap.add_argument("--preview", help="optional preview image (png/jpg/webp, <=1024px)")
    ap.add_argument("--author", help="author name")
    ap.add_argument("--victory-quote", help="bubble line for the completed state")
    ap.add_argument("--version", help="author version string")
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--rows", type=int, default=9)
    ap.add_argument("--frame-w", type=int, default=192)
    ap.add_argument("--frame-h", type=int, default=208)
    ap.add_argument("--out", required=True, help="output zip path")
    args = ap.parse_args()

    if not ID_REGEX.match(args.id):
        fail(f"id '{args.id}' does not match ^[a-z0-9][a-z0-9_-]{{1,31}}$")
    if args.id in RESERVED_IDS:
        fail(f"id '{args.id}' is reserved by a built-in skin; pick another id")
    if len(args.name) > 24:
        fail("name exceeds 24 chars")
    if len(args.subtitle) > 32:
        fail("subtitle exceeds 32 chars")

    sheet = Path(args.sheet)
    if not sheet.is_file():
        fail(f"sprite sheet not found: {sheet}")
    ext = sheet.suffix.lower().lstrip(".")
    if ext not in ("webp", "png"):
        fail(f"sprite sheet must be .webp or .png, got .{ext}")

    grid = {"cols": args.cols, "rows": args.rows, "frame_width": args.frame_w, "frame_height": args.frame_h}
    expect = (args.cols * args.frame_w, args.rows * args.frame_h)
    size = image_size(sheet)
    if size is None:
        print("note: could not parse image header; skipping dimension check (the app validates strictly)")
    elif size != expect:
        fail(f"spritesheet is {size[0]}x{size[1]} but grid implies {expect[0]}x{expect[1]}")

    manifest = {
        "format_version": 1,
        "id": args.id,
        "name": args.name,
        "subtitle": args.subtitle,
        "spritesheet": f"spritesheet.{ext}",
        "grid": grid,
    }
    if args.author:
        manifest["author"] = args.author
    if args.victory_quote:
        manifest["victory_quote"] = args.victory_quote
    if args.version:
        manifest["version"] = args.version

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    preview_src = Path(args.preview) if args.preview else None
    if preview_src is not None:
        if not preview_src.is_file():
            fail(f"preview not found: {preview_src}")
        manifest["preview"] = f"preview{preview_src.suffix.lower()}"

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
        zf.write(sheet, f"spritesheet.{ext}")
        if preview_src is not None:
            zf.write(preview_src, manifest["preview"])

    if out.stat().st_size > MAX_ZIP_BYTES:
        out.unlink()
        fail("resulting zip exceeds the 20MB cap")

    print(f"packed: {out} ({out.stat().st_size} bytes)")
    print(f"  id={args.id} grid={args.cols}x{args.rows} {args.frame_w}x{args.frame_h}")
    print("import on device: 个性化 → 宠物形象 → ＋ 添加 → 从本地导入 / 从链接导入")


if __name__ == "__main__":
    main()
