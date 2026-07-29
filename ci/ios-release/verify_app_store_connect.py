#!/usr/bin/env python3
"""Verify Apple's asynchronous processing result for an uploaded build.

The verifier rejects missing export compliance and can optionally attach a
ready build to one explicitly named *internal* TestFlight group. It never
changes ``autoNotifyEnabled`` and refuses external groups unless the caller
also passes ``--allow-external-group``.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Iterable

TOOL_VERSION = "1.0.1"
API_ROOT = "https://api.appstoreconnect.apple.com"
READY_INTERNAL_STATES = {"READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}
PENDING_INTERNAL_STATES = {"PROCESSING", "IN_EXPORT_COMPLIANCE_REVIEW"}
FATAL_INTERNAL_STATES = {
    "PROCESSING_EXCEPTION",
    "MISSING_EXPORT_COMPLIANCE",
    "EXPIRED",
}


class VerificationError(RuntimeError):
    """A configuration, API, or delivery-contract failure."""


def b64url(payload: bytes) -> str:
    return base64.urlsafe_b64encode(payload).rstrip(b"=").decode("ascii")


def der_length(payload: bytes, offset: int) -> tuple[int, int]:
    if offset >= len(payload):
        raise VerificationError("truncated DER signature")
    first = payload[offset]
    if first < 0x80:
        return first, offset + 1
    count = first & 0x7F
    if count == 0 or count > 4 or offset + 1 + count > len(payload):
        raise VerificationError("invalid DER signature length")
    value = int.from_bytes(payload[offset + 1 : offset + 1 + count], "big")
    return value, offset + 1 + count


def der_es256_to_raw(signature: bytes) -> bytes:
    if not signature or signature[0] != 0x30:
        raise VerificationError("OpenSSL did not return an ECDSA DER sequence")
    sequence_length, cursor = der_length(signature, 1)
    if cursor + sequence_length != len(signature):
        raise VerificationError("invalid ECDSA DER sequence length")
    values: list[bytes] = []
    for _ in range(2):
        if cursor >= len(signature) or signature[cursor] != 0x02:
            raise VerificationError("invalid ECDSA DER integer")
        integer_length, cursor = der_length(signature, cursor + 1)
        integer = signature[cursor : cursor + integer_length]
        cursor += integer_length
        integer = integer.lstrip(b"\x00")
        if len(integer) > 32:
            raise VerificationError("ECDSA integer exceeds P-256 width")
        values.append(integer.rjust(32, b"\x00"))
    if cursor != len(signature):
        raise VerificationError("unexpected trailing ECDSA DER data")
    return values[0] + values[1]


def make_jwt(key_id: str, issuer_id: str, key_path: pathlib.Path) -> str:
    now = int(time.time())
    header = b64url(
        json.dumps(
            {"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")
        ).encode()
    )
    claims = b64url(
        json.dumps(
            {
                "iss": issuer_id,
                "iat": now - 20,
                "exp": now + 19 * 60,
                "aud": "appstoreconnect-v1",
            },
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{claims}".encode("ascii")
    try:
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
            input=signing_input,
            check=False,
            capture_output=True,
        )
    except FileNotFoundError as error:
        raise VerificationError("openssl is required to sign the App Store JWT") from error
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise VerificationError(f"openssl could not sign App Store JWT: {detail}")
    return f"{header}.{claims}.{b64url(der_es256_to_raw(result.stdout))}"


class AppStoreClient:
    def __init__(self, key_id: str, issuer_id: str, key_path: pathlib.Path) -> None:
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_path = key_path
        self.token = make_jwt(key_id, issuer_id, key_path)
        self.token_created = time.monotonic()

    def refresh_token_if_needed(self) -> None:
        if time.monotonic() - self.token_created > 15 * 60:
            self.token = make_jwt(self.key_id, self.issuer_id, self.key_path)
            self.token_created = time.monotonic()

    def request(
        self,
        method: str,
        path: str,
        query: dict[str, Any] | None = None,
        body: dict[str, Any] | None = None,
    ) -> tuple[int, dict[str, Any] | None]:
        self.refresh_token_if_needed()
        url = API_ROOT + path
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        encoded = None
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/json",
        }
        if body is not None:
            encoded = json.dumps(body, separators=(",", ":")).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=encoded, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                payload = response.read()
                return response.status, json.loads(payload) if payload else None
        except urllib.error.HTTPError as error:
            payload = error.read().decode("utf-8", errors="replace")
            try:
                detail = json.loads(payload)
                messages = [
                    item.get("detail") or item.get("title") or str(item)
                    for item in detail.get("errors", [])
                ]
                rendered = "; ".join(messages) or payload
            except json.JSONDecodeError:
                rendered = payload
            raise VerificationError(
                f"App Store Connect {method} {path} returned HTTP {error.code}: {rendered}"
            ) from error
        except urllib.error.URLError as error:
            raise VerificationError(f"App Store Connect request failed: {error}") from error


def resources(payload: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not payload or not isinstance(payload.get("data"), list):
        return []
    return payload["data"]


def load_contract(path: pathlib.Path) -> dict[str, Any]:
    try:
        contract = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise VerificationError(f"cannot read iOS app contract: {error}") from error
    if contract.get("schema_version") != 1:
        raise VerificationError("unsupported iOS app contract schema_version")
    for field in ("app_name", "bundle_id", "uses_non_exempt_encryption"):
        if field not in contract:
            raise VerificationError(f"iOS app contract omits {field}")
    return contract


def one_exact(items: list[dict[str, Any]], label: str) -> dict[str, Any]:
    if len(items) != 1:
        raise VerificationError(f"expected one {label}; App Store Connect returned {len(items)}")
    return items[0]


def find_app(client: AppStoreClient, bundle_id: str) -> dict[str, Any]:
    _, payload = client.request(
        "GET",
        "/v1/apps",
        {"filter[bundleId]": bundle_id, "fields[apps]": "name,bundleId"},
    )
    exact = [
        item
        for item in resources(payload)
        if item.get("attributes", {}).get("bundleId") == bundle_id
    ]
    return one_exact(exact, f"app with bundle ID {bundle_id!r}")


def find_build(
    client: AppStoreClient,
    app_id: str,
    build_number: str,
    marketing_version: str | None,
) -> dict[str, Any] | None:
    query: dict[str, Any] = {
        "filter[app]": app_id,
        "filter[version]": build_number,
        "fields[builds]": (
            "version,uploadedDate,expirationDate,expired,minOsVersion,"
            "processingState,usesNonExemptEncryption,buildAudienceType,"
            "preReleaseVersion"
        ),
        "include": "preReleaseVersion",
        "fields[preReleaseVersions]": "version,platform",
        "limit": 20,
    }
    if marketing_version:
        query["filter[preReleaseVersion.version]"] = marketing_version
    _, payload = client.request("GET", "/v1/builds", query)
    candidates = [
        item
        for item in resources(payload)
        if str(item.get("attributes", {}).get("version", "")) == build_number
    ]
    if not candidates:
        return None
    if len(candidates) > 1:
        raise VerificationError(
            "multiple builds matched; pass --marketing-version to disambiguate"
        )
    return candidates[0]


def get_beta_detail(client: AppStoreClient, build_id: str) -> dict[str, Any]:
    _, payload = client.request(
        "GET",
        f"/v1/builds/{build_id}/buildBetaDetail",
        {"fields[buildBetaDetails]": "autoNotifyEnabled,internalBuildState,externalBuildState"},
    )
    if not payload or not isinstance(payload.get("data"), dict):
        raise VerificationError("build beta detail response omitted data")
    return payload["data"]


def group_for_name(
    client: AppStoreClient, app_id: str, group_name: str
) -> dict[str, Any]:
    _, payload = client.request(
        "GET",
        f"/v1/apps/{app_id}/betaGroups",
        {
            "fields[betaGroups]": "name,isInternalGroup,hasAccessToAllBuilds",
            "limit": 200,
        },
    )
    exact = [
        item
        for item in resources(payload)
        if item.get("attributes", {}).get("name") == group_name
    ]
    return one_exact(exact, f"beta group named {group_name!r}")


def ensure_group_build(
    client: AppStoreClient,
    group: dict[str, Any],
    build_id: str,
) -> str:
    group_id = group["id"]
    attributes = group.get("attributes", {})
    if attributes.get("hasAccessToAllBuilds") is True:
        return "group-has-access-to-all-builds"
    _, payload = client.request(
        "GET",
        f"/v1/betaGroups/{group_id}/relationships/builds",
        {"limit": 200},
    )
    if any(item.get("id") == build_id for item in resources(payload)):
        return "already-assigned"
    client.request(
        "POST",
        f"/v1/betaGroups/{group_id}/relationships/builds",
        body={"data": [{"type": "builds", "id": build_id}]},
    )
    return "assigned"


def write_receipt(path: pathlib.Path, receipt: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True, type=pathlib.Path)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--marketing-version")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--key-id", default=os.environ.get("APPLE_KEY_ID"))
    parser.add_argument("--issuer-id", default=os.environ.get("APPLE_ISSUER_ID"))
    parser.add_argument(
        "--private-key",
        type=pathlib.Path,
        default=(
            pathlib.Path(os.environ["APPLE_API_KEY_PATH"])
            if os.environ.get("APPLE_API_KEY_PATH")
            else None
        ),
    )
    parser.add_argument("--poll-seconds", type=int, default=30)
    parser.add_argument("--timeout-seconds", type=int, default=1800)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--beta-group")
    parser.add_argument("--allow-external-group", action="store_true")
    return parser.parse_args(list(argv))


def main(argv: Iterable[str] = sys.argv[1:]) -> int:
    args = parse_args(argv)
    receipt: dict[str, Any] = {
        "schema_version": 1,
        "tool": {
            "name": "such-fleet-ios-release/verify_app_store_connect",
            "version": TOOL_VERSION,
        },
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "result": "ERROR",
        "build_number": args.build_number,
        "marketing_version": args.marketing_version,
        "observations": [],
    }
    try:
        if not args.key_id or not args.issuer_id or not args.private_key:
            raise VerificationError(
                "APPLE_KEY_ID, APPLE_ISSUER_ID, and APPLE_API_KEY_PATH are required"
            )
        if not args.private_key.is_file():
            raise VerificationError(f"private key does not exist: {args.private_key}")
        if args.poll_seconds < 1 or args.poll_seconds > 300:
            raise VerificationError("poll-seconds must be between 1 and 300")
        if args.timeout_seconds < 0 or args.timeout_seconds > 7200:
            raise VerificationError("timeout-seconds must be between 0 and 7200")
        contract = load_contract(args.contract)
        receipt.update(
            {
                "app": contract["app_name"],
                "bundle_id": contract["bundle_id"],
                "expected_uses_non_exempt_encryption": contract[
                    "uses_non_exempt_encryption"
                ],
            }
        )
        client = AppStoreClient(args.key_id, args.issuer_id, args.private_key)
        app = find_app(client, contract["bundle_id"])
        receipt["app_store_connect_app_id"] = app["id"]
        deadline = time.monotonic() + args.timeout_seconds
        while True:
            build = find_build(
                client, app["id"], args.build_number, args.marketing_version
            )
            if build is None:
                observation = {
                    "at": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "processing_state": "NOT_YET_VISIBLE",
                }
                receipt["observations"].append(observation)
                pending_reason = "build is not yet visible in App Store Connect"
            else:
                attributes = build.get("attributes", {})
                processing = attributes.get("processingState")
                observation = {
                    "at": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "build_id": build["id"],
                    "processing_state": processing,
                    "uses_non_exempt_encryption": attributes.get(
                        "usesNonExemptEncryption"
                    ),
                }
                receipt["observations"].append(observation)
                receipt["app_store_connect_build_id"] = build["id"]
                if processing in {"FAILED", "INVALID"}:
                    raise VerificationError(f"Apple build processing ended in {processing}")
                if processing == "VALID":
                    expected_encryption = contract["uses_non_exempt_encryption"]
                    actual_encryption = attributes.get("usesNonExemptEncryption")
                    if actual_encryption is not expected_encryption:
                        raise VerificationError(
                            "processed build encryption flag does not match contract: "
                            f"expected {expected_encryption!r}, got {actual_encryption!r}"
                        )
                    detail = get_beta_detail(client, build["id"])
                    detail_attributes = detail.get("attributes", {})
                    internal_state = detail_attributes.get("internalBuildState")
                    observation["internal_build_state"] = internal_state
                    observation["external_build_state"] = detail_attributes.get(
                        "externalBuildState"
                    )
                    observation["auto_notify_enabled"] = detail_attributes.get(
                        "autoNotifyEnabled"
                    )
                    receipt["internal_build_state"] = internal_state
                    if internal_state in FATAL_INTERNAL_STATES:
                        raise VerificationError(
                            f"TestFlight internal build state is {internal_state}"
                        )
                    if internal_state in READY_INTERNAL_STATES:
                        if args.beta_group:
                            group = group_for_name(
                                client, app["id"], args.beta_group
                            )
                            is_internal = group.get("attributes", {}).get(
                                "isInternalGroup"
                            )
                            if is_internal is not True and not args.allow_external_group:
                                raise VerificationError(
                                    f"beta group {args.beta_group!r} is external; "
                                    "refusing assignment without --allow-external-group"
                                )
                            assignment = ensure_group_build(client, group, build["id"])
                            receipt["beta_group"] = {
                                "id": group["id"],
                                "name": args.beta_group,
                                "is_internal": is_internal,
                                "assignment": assignment,
                            }
                        receipt["result"] = "READY"
                        write_receipt(args.output, receipt)
                        print(
                            "App Store Connect verification: READY "
                            f"{contract['bundle_id']} {args.marketing_version or '?'} "
                            f"({args.build_number}) internal={internal_state}"
                        )
                        return 0
                    if internal_state not in PENDING_INTERNAL_STATES:
                        raise VerificationError(
                            f"unrecognized TestFlight internal build state: {internal_state!r}"
                        )
                    pending_reason = f"TestFlight internal build state is {internal_state}"
                else:
                    pending_reason = f"Apple processing state is {processing}"

            if args.once or time.monotonic() >= deadline:
                receipt["result"] = "PENDING"
                receipt["pending_reason"] = pending_reason
                write_receipt(args.output, receipt)
                print(
                    f"App Store Connect verification: PENDING: {pending_reason}",
                    file=sys.stderr,
                )
                return 2
            time.sleep(args.poll_seconds)
    except (VerificationError, OSError, ValueError) as error:
        receipt["result"] = "ERROR"
        receipt["error"] = str(error)
        write_receipt(args.output, receipt)
        print(f"App Store Connect verification: ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
