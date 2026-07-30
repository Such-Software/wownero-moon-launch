#!/usr/bin/env python3
"""Static fail-closed checks for the Moon Launch Nakama runtime inputs."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
NAKAMA = ROOT / "server" / "nakama"
CONTRACT_COMMIT = "4c202f2a27685b4d3658c0fe78efa0eee7e3168a"
REQUIRED_RPCS = {
    "app_platform_health",
    "app_platform_readiness",
    "app_platform_build_info",
    "app_platform_entitlements",
    "app_platform_prepare_guest_claim",
    "app_platform_claim_guest",
    "app_entitlement_projection",
    "moon_launch_room_register",
    "moon_launch_room_resolve",
    "moon_launch_room_close",
}
REQUIRED_TABLES = {
    "such_platform_identity",
    "such_platform_entitlement",
    "such_platform_guest_claim_token",
    "such_platform_guest_claim",
    "such_platform_migration_operation",
    "such_moon_launch_friendly_room",
}


def fail(message: str) -> None:
    print(f"FATAL: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {path.relative_to(ROOT)}: {exc}")
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def main() -> None:
    package = read_json(NAKAMA / "package.json")
    lock = read_json(NAKAMA / "package-lock.json")
    tsconfig = read_json(NAKAMA / "tsconfig.json")
    manifest = read_json(NAKAMA / "runtime-manifest.template.json")

    dependencies = package.get("devDependencies")
    if dependencies != {
        "nakama-runtime":
            "https://github.com/heroiclabs/nakama-common/archive/refs/tags/"
            "v1.47.0.tar.gz",
        "typescript": "5.9.3",
    }:
        fail("runtime development dependencies must remain exactly pinned")

    locked = lock.get("packages", {})
    runtime_lock = locked.get("node_modules/nakama-runtime", {})
    compiler_lock = locked.get("node_modules/typescript", {})
    if runtime_lock.get("version") != "1.47.0" or not runtime_lock.get(
        "integrity"
    ):
        fail("lockfile does not pin Nakama runtime types 1.47.0 with integrity")
    if compiler_lock.get("version") != "5.9.3" or not compiler_lock.get(
        "integrity"
    ):
        fail("lockfile does not pin TypeScript 5.9.3 with integrity")

    options = tsconfig.get("compilerOptions", {})
    if options.get("target") != "ES5" or options.get("module") != "none":
        fail("Nakama runtime must compile as module-free ES5")
    if options.get("outFile") != "dist/index.js":
        fail("unexpected checked-in runtime output path")

    if manifest.get("app_id") != "moon_launch":
        fail("runtime manifest app ID drift")
    if manifest.get("contract_source_commit") != CONTRACT_COMMIT:
        fail("runtime manifest contract pin drift")
    if manifest.get("minimum_nakama_version") != "3.40.0":
        fail("runtime manifest Nakama floor drift")
    if (
        manifest.get("schema_version") != 2
        or manifest.get("migrations", {}).get("schema_version") != 2
    ):
        fail("runtime manifest schema version drift")
    if manifest.get("runtime", {}).get("sha256") is not None:
        fail("runtime digest must be injected during the Build render")
    if manifest.get("migrations", {}).get("sha256") is not None:
        fail("migration digest must be injected independently")

    source_paths = sorted((NAKAMA / "src").glob("*.ts"))
    if not source_paths:
        fail("runtime source is missing")
    source = "\n".join(path.read_text(encoding="utf-8") for path in source_paths)
    for rpc in REQUIRED_RPCS:
        if f'"{rpc}"' not in source:
            fail(f"runtime does not register {rpc}")
    if "registerBeforeAuthenticateCustom" not in source:
        fail("custom authentication hook is missing")
    if not re.search(r"\bfunction\s+InitModule\s*\(", source):
        fail("InitModule must be a global function declaration")

    required_runtime_environment = {
        "SUCH_PLATFORM_APP_ID",
        "SUCH_PLATFORM_SCHEMA_VERSION",
        "SUCH_PLATFORM_CONTRACT_VERSION",
        "SUCH_PLATFORM_CONTRACT_COMMIT",
        "SUCH_PLATFORM_SOURCE_COMMIT",
        "SUCH_PLATFORM_RUNTIME_SHA256",
        "SUCH_PLATFORM_MIGRATION_SHA256",
        "SUCH_IDP_CONSUME_URL",
        "SUCH_IDP_CONSUMER_TOKEN",
        "SUCH_ENTITLEMENT_PROVIDER_URL",
        "SUCH_ENTITLEMENT_PROVIDER_TOKEN",
        "SUCH_ENTITLEMENT_PROJECTION_HMAC_KEY",
        "SUCH_ROOM_SEED_HMAC_KEY",
        "SUCH_IAP_APPLE_PRODUCT_IDS",
        "SUCH_IAP_GOOGLE_PRODUCT_IDS",
    }
    for key in required_runtime_environment:
        if not re.search(
            rf"(?<![A-Z0-9_]){re.escape(key)}(?![A-Z0-9_])",
            source,
        ):
            fail(f"runtime does not consume Fleet environment role {key}")
    for legacy_key in (
        "APP_RUNTIME_SOURCE_COMMIT",
        "APP_PLATFORM_CONTRACT_SOURCE_COMMIT",
        "IDP_CONSUMER_TOKEN",
        "ENTITLEMENT_SIGNING_KEY",
    ):
        if re.search(
            rf"(?<![A-Z0-9_]){re.escape(legacy_key)}(?![A-Z0-9_])",
            source,
        ):
            fail(f"runtime still consumes legacy environment role {legacy_key}")

    forbidden_runtime = {
        r"\brequire\s*\(": "Node require",
        r"\bprocess\.": "Node process",
        r"\bBuffer\b": "Node Buffer",
        r"\bfetch\s*\(": "browser fetch",
        r"\bXMLHttpRequest\b": "browser XMLHttpRequest",
        r"\bWebSocket\b": "browser WebSocket",
        r"\bconsole\.": "console output",
        r"\beval\s*\(": "dynamic evaluation",
    }
    for pattern, label in forbidden_runtime.items():
        if re.search(pattern, source):
            fail(f"runtime source uses forbidden {label}")

    migrations = sorted((NAKAMA / "migrations").glob("*.sql"))
    if not migrations:
        fail("runtime migrations are missing")
    migration_source = "\n".join(
        path.read_text(encoding="utf-8") for path in migrations
    )
    for table in REQUIRED_TABLES:
        if f"CREATE TABLE IF NOT EXISTS {table}" not in migration_source:
            fail(f"migration does not add {table}")
    for required in (
        r"\set ON_ERROR_STOP on",
        "BEGIN;",
        "COMMIT;",
        "such_platform_apply_entitlement_event",
        "such_moon_launch_claim_guest",
        "ON CONFLICT (schema_version) DO NOTHING",
    ):
        if required not in migration_source:
            fail(f"migration invariant missing: {required}")
    if re.search(
        r"\b(?:DROP\s+TABLE|TRUNCATE|DELETE\s+FROM)\b",
        migration_source,
        re.IGNORECASE,
    ):
        fail("migration bundle contains a destructive statement")

    tests = sorted((NAKAMA / "test").glob("*.test.js"))
    if not tests:
        fail("runtime parser/replay/migration tests are missing")

    print("PASS Nakama runtime static contract")


if __name__ == "__main__":
    main()
