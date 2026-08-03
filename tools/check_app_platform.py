#!/usr/bin/env python3
"""Secretless consumer-config and official-bundle policy gate for App Platform v1."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

METHODS = {"email_password", "ethereum_siwe", "smirk_nostr"}
OFFICIAL = {"official_ios", "official_android"}
ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]+$")
HEX_COMMIT = re.compile(r"^[0-9a-f]{40,64}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
APP_ID = re.compile(r"^[a-z][a-z0-9_]*$")
PACK_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SCAN_ROOT = re.compile(r"^[A-Za-z0-9._/-]+$")
TEXT_SUFFIXES = {".dart", ".gd", ".java", ".kt", ".strings", ".xml", ".json", ".plist", ".tscn", ".tres", ".html"}
PURCHASE_PATTERNS = (
    re.compile(r"\bpay(?:ment)?\s+(?:with|using)\s+(?:crypto|bitcoin|ethereum|wownero|monero)\b", re.I),
    re.compile(r"\b(?:crypto|bitcoin|ethereum|wownero|monero)\s+(?:payment|checkout)\b", re.I),
    re.compile(r"\bbuy\b.{0,48}\b(?:with|using)\b.{0,24}\b(?:crypto|bitcoin|ethereum|wownero|monero)\b", re.I),
    re.compile(r"\b(?:stripe|medusa)\s+checkout\b", re.I),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("config", nargs="?", default="config/app-platform-v1.json")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--expect-app")
    parser.add_argument("--promotion", action="store_true", help="require production services and evidence")
    return parser.parse_args()


def semver(value: object) -> tuple[int, int, int]:
    try:
        parts = tuple(int(part) for part in str(value).split("."))
    except ValueError:
        return (0, 0, 0)
    return parts if len(parts) == 3 else (0, 0, 0)


def checked_object(value: object, label: str, errors: list[str]) -> dict:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return {}
    return value


def exact_keys(
    value: dict, expected: set[str], label: str, errors: list[str]
) -> None:
    missing = expected - set(value)
    unknown = set(value) - expected
    if missing:
        errors.append(f"{label} is missing fields: {', '.join(sorted(missing))}")
    if unknown:
        errors.append(f"{label} has unknown fields: {', '.join(sorted(unknown))}")


def scan_official_bundle(root: Path, roots: list[object]) -> list[str]:
    errors: list[str] = []
    for relative in roots:
        relative_path = Path(str(relative))
        if relative_path.is_absolute() or ".." in relative_path.parts:
            errors.append(f"scan root must stay inside the repository: {relative}")
            continue
        path = (root / relative_path).resolve()
        if path != root and root not in path.parents:
            errors.append(f"scan root escaped the repository: {relative}")
            continue
        if not path.exists():
            errors.append(f"scan root does not exist: {relative}")
            continue
        files = [path] if path.is_file() else path.rglob("*")
        for candidate in files:
            if not candidate.is_file() or candidate.suffix.lower() not in TEXT_SUFFIXES:
                continue
            if any(part in {"addons", "build", ".dart_tool", ".godot", "vendor"} for part in candidate.parts):
                continue
            try:
                text = candidate.read_text(errors="ignore")
            except OSError:
                continue
            for pattern in PURCHASE_PATTERNS:
                if pattern.search(text):
                    errors.append(f"official purchase-copy violation: {candidate.relative_to(root)}")
                    break
    return errors


def main() -> int:
    args = parse_args()
    root = Path(args.repo_root).resolve()
    config_path = (root / args.config).resolve() if not Path(args.config).is_absolute() else Path(args.config)
    errors: list[str] = []
    try:
        data = json.loads(config_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL {config_path}: {exc}")
        return 1

    data = checked_object(data, "consumer config", errors)
    exact_keys(
        data,
        {
            "$schema",
            "contract_version",
            "app_id",
            "runtime",
            "contract_pin",
            "brand",
            "services",
            "distribution_profiles",
            "features",
            "official_artifact_scan_roots",
            "release_evidence",
        },
        "consumer config",
        errors,
    )

    app_id = data.get("app_id")
    if not APP_ID.fullmatch(str(app_id or "")):
        errors.append("app_id is invalid")
    if data.get("contract_version") != 1:
        errors.append("contract_version must be 1")
    if not isinstance(data.get("$schema"), str):
        errors.append("$schema must be a string")
    if data.get("runtime") not in {"flutter", "godot", "libgdx", "web"}:
        errors.append("runtime is invalid")
    if args.expect_app and app_id != args.expect_app:
        errors.append(f"expected app_id={args.expect_app}, got {app_id}")
    pin = checked_object(data.get("contract_pin"), "contract_pin", errors)
    exact_keys(pin, {"repo", "commit"}, "contract_pin", errors)
    if pin.get("repo") != "docs" or not HEX_COMMIT.fullmatch(str(pin.get("commit", ""))):
        errors.append("contract_pin must identify a committed docs revision")
    brand = checked_object(data.get("brand"), "brand", errors)
    exact_keys(
        brand,
        {"repo", "commit", "pack_id", "projection_lock_sha256"},
        "brand",
        errors,
    )
    if brand.get("repo") != "such-graphics" or not HEX_COMMIT.fullmatch(str(brand.get("commit", ""))):
        errors.append("brand must identify a committed such-graphics revision")
    if not PACK_ID.fullmatch(str(brand.get("pack_id", ""))):
        errors.append("brand pack_id is invalid")
    if not SHA256.fullmatch(str(brand.get("projection_lock_sha256", ""))):
        errors.append("brand projection lock SHA-256 is invalid")

    services = checked_object(data.get("services"), "services", errors)
    exact_keys(services, {"nakama", "identity", "entitlements"}, "services", errors)
    nakama = checked_object(services.get("nakama"), "services.nakama", errors)
    identity = checked_object(services.get("identity"), "services.identity", errors)
    entitlements = checked_object(
        services.get("entitlements"), "services.entitlements", errors
    )
    exact_keys(
        nakama,
        {"activation", "minimum_version", "endpoint_env"},
        "services.nakama",
        errors,
    )
    exact_keys(
        identity,
        {"activation", "flow", "issuer_env", "client_id_env", "methods"},
        "services.identity",
        errors,
    )
    exact_keys(
        entitlements,
        {"activation", "authority"},
        "services.entitlements",
        errors,
    )
    for name, service in (
        ("nakama", nakama),
        ("identity", identity),
        ("entitlements", entitlements),
    ):
        if service.get("activation") not in {"disabled", "test", "production"}:
            errors.append(f"services.{name}.activation is invalid")
    if semver(nakama.get("minimum_version")) < (3, 40, 0):
        errors.append("Nakama minimum_version must be at least 3.40.0")
    for label, value in {
        "Nakama endpoint": nakama.get("endpoint_env"),
        "OIDC issuer": identity.get("issuer_env"),
        "OIDC client ID": identity.get("client_id_env"),
    }.items():
        if not ENV_NAME.fullmatch(str(value or "")):
            errors.append(f"{label} must be sourced from a named environment/build variable")
    methods = identity.get("methods")
    if (
        identity.get("flow") != "oidc_authorization_code_pkce"
        or not isinstance(methods, list)
        or len(methods) != len(METHODS)
        or not all(isinstance(method, str) for method in methods)
        or set(methods) != METHODS
    ):
        errors.append("identity must use OIDC Authorization Code + PKCE with all three shared methods")
    if entitlements.get("authority") != "such-entitlement-ledger-v1":
        errors.append("entitlement authority must be such-entitlement-ledger-v1")

    profiles = checked_object(
        data.get("distribution_profiles"), "distribution_profiles", errors
    )
    for required_profile in (
        "official_ios",
        "official_android",
        "sideload_android",
        "web",
    ):
        if required_profile not in profiles:
            errors.append(f"distribution_profiles is missing {required_profile}")
    for name, raw_profile in profiles.items():
        profile = checked_object(
            raw_profile, f"distribution_profiles.{name}", errors
        )
        exact_keys(
            profile,
            {"wallet_auth", "external_digital_checkout", "crypto_purchase_surface"},
            f"distribution_profiles.{name}",
            errors,
        )
        for field in (
            "wallet_auth",
            "external_digital_checkout",
            "crypto_purchase_surface",
        ):
            if not isinstance(profile.get(field), bool):
                errors.append(f"distribution_profiles.{name}.{field} must be boolean")
    for name in OFFICIAL:
        profile = checked_object(
            profiles.get(name), f"distribution_profiles.{name}", errors
        )
        if profile.get("external_digital_checkout") is not False:
            errors.append(f"{name} must disable external digital checkout")
        if profile.get("crypto_purchase_surface") is not False:
            errors.append(f"{name} must disable crypto purchase surfaces")
        if profile.get("wallet_auth") is not True:
            errors.append(f"{name} must preserve wallet authentication")

    roots = data.get("official_artifact_scan_roots", [])
    if not isinstance(roots, list) or not roots:
        errors.append("official_artifact_scan_roots must be non-empty")
    else:
        if len({str(root) for root in roots}) != len(roots):
            errors.append("official_artifact_scan_roots must be unique")
        for root_value in roots:
            if not isinstance(root_value, str) or not SCAN_ROOT.fullmatch(root_value):
                errors.append(f"official scan root is invalid: {root_value}")
        errors.extend(scan_official_bundle(root, roots))

    features = checked_object(data.get("features"), "features", errors)
    exact_keys(features, {"room_quiz", "nearby_p2p"}, "features", errors)
    if features.get("room_quiz") not in {"disabled", "pilot", "enabled"}:
        errors.append("features.room_quiz is invalid")
    if features.get("nearby_p2p") not in {"disabled", "research", "enabled"}:
        errors.append("features.nearby_p2p is invalid")

    evidence_map = checked_object(
        data.get("release_evidence"), "release_evidence", errors
    )
    exact_keys(
        evidence_map,
        {"identity", "nakama_restore", "entitlement_replay", "native_products"},
        "release_evidence",
        errors,
    )
    for name in ("identity", "nakama_restore", "entitlement_replay", "native_products"):
        evidence = checked_object(
            evidence_map.get(name), f"release_evidence.{name}", errors
        )
        exact_keys(evidence, {"status", "reference"}, f"release_evidence.{name}", errors)
        if evidence.get("status") not in {"missing", "pass", "not_applicable"}:
            errors.append(f"release_evidence.{name}.status is invalid")
        reference = evidence.get("reference")
        if reference is not None and not isinstance(reference, str):
            errors.append(f"release_evidence.{name}.reference must be string or null")
        if evidence.get("status") == "pass" and not reference:
            errors.append(f"release_evidence.{name} pass needs a reference")

    if args.promotion:
        for name, service in (("identity", identity), ("nakama", nakama), ("entitlements", entitlements)):
            if service.get("activation") != "production":
                errors.append(f"promotion requires services.{name}.activation=production")
        for env_key in (nakama.get("endpoint_env"), identity.get("issuer_env"), identity.get("client_id_env")):
            if ENV_NAME.fullmatch(str(env_key or "")) and not os.environ.get(str(env_key)):
                errors.append(f"promotion environment is missing {env_key}")
        for name in ("identity", "nakama_restore", "entitlement_replay", "native_products"):
            evidence = checked_object(
                evidence_map.get(name), f"release_evidence.{name}", errors
            )
            if evidence.get("status") not in {"pass", "not_applicable"}:
                errors.append(f"promotion evidence is missing: {name}")
            if evidence.get("status") == "pass" and not evidence.get("reference"):
                errors.append(f"passing promotion evidence needs a reference: {name}")

    for error in errors:
        print("FAIL", error)
    print(f"app_consumer_check: app={app_id} promotion={args.promotion} errors={len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
