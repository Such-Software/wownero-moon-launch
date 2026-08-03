#!/usr/bin/env python3
"""Check Moon Launch's inert, app-owned web-commerce integration."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP_ID = "moon_launch"
MARKETING_HOST = "moonlaunch.space"
SHOP_HOST = "shop.moonlaunch.space"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    consumer = json.loads(read("config/app-platform-v1.json"))
    storefront = json.loads(read("config/storefront-content-v1.json"))

    expected_storefront = {
        "contract_version": 1,
        "app_id": APP_ID,
        "intended_storefront_host": SHOP_HOST,
        "marketing_host": MARKETING_HOST,
        "brand_lock_sha256": consumer["brand"]["projection_lock_sha256"],
    }
    if set(storefront) != {*expected_storefront, "theme"}:
        errors.append("storefront content has an unexpected top-level shape")
    for key, expected in expected_storefront.items():
        if storefront.get(key) != expected:
            errors.append(f"storefront content {key} is not canonical")
    if not isinstance(storefront.get("theme"), dict) or not storefront["theme"]:
        errors.append("storefront content needs a non-empty app-owned theme")
    if re.search(r"offer_id|product_id|tenant_id|channel_id|oidc_client", read(
        "config/storefront-content-v1.json"
    ), re.IGNORECASE):
        errors.append("storefront content must not invent provisioned identifiers")

    public_config = read("web/app-config.js")
    body = re.search(
        r"window\.SUCH_APP_CONFIG\s*=\s*\{(?P<body>.*?)\};",
        public_config,
        re.DOTALL,
    )
    entries = (
        dict(re.findall(r"^\s*([A-Za-z][A-Za-z0-9]*)\s*:\s*(null|false)\s*,?\s*$", body.group("body"), re.MULTILINE))
        if body
        else {}
    )
    if entries != {
        "oidcIssuer": "null",
        "oidcClientId": "null",
        "ledgerBase": "null",
        "checkoutUrl": "null",
        "checkoutEnabled": "false",
    }:
        errors.append("checked-in web public config must be exactly all-null/false")

    checkout = read("web/checkout.js")
    for required in (
        f'EXPECTED_SHOP_HOST = "{SHOP_HOST}"',
        'code_challenge_method: "S256"',
        'response_type: "code"',
        'returnedState !== expectedState',
        'LEDGER + "/me/entitlements"',
        'entitlements.premium === true',
        "window.SUCH_APP_startCheckout",
    ):
        if required not in checkout:
            errors.append(f"web checkout invariant is missing: {required}")
    for forbidden in (
        "bauhaus_echo",
        "bauhaus-echo",
        "echo.such",
        "client_secret",
        "localStorage",
        "BEGIN PRIVATE KEY",
        "sharedReadToken",
    ):
        if forbidden.lower() in checkout.lower():
            errors.append(f"web checkout contains forbidden material: {forbidden}")

    shell = read("web/custom_shell.html")
    config_position = shell.find('<script src="app-config.js"></script>')
    checkout_position = shell.find('<script src="checkout.js"></script>')
    engine_position = shell.find('<script src="$GODOT_URL"></script>')
    if not (0 <= config_position < checkout_position < engine_position):
        errors.append("web public config and checkout must load before the Godot engine")
    if (
        f'href="https://{MARKETING_HOST}/store"' not in shell
        or "window.SUCH_APP_startCheckout" not in shell
    ):
        errors.append("unconfigured checkout must retain the canonical Hangar fallback")

    exporter = read("tools/export_candidate.sh")
    for asset in ("app-config.js", "checkout.js"):
        expected = f'install -m 0644 web/{asset} "$PRODUCT_DIR/web/{asset}"'
        if expected not in exporter:
            errors.append(f"web candidate does not package {asset}")

    analytics = read("game/net/Analytics.gd")
    if 'const APP_ID := "moon_launch"' not in analytics:
        errors.append("analytics must emit the canonical app ID")
    ad_manager = read("game/net/AdManager.gd")
    if (
        "_web_has_neutral_premium" not in ad_manager
        or "window.SUCH_APP && window.SUCH_APP.premium === true" not in ad_manager
        or '"such-app-entitlements-changed"' not in ad_manager
        or "JavaScriptBridge.create_callback" not in ad_manager
        or "premium_status_changed.emit(premium)" not in ad_manager
    ):
        errors.append(
            "Godot web must react to only the neutral resolved Premium capability"
        )

    for error in errors:
        print("FAIL", error)
    print(
        f"moonlaunch_web_commerce: app={APP_ID} "
        f"source_activation=disabled errors={len(errors)}"
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
