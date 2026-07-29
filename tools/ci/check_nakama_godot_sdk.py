#!/usr/bin/env python3
"""Verify the selectively vendored Heroic Labs Nakama Godot SDK."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import sys


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    root = pathlib.Path(__file__).resolve().parents[2]
    lock_path = root / "config/nakama-godot-sdk.lock.json"
    sdk_root = root / "addons/com.heroiclabs.nakama"
    errors: list[str] = []

    try:
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"FAIL Nakama Godot SDK lock: {error}", file=sys.stderr)
        return 1

    if lock.get("schema_version") != 1:
        errors.append("unsupported SDK lock schema")
    if lock.get("upstream") != "https://github.com/heroiclabs/nakama-godot":
        errors.append("unexpected SDK upstream")
    if lock.get("tag") != "v3.4.0":
        errors.append("unexpected SDK tag")
    if not re.fullmatch(r"[0-9a-f]{40}", str(lock.get("commit", ""))):
        errors.append("SDK commit is not a full Git object ID")
    if not re.fullmatch(
        r"[0-9a-f]{64}", str(lock.get("archive_sha256", ""))
    ):
        errors.append("SDK archive SHA-256 is invalid")

    expected = lock.get("files")
    if not isinstance(expected, dict) or not expected:
        errors.append("SDK file lock is empty")
        expected = {}

    actual = {
        path.relative_to(sdk_root).as_posix()
        for path in sdk_root.rglob("*")
        if (
            path.is_file()
            and path.name != "UPSTREAM.md"
            and path.suffix != ".uid"
        )
    }
    expected_paths = set(expected)
    for relative in sorted(expected_paths - actual):
        errors.append(f"vendored SDK file is missing: {relative}")
    for relative in sorted(actual - expected_paths):
        errors.append(f"unexpected vendored SDK file: {relative}")
    for relative in sorted(actual & expected_paths):
        expected_digest = expected[relative]
        if not re.fullmatch(r"[0-9a-f]{64}", str(expected_digest)):
            errors.append(f"invalid locked SDK digest: {relative}")
        elif digest(sdk_root / relative) != expected_digest:
            errors.append(f"vendored SDK file drift: {relative}")

    for error in errors:
        print("FAIL", error)
    print(
        "nakama_godot_sdk_check: "
        f"tag={lock.get('tag')} files={len(actual)} errors={len(errors)}"
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
