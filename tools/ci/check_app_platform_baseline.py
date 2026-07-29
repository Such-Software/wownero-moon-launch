#!/usr/bin/env python3
"""Verify Moon Launch's pinned generated brand projection and closed baseline."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    config = json.loads((root / "config/app-platform-v1.json").read_text())
    lock_path = root / "config/brand-projection.lock.json"
    lock = json.loads(lock_path.read_text())
    errors: list[str] = []

    brand = config["brand"]
    if digest(lock_path) != brand["projection_lock_sha256"]:
        errors.append("brand projection lock does not match consumer pin")
    if lock.get("pack_id") != brand["pack_id"]:
        errors.append("brand projection pack does not match consumer pin")
    if lock.get("source_commit") != brand["commit"]:
        errors.append("brand projection commit does not match consumer pin")

    godot_projection = root / "game/platform/brand/design_tokens.gd"
    expected_godot = lock.get("files", {}).get("design_tokens.gd")
    if not godot_projection.is_file() or digest(godot_projection) != expected_godot:
        errors.append("checked-in Godot brand projection does not match generated lock")

    for name, service in config["services"].items():
        if service["activation"] != "disabled":
            errors.append(f"baseline requires services.{name}.activation=disabled")

    for error in errors:
        print("FAIL", error)
    print(f"moonlaunch_platform_baseline: errors={len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
