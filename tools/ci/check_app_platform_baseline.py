#!/usr/bin/env python3
"""Verify Moon Launch's pinned generated brand projection and closed baseline."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


EXPECTED_CONTRACT_COMMIT = "4c202f2a27685b4d3658c0fe78efa0eee7e3168a"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    config = json.loads((root / "config/app-platform-v1.json").read_text())
    runtime_manifest = json.loads(
        (root / "server/nakama/runtime-manifest.template.json").read_text()
    )
    lock_path = root / "config/brand-projection.lock.json"
    lock = json.loads(lock_path.read_text())
    errors: list[str] = []

    contract_pin = config["contract_pin"]
    if contract_pin.get("repo") != "docs":
        errors.append("consumer contract pin must reference docs")
    if contract_pin.get("commit") != EXPECTED_CONTRACT_COMMIT:
        errors.append("consumer contract pin is not the reviewed contract commit")
    if runtime_manifest.get("contract_source_commit") != contract_pin.get("commit"):
        errors.append("runtime manifest and consumer contract pins do not match")

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

    website_projection = root / "website/app/brand.css"
    expected_website = lock.get("files", {}).get("brand.css")
    if not website_projection.is_file() or digest(website_projection) != expected_website:
        errors.append("checked-in website brand projection does not match generated lock")

    website_projection_metadata = root / "website/app/brand.json"
    expected_metadata = lock.get("files", {}).get("brand.json")
    if (
        not website_projection_metadata.is_file()
        or digest(website_projection_metadata) != expected_metadata
    ):
        errors.append("checked-in website brand metadata does not match generated lock")

    for name, service in config["services"].items():
        if service["activation"] != "disabled":
            errors.append(f"baseline requires services.{name}.activation=disabled")

    for error in errors:
        print("FAIL", error)
    print(f"moonlaunch_platform_baseline: errors={len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
