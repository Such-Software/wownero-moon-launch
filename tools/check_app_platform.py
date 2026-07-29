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
HEX_COMMIT = re.compile(r"^[0-9a-f]{7,64}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
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

    app_id = data.get("app_id")
    if data.get("contract_version") != 1:
        errors.append("contract_version must be 1")
    if args.expect_app and app_id != args.expect_app:
        errors.append(f"expected app_id={args.expect_app}, got {app_id}")
    pin = data.get("contract_pin", {})
    if pin.get("repo") != "docs" or not HEX_COMMIT.fullmatch(str(pin.get("commit", ""))):
        errors.append("contract_pin must identify a committed docs revision")
    brand = data.get("brand", {})
    if brand.get("repo") != "such-graphics" or not HEX_COMMIT.fullmatch(str(brand.get("commit", ""))):
        errors.append("brand must identify a committed such-graphics revision")
    if not SHA256.fullmatch(str(brand.get("projection_lock_sha256", ""))):
        errors.append("brand projection lock SHA-256 is invalid")

    services = data.get("services", {})
    nakama = services.get("nakama", {})
    identity = services.get("identity", {})
    entitlements = services.get("entitlements", {})
    if semver(nakama.get("minimum_version")) < (3, 40, 0):
        errors.append("Nakama minimum_version must be at least 3.40.0")
    for label, value in {
        "Nakama endpoint": nakama.get("endpoint_env"),
        "OIDC issuer": identity.get("issuer_env"),
        "OIDC client ID": identity.get("client_id_env"),
    }.items():
        if not ENV_NAME.fullmatch(str(value or "")):
            errors.append(f"{label} must be sourced from a named environment/build variable")
    if identity.get("flow") != "oidc_authorization_code_pkce" or set(identity.get("methods", [])) != METHODS:
        errors.append("identity must use OIDC Authorization Code + PKCE with all three shared methods")
    if entitlements.get("authority") != "such-entitlement-ledger-v1":
        errors.append("entitlement authority must be such-entitlement-ledger-v1")

    profiles = data.get("distribution_profiles", {})
    for name in OFFICIAL:
        profile = profiles.get(name, {})
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
        errors.extend(scan_official_bundle(root, roots))

    if args.promotion:
        for name, service in (("identity", identity), ("nakama", nakama), ("entitlements", entitlements)):
            if service.get("activation") != "production":
                errors.append(f"promotion requires services.{name}.activation=production")
        for env_key in (nakama.get("endpoint_env"), identity.get("issuer_env"), identity.get("client_id_env")):
            if ENV_NAME.fullmatch(str(env_key or "")) and not os.environ.get(str(env_key)):
                errors.append(f"promotion environment is missing {env_key}")
        evidence_map = data.get("release_evidence", {})
        for name in ("identity", "nakama_restore", "entitlement_replay", "native_products"):
            evidence = evidence_map.get(name, {})
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
