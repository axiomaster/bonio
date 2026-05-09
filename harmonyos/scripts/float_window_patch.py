#!/usr/bin/env python3
"""Patch HarmonyOS BMS and AccessToken databases for Bonio float window experiments.

This script only edits local database copies. The PowerShell wrapper is
responsible for pulling files from the device, writing patched files back, and
restoring device-side ownership/context.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
from pathlib import Path
from typing import Any


FLOAT_PERMISSION = "ohos.permission.SYSTEM_FLOAT_WINDOW"
DEFAULT_BUNDLE = "com.axiomaster.bonio"
DEFAULT_MODULE = "entry"
DEFAULT_ABILITY = "EntryAbility"
DEFAULT_REASON = "$string:reason_float_window"
DEFAULT_REASON_ID = 16777224
DEFAULT_DEVICE_ID = "PHONE-001"


def open_json(value: str) -> dict[str, Any]:
    parsed = json.loads(value)
    if not isinstance(parsed, dict):
        raise ValueError("installed_bundle VALUE is not a JSON object")
    return parsed


def permission_detail(module_name: str) -> dict[str, Any]:
    return {
        "moduleName": module_name,
        "name": FLOAT_PERMISSION,
        "reason": DEFAULT_REASON,
        "reasonId": DEFAULT_REASON_ID,
        "usedScene": {
            "abilities": [DEFAULT_ABILITY],
            "when": "inuse",
        },
    }


def ensure_permission_detail(items: list[Any], detail: dict[str, Any]) -> bool:
    for item in items:
        if isinstance(item, dict) and item.get("name") == FLOAT_PERMISSION:
            return False
    items.append(detail)
    return True


def ensure_string(items: list[Any], value: str) -> bool:
    if value in items:
        return False
    items.append(value)
    return True


def patch_bundle_json(obj: dict[str, Any]) -> bool:
    changed = False

    base_bundle_info = obj.setdefault("baseBundleInfo", {})
    if not isinstance(base_bundle_info, dict):
        raise ValueError("baseBundleInfo is not an object")

    req_details = base_bundle_info.setdefault("reqPermissionDetails", [])
    req_permissions = base_bundle_info.setdefault("reqPermissions", [])
    req_states = base_bundle_info.setdefault("reqPermissionStates", [])
    if not all(isinstance(v, list) for v in (req_details, req_permissions, req_states)):
        raise ValueError("baseBundleInfo permission fields must be lists")

    changed |= ensure_permission_detail(req_details, permission_detail(DEFAULT_MODULE))
    changed |= ensure_string(req_permissions, FLOAT_PERMISSION)
    if len(req_states) < len(req_permissions):
        req_states.extend([0] * (len(req_permissions) - len(req_states)))
        changed = True

    base_application_info = obj.setdefault("baseApplicationInfo", {})
    if not isinstance(base_application_info, dict):
        raise ValueError("baseApplicationInfo is not an object")
    app_permissions = base_application_info.setdefault("permissions", [])
    if not isinstance(app_permissions, list):
        raise ValueError("baseApplicationInfo.permissions must be a list")
    changed |= ensure_string(app_permissions, FLOAT_PERMISSION)

    inner_modules = obj.setdefault("innerModuleInfos", {})
    if not isinstance(inner_modules, dict):
        raise ValueError("innerModuleInfos is not an object")
    entry_module = inner_modules.setdefault(DEFAULT_MODULE, {})
    if not isinstance(entry_module, dict):
        raise ValueError("innerModuleInfos.entry is not an object")
    request_permissions = entry_module.setdefault("requestPermissions", [])
    if not isinstance(request_permissions, list):
        raise ValueError("innerModuleInfos.entry.requestPermissions must be a list")
    changed |= ensure_permission_detail(request_permissions, permission_detail(""))

    return changed


def patch_bms_db(src: Path, dst: Path, bundle_name: str) -> dict[str, Any]:
    shutil.copy2(src, dst)
    con = sqlite3.connect(dst)
    try:
        row = con.execute(
            "select VALUE from installed_bundle where KEY = ?", (bundle_name,)
        ).fetchone()
        if row is None:
            raise ValueError(f"bundle not found in installed_bundle: {bundle_name}")

        before = row[0]
        bundle_json = open_json(before)
        changed = patch_bundle_json(bundle_json)
        after = json.dumps(bundle_json, ensure_ascii=False, separators=(",", ":"))
        if changed:
            con.execute(
                "update installed_bundle set VALUE = ? where KEY = ?",
                (after, bundle_name),
            )
            con.commit()
        integrity = con.execute("pragma integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ValueError(f"sqlite integrity_check failed for {dst}: {integrity}")
        return {
            "path": str(dst),
            "changed": changed,
            "oldLength": len(before),
            "newLength": len(after),
            "integrity": integrity,
        }
    finally:
        con.close()


def get_token_id(access_db: Path, bundle_name: str) -> int:
    con = sqlite3.connect(access_db)
    try:
        rows = con.execute(
            "select token_id from hap_token_info_table where bundle_name = ?",
            (bundle_name,),
        ).fetchall()
        if not rows:
            raise ValueError(f"bundle not found in hap_token_info_table: {bundle_name}")
        if len(rows) > 1:
            raise ValueError(
                f"multiple token rows found for {bundle_name}; refusing to guess"
            )
        return int(rows[0][0])
    finally:
        con.close()


def infer_device_id(con: sqlite3.Connection, token_id: int) -> str:
    row = con.execute(
        """
        select device_id
        from permission_state_table
        where token_id = ?
        order by case when permission_name = 'ohos.permission.INTERNET' then 0 else 1 end
        limit 1
        """,
        (token_id,),
    ).fetchone()
    return str(row[0]) if row and row[0] else DEFAULT_DEVICE_ID


def patch_access_db(src: Path, dst: Path, token_id: int) -> dict[str, Any]:
    shutil.copy2(src, dst)
    con = sqlite3.connect(dst)
    try:
        device_id = infer_device_id(con, token_id)
        before = con.execute(
            """
            select token_id, permission_name, device_id, is_general, grant_state, grant_flag
            from permission_state_table
            where token_id = ? and permission_name = ?
            """,
            (token_id, FLOAT_PERMISSION),
        ).fetchone()
        con.execute(
            """
            insert or replace into permission_state_table
              (token_id, permission_name, device_id, is_general, grant_state, grant_flag)
            values (?, ?, ?, 1, 0, 4)
            """,
            (token_id, FLOAT_PERMISSION, device_id),
        )
        con.commit()
        after = con.execute(
            """
            select token_id, permission_name, device_id, is_general, grant_state, grant_flag
            from permission_state_table
            where token_id = ? and permission_name = ?
            """,
            (token_id, FLOAT_PERMISSION),
        ).fetchone()
        integrity = con.execute("pragma integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ValueError(f"sqlite integrity_check failed for {dst}: {integrity}")
        return {
            "path": str(dst),
            "changed": tuple(before) != tuple(after) if before else True,
            "tokenId": token_id,
            "before": list(before) if before else None,
            "after": list(after) if after else None,
            "integrity": integrity,
        }
    finally:
        con.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch local HarmonyOS DB copies for SYSTEM_FLOAT_WINDOW."
    )
    parser.add_argument("--bundle", default=DEFAULT_BUNDLE)
    parser.add_argument("--bms-db", required=True, type=Path)
    parser.add_argument("--bms-slave-db", required=True, type=Path)
    parser.add_argument("--access-db", required=True, type=Path)
    parser.add_argument("--access-slave-db", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    if args.bundle != DEFAULT_BUNDLE:
        raise SystemExit(
            f"Refusing to patch non-default bundle {args.bundle!r}. "
            f"Edit the script if this is intentional."
        )

    args.out_dir.mkdir(parents=True, exist_ok=True)

    token_id = get_token_id(args.access_db, args.bundle)
    summary = {
        "bundle": args.bundle,
        "permission": FLOAT_PERMISSION,
        "tokenId": token_id,
        "bms": [
            patch_bms_db(args.bms_db, args.out_dir / "bmsdb.db", args.bundle),
            patch_bms_db(
                args.bms_slave_db, args.out_dir / "bmsdb_slave.db", args.bundle
            ),
        ],
        "accessToken": [
            patch_access_db(args.access_db, args.out_dir / "access_token.db", token_id),
            patch_access_db(
                args.access_slave_db, args.out_dir / "access_token_slave.db", token_id
            ),
        ],
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
