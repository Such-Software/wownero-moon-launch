#!/usr/bin/env python3
"""Secret-free checks for the committed Such Moon Launch iOS contract."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys


def fail(message: str) -> None:
    raise ValueError(message)


def parse_godot_config(path: pathlib.Path) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current = ""
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, {})
            continue
        if "=" in line and current:
            key, value = line.split("=", 1)
            sections[current][key.strip()] = value.strip()
    return sections


def unquote(value: str | None) -> str:
    if value is None:
        return ""
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


def require_equal(actual: str, expected: str, label: str) -> None:
    if actual != expected:
        fail(f"{label}: expected {expected!r}, got {actual!r}")


def tracked(repo: pathlib.Path, relative: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(repo), "ls-files", "--error-unmatch", relative],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", default="ci/ios-app.json", type=pathlib.Path)
    parser.add_argument("--repo", default=".", type=pathlib.Path)
    args = parser.parse_args()

    repo = args.repo.resolve()
    contract_path = (repo / args.contract).resolve()
    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
        if contract.get("schema_version") != 1:
            fail("unsupported or missing iOS contract schema_version")
        require_equal(contract.get("project_adapter", ""), "godot", "project adapter")
        require_equal(
            contract.get("godot_version", ""),
            "4.6.1-stable",
            "iOS Godot version",
        )

        project_path = repo / contract.get("project_path", ".")
        project = parse_godot_config(project_path / "project.godot")
        presets = parse_godot_config(project_path / "export_presets.cfg")

        preset_index = ""
        for section, values in presets.items():
            if re.fullmatch(r"preset\.\d+", section) and unquote(values.get("name")) == contract["export_preset"]:
                preset_index = section.split(".", 1)[1]
                require_equal(unquote(values.get("platform")), "iOS", "preset platform")
                break
        if not preset_index:
            fail(f"missing export preset {contract['export_preset']!r}")

        options = presets.get(f"preset.{preset_index}.options", {})
        require_equal(
            unquote(options.get("application/bundle_identifier")),
            contract["bundle_id"],
            "bundle identifier",
        )
        require_equal(
            unquote(options.get("application/app_store_team_id")),
            contract["team_id"],
            "Apple team",
        )
        require_equal(
            unquote(options.get("application/provisioning_profile_specifier_release")),
            contract["profile_name"],
            "release provisioning profile",
        )
        require_equal(
            unquote(options.get("application/min_ios_version")),
            contract["minimum_ios"],
            "minimum iOS",
        )
        require_equal(
            options.get("application/export_project_only", ""),
            "false",
            "direct IPA export policy",
        )
        require_equal(
            options.get("entitlements/game_center", ""),
            "true",
            "Game Center export entitlement",
        )

        short_version = unquote(options.get("application/short_version"))
        build_number = unquote(options.get("application/version"))
        if not re.fullmatch(r"\d+\.\d+\.\d+", short_version):
            fail(f"invalid iOS marketing version: {short_version!r}")
        if not re.fullmatch(r"[1-9]\d*", build_number):
            fail(f"invalid positive iOS build number: {build_number!r}")
        require_equal(
            unquote(project.get("application", {}).get("config/version")),
            short_version,
            "project/iOS marketing version",
        )

        for plugin in contract.get("required_plugins", []):
            require_equal(options.get(f"plugins/{plugin}", ""), "true", f"iOS plugin {plugin}")

        for relative in contract.get("tracked_release_inputs", []):
            if not (repo / relative).is_file():
                fail(f"tracked release input is missing: {relative}")
            if not tracked(repo, relative):
                fail(f"release input is not tracked by Git: {relative}")

        forbidden_suffixes = (".mobileprovision", ".p12", ".p8")
        tracked_files = subprocess.check_output(
            ["git", "-C", str(repo), "ls-files"], text=True
        ).splitlines()
        forbidden = [path for path in tracked_files if path.endswith(forbidden_suffixes)]
        if forbidden:
            fail(f"signing material must not be tracked: {', '.join(forbidden)}")

        seed = contract.get("seed", {})
        if seed.get("hash_algorithm") != "sha256-tree-v1":
            fail("seed hash_algorithm must be sha256-tree-v1")
        entries = seed.get("entries")
        if not isinstance(entries, list) or not entries:
            fail("seed entries must be declared")
        for entry in entries:
            digest = entry.get("sha256", "")
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                fail(f"invalid seed SHA-256 for {entry.get('path')!r}")

        payload = contract.get("required_payload_names")
        if not isinstance(payload, list) or not payload:
            fail("required iOS payload names must be declared")

        privacy_manifests = contract.get("required_privacy_manifests")
        if not isinstance(privacy_manifests, list) or not privacy_manifests:
            fail("required iOS privacy manifests must be declared")
        privacy_paths: set[str] = set()
        for manifest in privacy_manifests:
            if not isinstance(manifest, dict):
                fail("privacy manifest contracts must be objects")
            relative = manifest.get("relative_path", "")
            if (
                not isinstance(relative, str)
                or not relative
                or relative.startswith("/")
                or ".." in pathlib.PurePosixPath(relative).parts
                or not relative.endswith("PrivacyInfo.xcprivacy")
            ):
                fail(f"invalid privacy manifest relative_path: {relative!r}")
            if relative in privacy_paths:
                fail(f"duplicate privacy manifest relative_path: {relative}")
            privacy_paths.add(relative)
            collected_types = manifest.get("collected_data_types", [])
            tracking_types = manifest.get("tracking_data_types", [])
            if not isinstance(collected_types, list) or not all(
                isinstance(item, str) and item.startswith("NSPrivacyCollectedDataType")
                for item in collected_types
            ):
                fail(f"invalid collected_data_types for privacy manifest {relative}")
            if not isinstance(tracking_types, list) or not set(tracking_types).issubset(
                set(collected_types)
            ):
                fail(f"tracking_data_types must be a subset for privacy manifest {relative}")
            if "tracking" in manifest and not isinstance(manifest["tracking"], bool):
                fail(f"privacy manifest tracking must be Boolean for {relative}")

        print(
            "PASS iOS contract: "
            f"{contract['app_name']} {short_version} ({build_number}), "
            f"{contract['bundle_id']}, iOS {contract['minimum_ios']}+"
        )
        return 0
    except (
        KeyError,
        OSError,
        ValueError,
        json.JSONDecodeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"FAIL iOS release contract: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
