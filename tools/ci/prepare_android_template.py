#!/usr/bin/env python3
"""Prepare a disposable Godot 4.6.1 Android template for API 36.

Godot 4.6.1 ships a Gradle template pinned to API 35 / AGP 8.6.1. Such Moon
Launch targets API 36, whose supported minimum is AGP 8.9.1. This script
updates only a resolved template below ~/Build and fails if the upstream
template or committed contract drift unexpectedly.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import xml.etree.ElementTree as ET


class TemplateError(RuntimeError):
    """The generated Android template is unsafe or incompatible."""


def require_below(path: pathlib.Path, parent: pathlib.Path) -> None:
    try:
        path.relative_to(parent)
    except ValueError as error:
        raise TemplateError(
            f"Android template must resolve below {parent}, got {path}"
        ) from error


def update_setting(
    payload: str,
    *,
    label: str,
    pattern: str,
    baseline: str,
    expected: str,
) -> str:
    match = re.search(pattern, payload, flags=re.MULTILINE)
    if match is None:
        raise TemplateError(f"Godot Android template is missing {label}")
    actual = match.group("value")
    if actual == expected:
        return payload
    if actual != baseline:
        raise TemplateError(
            f"unexpected {label}: expected stock {baseline!r} or prepared "
            f"{expected!r}, got {actual!r}"
        )
    start, end = match.span("value")
    return f"{payload[:start]}{expected}{payload[end:]}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default="android/build", type=pathlib.Path)
    parser.add_argument(
        "--contract", default="ci/android-app.json", type=pathlib.Path
    )
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        build_root = (pathlib.Path.home() / "Build").resolve(strict=True)
        require_below(root, build_root)
        contract = json.loads(args.contract.read_text(encoding="utf-8"))
        toolchain = contract["android_toolchain"]
        expected = {
            "android_gradle_plugin": "8.9.1",
            "build_tools": "36.0.0",
            "compile_sdk": "36",
            "gradle": "8.11.1",
        }
        if toolchain != expected:
            raise TemplateError(
                f"committed Android toolchain contract must be {expected!r}"
            )
        if contract.get("target_sdk") != toolchain["compile_sdk"]:
            raise TemplateError("compile and target SDK contracts must match")

        gdignore_path = root / ".gdignore"
        if gdignore_path.is_symlink() or (
            gdignore_path.exists() and not gdignore_path.is_file()
        ):
            raise TemplateError("Android template .gdignore must be a regular file")
        if gdignore_path.exists():
            gdignore = gdignore_path.read_text(encoding="utf-8")
            if gdignore not in ("", "\n"):
                raise TemplateError("Android template has an unexpected .gdignore")
        gdignore_path.write_text("\n", encoding="utf-8")
        import_sidecars = {
            path.relative_to(root).as_posix() for path in root.rglob("*.import")
        }
        stock_sidecars = {"src/instrumented/assets/icon.svg.import"}
        unexpected_sidecars = {
            path
            for path in import_sidecars - stock_sidecars
            if not path.startswith("assetPackInstallTime/src/main/assets/")
        }
        missing_sidecars = stock_sidecars - import_sidecars
        if missing_sidecars or unexpected_sidecars:
            raise TemplateError(
                "Android template Godot import sidecars drifted: "
                f"missing={sorted(missing_sidecars)!r}, "
                f"unexpected={sorted(unexpected_sidecars)!r}"
            )

        config_path = root / "config.gradle"
        wrapper_path = root / "gradle/wrapper/gradle-wrapper.properties"
        if not (root / "build.gradle").is_file():
            raise TemplateError("Android template has no build.gradle")
        payload = config_path.read_text(encoding="utf-8")
        payload = update_setting(
            payload,
            label="Android Gradle plugin",
            pattern=r"androidGradlePlugin\s*:\s*'(?P<value>[^']+)'",
            baseline="8.6.1",
            expected=toolchain["android_gradle_plugin"],
        )
        payload = update_setting(
            payload,
            label="compile SDK",
            pattern=r"compileSdk\s*:\s*(?P<value>\d+)",
            baseline="35",
            expected=toolchain["compile_sdk"],
        )
        payload = update_setting(
            payload,
            label="default target SDK",
            pattern=r"targetSdk\s*:\s*(?P<value>\d+)",
            baseline="35",
            expected=contract["target_sdk"],
        )
        payload = update_setting(
            payload,
            label="Android build tools",
            pattern=r"buildTools\s*:\s*'(?P<value>[^']+)'",
            baseline="35.0.1",
            expected=toolchain["build_tools"],
        )

        wrapper = wrapper_path.read_text(encoding="utf-8")
        distribution = re.search(
            r"^distributionUrl=.*gradle-(?P<value>[0-9.]+)-bin\.zip$",
            wrapper,
            flags=re.MULTILINE,
        )
        if distribution is None or distribution.group("value") != toolchain["gradle"]:
            actual = distribution.group("value") if distribution else "missing"
            raise TemplateError(
                f"Gradle wrapper: expected {toolchain['gradle']!r}, got {actual!r}"
            )

        games_id = contract.get("play_games_project_id", "")
        if games_id != "412379035812":
            raise TemplateError("unexpected Google Play Games project ID")
        games_ids_path = root / "res/values/games-ids.xml"
        if games_ids_path.exists():
            games_ids = ET.parse(games_ids_path).getroot()
            matches = [
                item
                for item in games_ids.findall("string")
                if item.get("name") == "game_services_project_id"
            ]
            if len(matches) != 1 or (matches[0].text or "").strip() != games_id:
                raise TemplateError("generated Play Games resource has the wrong ID")
        else:
            games_ids_path.parent.mkdir(parents=True, exist_ok=True)
            games_ids_path.write_text(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                "<resources>\n"
                '    <string name="game_services_project_id" '
                f'translatable="false">{games_id}</string>\n'
                "</resources>\n",
                encoding="utf-8",
            )

        config_path.write_text(payload, encoding="utf-8")
        print(
            "PASS prepared Android template: "
            f"AGP {toolchain['android_gradle_plugin']}, "
            f"compile/target API {toolchain['compile_sdk']}, "
            f"build tools {toolchain['build_tools']}, "
            f"Gradle {toolchain['gradle']}, Play Games {games_id}, "
            "scanner guard installed"
        )
        return 0
    except (
        KeyError,
        OSError,
        ET.ParseError,
        json.JSONDecodeError,
        TemplateError,
    ) as error:
        print(f"FAIL Android template preparation: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
