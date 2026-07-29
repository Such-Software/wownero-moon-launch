#!/usr/bin/env python3
"""Inspect the final signed iOS IPA against a committed app contract.

Production mode is fail-closed and requires Apple's ``codesign`` and
``security`` tools. ``--fixture-mode`` exists only for hermetic Linux tests;
release workflows must never pass it.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from typing import Any, Iterable

TOOL_VERSION = "1.0.1"


class InspectionError(RuntimeError):
    """A release-contract failure."""


def json_value(value: Any) -> Any:
    if isinstance(value, bytes):
        return value.hex()
    if isinstance(value, (dt.datetime, dt.date)):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(key): json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    return value


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command: list[str]) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(command, check=False, capture_output=True)
    except FileNotFoundError as error:
        raise InspectionError(f"required command is unavailable: {command[0]}") from error


def plist_from_command(command: list[str], label: str) -> dict[str, Any]:
    result = run(command)
    output = result.stdout + b"\n" + result.stderr
    start = output.find(b"<?xml")
    if start < 0:
        start = output.find(b"bplist")
    if start < 0:
        detail = output.decode("utf-8", errors="replace").strip()
        raise InspectionError(f"{label} did not emit a plist: {detail}")
    if output[start : start + 6] == b"bplist":
        payload = output[start:]
    else:
        end = output.find(b"</plist>", start)
        if end < 0:
            raise InspectionError(f"{label} emitted a truncated plist")
        payload = output[start : end + len(b"</plist>")]
    try:
        value = plistlib.loads(payload)
    except Exception as error:
        raise InspectionError(f"{label} emitted an invalid plist: {error}") from error
    if not isinstance(value, dict):
        raise InspectionError(f"{label} plist root is not a dictionary")
    return value


def load_contract(path: pathlib.Path) -> dict[str, Any]:
    try:
        contract = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InspectionError(f"cannot read contract {path}: {error}") from error
    if contract.get("schema_version") != 1:
        raise InspectionError("ci/ios-app.json must use schema_version 1")
    required = (
        "app_name",
        "bundle_id",
        "team_id",
        "profile_name",
        "minimum_ios",
        "uses_non_exempt_encryption",
        "allowed_entitlements",
    )
    missing = [field for field in required if field not in contract]
    if missing:
        raise InspectionError(f"contract omits required fields: {', '.join(missing)}")
    if not isinstance(contract["uses_non_exempt_encryption"], bool):
        raise InspectionError("uses_non_exempt_encryption must be a Boolean")
    allowed = contract["allowed_entitlements"]
    if not isinstance(allowed, list) or not all(isinstance(item, str) for item in allowed):
        raise InspectionError("allowed_entitlements must be an array of strings")
    baseline = {
        "application-identifier",
        "beta-reports-active",
        "com.apple.developer.team-identifier",
        "get-task-allow",
    }
    if not baseline.issubset(set(allowed)):
        raise InspectionError(
            "allowed_entitlements omits App Store baseline keys: "
            + ", ".join(sorted(baseline - set(allowed)))
        )
    return contract


def safe_extract(ipa: pathlib.Path, destination: pathlib.Path) -> None:
    try:
        archive = zipfile.ZipFile(ipa)
    except (OSError, zipfile.BadZipFile) as error:
        raise InspectionError(f"invalid IPA zip: {error}") from error
    with archive:
        for member in archive.infolist():
            normalized = pathlib.PurePosixPath(member.filename)
            if normalized.is_absolute() or ".." in normalized.parts:
                raise InspectionError(f"IPA contains unsafe path: {member.filename!r}")
        archive.extractall(destination)


def matching_files(app: pathlib.Path, pattern: str) -> list[str]:
    matches: list[str] = []
    for path in app.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(app).as_posix()
        if fnmatch.fnmatch(relative, pattern) or fnmatch.fnmatch(path.name, pattern):
            matches.append(relative)
    return sorted(matches)


def profile_entitlement_supports(profile_value: Any, signed_value: Any) -> bool:
    if profile_value == signed_value:
        return True
    if isinstance(profile_value, str) and isinstance(signed_value, str):
        return fnmatch.fnmatch(signed_value, profile_value)
    if isinstance(profile_value, list) and isinstance(signed_value, list):
        return all(
            any(profile_entitlement_supports(candidate, item) for candidate in profile_value)
            for item in signed_value
        )
    return False


class Inspector:
    def __init__(
        self,
        ipa: pathlib.Path,
        contract: dict[str, Any],
        expected_version: str | None,
        expected_build: str | None,
        expected_profile_uuid: str | None,
        fixture_mode: bool,
    ) -> None:
        self.ipa = ipa
        self.contract = contract
        self.expected_version = expected_version
        self.expected_build = expected_build
        self.expected_profile_uuid = expected_profile_uuid
        self.fixture_mode = fixture_mode
        self.checks: list[dict[str, str]] = []
        self.report: dict[str, Any] = {
            "schema_version": 1,
            "tool": {"name": "such-fleet-ios-release/inspect_ipa", "version": TOOL_VERSION},
            "mode": "fixture" if fixture_mode else "production-signed",
            "ipa": str(ipa),
            "result": "FAIL",
        }

    def passed(self, name: str, detail: str) -> None:
        self.checks.append({"name": name, "status": "PASS", "detail": detail})

    def require(self, condition: bool, name: str, detail: str) -> None:
        if not condition:
            self.checks.append({"name": name, "status": "FAIL", "detail": detail})
            raise InspectionError(detail)
        self.passed(name, detail)

    def inspect(self) -> dict[str, Any]:
        self.require(self.ipa.is_file(), "ipa.exists", f"IPA exists: {self.ipa}")
        self.require(self.ipa.stat().st_size > 0, "ipa.nonempty", "IPA is nonempty")
        self.report["ipa_size_bytes"] = self.ipa.stat().st_size
        self.report["ipa_sha256"] = sha256_file(self.ipa)

        with tempfile.TemporaryDirectory(prefix="such-ios-ipa-") as temp:
            root = pathlib.Path(temp)
            safe_extract(self.ipa, root)
            apps = sorted((root / "Payload").glob("*.app"))
            self.require(
                len(apps) == 1 and apps[0].is_dir(),
                "payload.single_app",
                f"IPA contains exactly one top-level app (found {len(apps)})",
            )
            app = apps[0]
            info_path = app / "Info.plist"
            self.require(info_path.is_file(), "info.exists", "app contains Info.plist")
            try:
                info = plistlib.loads(info_path.read_bytes())
            except Exception as error:
                raise InspectionError(f"cannot parse final Info.plist: {error}") from error

            identity = {
                "bundle_id": info.get("CFBundleIdentifier"),
                "marketing_version": info.get("CFBundleShortVersionString"),
                "build_number": str(info.get("CFBundleVersion", "")),
                "minimum_ios": info.get("MinimumOSVersion"),
                "executable": info.get("CFBundleExecutable"),
                "uses_non_exempt_encryption": info.get("ITSAppUsesNonExemptEncryption"),
                "encryption_compliance_code": info.get("ITSEncryptionExportComplianceCode"),
            }
            self.report["identity"] = identity
            self.require(
                identity["bundle_id"] == self.contract["bundle_id"],
                "identity.bundle_id",
                f"bundle ID is {identity['bundle_id']!r}",
            )
            if self.expected_version:
                self.require(
                    identity["marketing_version"] == self.expected_version,
                    "identity.marketing_version",
                    f"marketing version is {identity['marketing_version']!r}",
                )
            if self.expected_build:
                self.require(
                    identity["build_number"] == self.expected_build,
                    "identity.build_number",
                    f"build number is {identity['build_number']!r}",
                )
            self.require(
                identity["minimum_ios"] == self.contract["minimum_ios"],
                "identity.minimum_ios",
                f"minimum iOS is {identity['minimum_ios']!r}",
            )
            self.require(
                identity["uses_non_exempt_encryption"]
                is self.contract["uses_non_exempt_encryption"],
                "compliance.encryption",
                "final IPA encryption declaration: "
                f"expected {self.contract['uses_non_exempt_encryption']!r}, "
                f"got {identity['uses_non_exempt_encryption']!r}",
            )
            expected_code = self.contract.get("encryption_compliance_code")
            if expected_code is not None:
                self.require(
                    identity["encryption_compliance_code"] == expected_code,
                    "compliance.encryption_code",
                    "final IPA carries the reviewed encryption compliance code",
                )

            executable_name = identity["executable"]
            self.require(
                isinstance(executable_name, str)
                and bool(executable_name)
                and (app / executable_name).is_file()
                and (app / executable_name).stat().st_size > 0,
                "payload.executable",
                "declared executable exists and is nonempty",
            )
            executable = app / str(executable_name)

            payload_matches: dict[str, list[str]] = {}
            required_patterns = list(self.contract.get("required_payload_names", []))
            required_patterns.extend(self.contract.get("required_payload_globs", []))
            if self.contract.get("privacy_manifest_required", True):
                required_patterns.append("PrivacyInfo.xcprivacy")
            for pattern in dict.fromkeys(required_patterns):
                matches = matching_files(app, pattern)
                payload_matches[pattern] = matches
                self.require(
                    bool(matches),
                    f"payload.required.{pattern}",
                    f"required payload {pattern!r}: {', '.join(matches) if matches else 'missing'}",
                )
            self.report["required_payload_matches"] = payload_matches

            if self.fixture_mode:
                fixture_entitlements = app / "fixture-entitlements.plist"
                self.require(
                    fixture_entitlements.is_file(),
                    "fixture.entitlements",
                    "fixture carries fixture-entitlements.plist",
                )
                entitlements = plistlib.loads(fixture_entitlements.read_bytes())
                embedded_path = app / "embedded.mobileprovision"
                self.require(
                    embedded_path.is_file(),
                    "profile.embedded",
                    "fixture carries embedded.mobileprovision",
                )
                profile = plistlib.loads(embedded_path.read_bytes())
                signature = {"fixture_mode": True}
                self.passed(
                    "signature.fixture_skip",
                    "fixture mode explicitly skipped Apple signature verification",
                )
            else:
                verify = run(
                    ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)]
                )
                verify_detail = (verify.stdout + verify.stderr).decode(
                    "utf-8", errors="replace"
                ).strip()
                self.require(
                    verify.returncode == 0,
                    "signature.codesign_verify",
                    verify_detail or "codesign verification passed",
                )
                metadata_result = run(["codesign", "-dv", "--verbose=4", str(app)])
                metadata_text = (metadata_result.stdout + metadata_result.stderr).decode(
                    "utf-8", errors="replace"
                )
                signature = {}
                for field in ("Identifier", "TeamIdentifier", "Authority"):
                    values = re.findall(rf"^{field}=(.+)$", metadata_text, re.MULTILINE)
                    if values:
                        signature[field] = values if field == "Authority" else values[-1]
                self.require(
                    signature.get("TeamIdentifier") == self.contract["team_id"],
                    "signature.team",
                    f"signature team is {signature.get('TeamIdentifier')!r}",
                )
                authorities = signature.get("Authority", [])
                self.require(
                    any("Apple Distribution" in item for item in authorities),
                    "signature.authority",
                    "signature chain contains Apple Distribution authority",
                )
                entitlements = plist_from_command(
                    ["codesign", "-d", "--entitlements", ":-", str(app)],
                    "codesign entitlements",
                )
                embedded_path = app / "embedded.mobileprovision"
                self.require(
                    embedded_path.is_file() and embedded_path.stat().st_size > 0,
                    "profile.embedded",
                    "signed app embeds a provisioning profile",
                )
                profile = plist_from_command(
                    ["security", "cms", "-D", "-i", str(embedded_path)],
                    "embedded provisioning profile",
                )
            self.report["signature"] = signature

            team = self.contract["team_id"]
            bundle = self.contract["bundle_id"]
            baseline_entitlements = {
                "application-identifier": f"{team}.{bundle}",
                "com.apple.developer.team-identifier": team,
                "get-task-allow": False,
                "beta-reports-active": True,
            }
            expected_entitlements = dict(baseline_entitlements)
            expected_entitlements.update(self.contract.get("required_entitlements", {}))
            for key, wanted in expected_entitlements.items():
                self.require(
                    entitlements.get(key) == wanted,
                    f"entitlement.required.{key}",
                    f"signed entitlement {key!r} is {entitlements.get(key)!r}",
                )
            allowed = set(self.contract["allowed_entitlements"])
            unexpected = sorted(set(entitlements) - allowed)
            self.require(
                not unexpected,
                "entitlement.allowlist",
                "signed entitlement keys are allowlisted"
                if not unexpected
                else f"unexpected signed entitlements: {', '.join(unexpected)}",
            )
            forbidden = sorted(
                key
                for key in self.contract.get("forbidden_entitlements", [])
                if key in entitlements
            )
            self.require(
                not forbidden,
                "entitlement.forbidden",
                "no forbidden product entitlements are signed"
                if not forbidden
                else f"forbidden signed entitlements: {', '.join(forbidden)}",
            )
            self.report["entitlements"] = json_value(entitlements)

            profile_entitlements = profile.get("Entitlements", {})
            profile_team = (profile.get("TeamIdentifier") or [""])[0]
            profile_summary = {
                "name": profile.get("Name"),
                "uuid": profile.get("UUID"),
                "team_id": profile_team,
                "expiration": json_value(profile.get("ExpirationDate")),
                "application_identifier": profile_entitlements.get(
                    "application-identifier"
                ),
            }
            self.report["profile"] = profile_summary
            self.require(
                profile_summary["name"] == self.contract["profile_name"],
                "profile.name",
                f"embedded profile name is {profile_summary['name']!r}",
            )
            self.require(
                profile_team == team,
                "profile.team",
                f"embedded profile team is {profile_team!r}",
            )
            self.require(
                profile_entitlements.get("application-identifier") == f"{team}.{bundle}",
                "profile.bundle",
                "embedded profile application identifier matches app identity",
            )
            if self.expected_profile_uuid:
                self.require(
                    profile_summary["uuid"] == self.expected_profile_uuid,
                    "profile.uuid",
                    f"embedded profile UUID is {profile_summary['uuid']!r}",
                )
            expires = profile.get("ExpirationDate")
            now = dt.datetime.now(dt.timezone.utc)
            if isinstance(expires, dt.datetime) and expires.tzinfo is None:
                expires = expires.replace(tzinfo=dt.timezone.utc)
            self.require(
                isinstance(expires, dt.datetime) and expires > now,
                "profile.expiration",
                f"embedded profile expires {profile_summary['expiration']!r}",
            )
            unsupported = []
            for key, value in entitlements.items():
                if key not in profile_entitlements or not profile_entitlement_supports(
                    profile_entitlements[key], value
                ):
                    unsupported.append(key)
            self.require(
                not unsupported,
                "profile.entitlements",
                "embedded profile supports every signed entitlement"
                if not unsupported
                else "profile does not support signed entitlements: "
                + ", ".join(sorted(unsupported)),
            )

            symbols: dict[str, bool] = {}
            if self.contract.get("required_linked_symbols"):
                result = run(["nm", "-gU", str(executable)])
                text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
                self.require(
                    result.returncode == 0,
                    "native_symbols.read",
                    "native symbol table is readable",
                )
                for symbol in self.contract["required_linked_symbols"]:
                    symbols[symbol] = symbol in text
                    self.require(
                        symbols[symbol],
                        f"native_symbols.required.{symbol}",
                        f"linked executable contains {symbol!r}",
                    )
            self.report["required_linked_symbols"] = symbols

        self.report["checks"] = self.checks
        self.report["result"] = "PASS"
        return self.report


def write_report(path: pathlib.Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(json_value(report), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", required=True, type=pathlib.Path)
    parser.add_argument("--contract", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--expected-version")
    parser.add_argument("--expected-build")
    parser.add_argument("--expected-profile-uuid")
    parser.add_argument(
        "--fixture-mode",
        action="store_true",
        help="TEST ONLY: read plist fixtures instead of verifying an Apple signature",
    )
    return parser.parse_args(list(argv))


def main(argv: Iterable[str] = sys.argv[1:]) -> int:
    args = parse_args(argv)
    report: dict[str, Any] = {
        "schema_version": 1,
        "tool": {"name": "such-fleet-ios-release/inspect_ipa", "version": TOOL_VERSION},
        "mode": "fixture" if args.fixture_mode else "production-signed",
        "ipa": str(args.ipa),
        "result": "FAIL",
    }
    try:
        contract = load_contract(args.contract)
        inspector = Inspector(
            ipa=args.ipa,
            contract=contract,
            expected_version=args.expected_version,
            expected_build=args.expected_build,
            expected_profile_uuid=args.expected_profile_uuid,
            fixture_mode=args.fixture_mode,
        )
        report = inspector.report
        report = inspector.inspect()
    except (InspectionError, OSError, plistlib.InvalidFileException) as error:
        report.setdefault("checks", [])
        report["error"] = str(error)
        write_report(args.output, report)
        print(f"IPA inspection: FAIL: {error}", file=sys.stderr)
        return 1
    write_report(args.output, report)
    identity = report["identity"]
    print(
        "IPA inspection: PASS "
        f"{identity['bundle_id']} {identity['marketing_version']} "
        f"({identity['build_number']}) sha256={report['ipa_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
