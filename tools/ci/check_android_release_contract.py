#!/usr/bin/env python3
"""Secret-free checks for the committed Such Moon Launch Android contract."""

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
    return (
        subprocess.run(
            ["git", "-C", str(repo), "ls-files", "--error-unmatch", relative],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--contract", default="ci/android-app.json", type=pathlib.Path
    )
    parser.add_argument("--repo", default=".", type=pathlib.Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    try:
        contract = json.loads(
            (repo / args.contract).read_text(encoding="utf-8")
        )
        if contract.get("schema_version") != 1:
            fail("unsupported or missing Android contract schema_version")
        require_equal(
            contract.get("godot_version", ""),
            "4.6.1-stable",
            "Android Godot version",
        )
        expected_toolchain = {
            "android_gradle_plugin": "8.9.1",
            "build_tools": "36.0.0",
            "compile_sdk": "36",
            "gradle": "8.11.1",
        }
        if contract.get("android_toolchain") != expected_toolchain:
            fail(f"Android toolchain contract must be {expected_toolchain!r}")
        require_equal(contract.get("target_sdk", ""), "36", "Android target SDK")
        require_equal(contract.get("minimum_sdk", ""), "24", "Android minimum SDK")
        require_equal(
            contract.get("play_games_project_id", ""),
            "412379035812",
            "Google Play Games project ID",
        )
        require_equal(
            contract.get("bundle_page_alignment", ""),
            "PAGE_ALIGNMENT_16K",
            "Android App Bundle page alignment",
        )

        project = parse_godot_config(repo / "project.godot")
        presets = parse_godot_config(repo / "export_presets.cfg")
        admob_config = parse_godot_config(
            repo / "addons/AdmobPlugin/android_export.cfg"
        )
        admob_contract = contract["admob"]
        require_equal(
            admob_config.get("General", {}).get("is_real", ""),
            "true",
            "Android AdMob real-inventory policy",
        )
        require_equal(
            unquote(admob_config.get("Release", {}).get("app_id")),
            admob_contract["release_app_id"],
            "Android AdMob release app ID",
        )
        if "3940256099942544" in admob_contract["release_app_id"]:
            fail("Android AdMob release app ID must not use Google's demo publisher")

        options: dict[str, str] | None = None
        for section, values in presets.items():
            if (
                re.fullmatch(r"preset\.\d+", section)
                and unquote(values.get("name")) == contract["export_preset"]
            ):
                require_equal(
                    unquote(values.get("platform")), "Android", "preset platform"
                )
                options = presets.get(f"{section}.options", {})
                break
        if options is None:
            fail(f"missing export preset {contract['export_preset']!r}")

        require_equal(
            unquote(options.get("package/unique_name")),
            contract["bundle_id"],
            "Android package",
        )
        require_equal(
            unquote(options.get("gradle_build/min_sdk")),
            contract["minimum_sdk"],
            "minimum Android SDK",
        )
        require_equal(
            unquote(options.get("gradle_build/target_sdk")),
            contract["target_sdk"],
            "target Android SDK",
        )
        require_equal(
            options.get("gradle_build/use_gradle_build", ""),
            "true",
            "custom Gradle build policy",
        )
        require_equal(
            options.get("gradle_build/export_format", ""),
            "1",
            "Android App Bundle format",
        )
        require_equal(options.get("package/signed", ""), "true", "signed package")
        require_equal(
            options.get("architectures/arm64-v8a", ""),
            "true",
            "Android ARM64 architecture",
        )

        version_name = unquote(options.get("version/name"))
        version_code = unquote(options.get("version/code"))
        if not re.fullmatch(r"\d+\.\d+\.\d+", version_name):
            fail(f"invalid Android version name: {version_name!r}")
        if not re.fullmatch(r"[1-9]\d*", version_code):
            fail(f"invalid positive Android version code: {version_code!r}")
        require_equal(version_name, contract["version_name"], "Android version name")
        require_equal(version_code, contract["version_code"], "Android version code")
        require_equal(
            unquote(project.get("application", {}).get("config/version")),
            version_name,
            "project/Android marketing version",
        )

        enabled_plugins = project.get("editor_plugins", {}).get("enabled", "")
        for plugin in contract.get("required_editor_plugins", []):
            if f'"{plugin}"' not in enabled_plugins:
                fail(f"required Android editor plugin is not enabled: {plugin}")

        require_equal(
            unquote(
                project.get("autoload", {}).get("GodotPlayGameServices")
            ),
            (
                "*res://addons/GodotPlayGameServices/scripts/autoloads/"
                "godot_play_game_services.gd"
            ),
            "Google Play Games autoload",
        )

        for relative in contract.get("tracked_release_inputs", []):
            if not (repo / relative).is_file():
                fail(f"tracked Android release input is missing: {relative}")
            if not tracked(repo, relative):
                fail(f"Android release input is not tracked by Git: {relative}")

        workflow = (repo / ".gitea/workflows/build-android-candidate.yml").read_text(
            encoding="utf-8"
        )
        required_workflow_markers = (
            "runs-on: such-android-release",
            "expected_sha:",
            "version_code:",
            "tools/ci/activate_ci_jdk.sh",
            "tools/ci/play_upload.js assert-monotonic",
            "tools/ci/play_upload.js upload",
        )
        for marker in required_workflow_markers:
            if marker not in workflow:
                fail(f"Android workflow is missing required marker: {marker}")
        required_secrets = (
            "ANDROID_KEYSTORE_BASE64",
            "ANDROID_KEYSTORE_PASSWORD",
            "ANDROID_KEY_ALIAS",
            "ANDROID_KEY_PASSWORD",
            "ANDROID_UPLOAD_CERT_SHA256",
            "ANDROID_GOOGLE_SERVICES_BASE64",
            "ANDROID_PLAY_SERVICE_ACCOUNT_JSON_BASE64",
        )
        for secret in required_secrets:
            if f"secrets.{secret}" not in workflow:
                fail(f"Android workflow does not reference canonical secret: {secret}")
        if "fastlane" in workflow.casefold():
            fail("Android workflow must use the self-contained Play delivery client")

        tracked_files = subprocess.check_output(
            ["git", "-C", str(repo), "ls-files"], text=True
        ).splitlines()
        forbidden_suffixes = (
            ".jks",
            ".keystore",
            ".mobileprovision",
            ".p12",
            ".p8",
        )
        forbidden = [
            path for path in tracked_files if path.lower().endswith(forbidden_suffixes)
        ]
        if forbidden:
            fail(f"signing material must not be tracked: {', '.join(forbidden)}")

        if not contract.get("required_aab_paths"):
            fail("required Android App Bundle paths must be declared")
        if "base/assets/google-services.json" not in contract["required_aab_paths"]:
            fail("final AAB must require the embedded Android Firebase config")
        if not contract.get("required_manifest_markers"):
            fail("required Android manifest markers must be declared")
        require_equal(
            contract.get("firebase_project_id", ""),
            "suchsoftwareapps",
            "Firebase project",
        )

        print(
            "PASS Android contract: "
            f"{contract['app_name']} {version_name} ({version_code}), "
            f"{contract['bundle_id']}, API {contract['target_sdk']}"
        )
        return 0
    except (
        KeyError,
        OSError,
        ValueError,
        json.JSONDecodeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"FAIL Android release contract: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
