#!/usr/bin/env python3
"""Fail-closed App Store Connect checks for the iOS delivery workflow.

This intentionally uses only Python's standard library and the system OpenSSL
binary available on the release Mac. It never prints the JWT or private key.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


API_ROOT = "https://api.appstoreconnect.apple.com"
TERMINAL_FAILURE_STATES = {"FAILED", "INVALID"}


class AppStoreConnectError(RuntimeError):
    """An App Store Connect request or invariant failed."""


def b64url(payload: bytes) -> str:
    return base64.urlsafe_b64encode(payload).rstrip(b"=").decode("ascii")


def read_der_length(payload: bytes, offset: int) -> tuple[int, int]:
    if offset >= len(payload):
        raise AppStoreConnectError("truncated ECDSA signature")
    first = payload[offset]
    offset += 1
    if first < 0x80:
        return first, offset
    octets = first & 0x7F
    if octets < 1 or octets > 2 or offset + octets > len(payload):
        raise AppStoreConnectError("unsupported ECDSA signature length")
    return int.from_bytes(payload[offset : offset + octets], "big"), offset + octets


def der_signature_to_raw(payload: bytes) -> bytes:
    """Convert OpenSSL's ASN.1 DER ECDSA signature to JWT's 64-byte R || S."""

    offset = 0
    if not payload or payload[offset] != 0x30:
        raise AppStoreConnectError("OpenSSL returned a non-sequence ECDSA signature")
    sequence_length, offset = read_der_length(payload, offset + 1)
    if offset + sequence_length != len(payload):
        raise AppStoreConnectError("invalid ECDSA signature sequence length")

    values: list[bytes] = []
    for _ in range(2):
        if offset >= len(payload) or payload[offset] != 0x02:
            raise AppStoreConnectError("invalid ECDSA signature integer")
        integer_length, offset = read_der_length(payload, offset + 1)
        value = payload[offset : offset + integer_length]
        offset += integer_length
        if len(value) != integer_length:
            raise AppStoreConnectError("truncated ECDSA signature integer")
        value = value.lstrip(b"\x00")
        if len(value) > 32:
            raise AppStoreConnectError("oversized ECDSA signature integer")
        values.append(value.rjust(32, b"\x00"))

    if offset != len(payload):
        raise AppStoreConnectError("trailing data in ECDSA signature")
    return b"".join(values)


def create_jwt(key_id: str, issuer_id: str, private_key: pathlib.Path) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {
        "iss": issuer_id,
        "iat": now - 5,
        "exp": now + 19 * 60,
        "aud": "appstoreconnect-v1",
    }
    encoded_header = b64url(
        json.dumps(header, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    encoded_claims = b64url(
        json.dumps(claims, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    signing_input = f"{encoded_header}.{encoded_claims}".encode("ascii")
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(private_key)],
        input=signing_input,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise AppStoreConnectError(f"OpenSSL could not sign App Store Connect JWT: {detail}")
    return f"{encoded_header}.{encoded_claims}.{b64url(der_signature_to_raw(result.stdout))}"


class Client:
    def __init__(self, key_id: str, issuer_id: str, private_key: pathlib.Path) -> None:
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = private_key

    def request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: dict[str, Any] | None = None,
        expected_status: int = 200,
    ) -> dict[str, Any] | None:
        url = f"{API_ROOT}{path}"
        if query:
            url = f"{url}?{urllib.parse.urlencode(query)}"
        encoded_body = None
        headers = {
            "Authorization": f"Bearer {create_jwt(self.key_id, self.issuer_id, self.private_key)}",
            "Accept": "application/json",
        }
        if body is not None:
            encoded_body = json.dumps(body, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            url, data=encoded_body, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                status = response.status
                payload = response.read()
        except urllib.error.HTTPError as error:
            payload = error.read().decode("utf-8", errors="replace")
            try:
                parsed = json.loads(payload)
                messages = [
                    str(item.get("detail") or item.get("title") or item.get("code"))
                    for item in parsed.get("errors", [])
                ]
                detail = "; ".join(messages) or f"HTTP {error.code}"
            except (json.JSONDecodeError, AttributeError):
                detail = f"HTTP {error.code}"
            raise AppStoreConnectError(
                f"{method} {path} was rejected by App Store Connect: {detail}"
            ) from error
        except urllib.error.URLError as error:
            raise AppStoreConnectError(
                f"{method} {path} could not reach App Store Connect: {error.reason}"
            ) from error

        if status != expected_status:
            raise AppStoreConnectError(
                f"{method} {path}: expected HTTP {expected_status}, got {status}"
            )
        if not payload:
            return None
        try:
            decoded = json.loads(payload)
        except json.JSONDecodeError as error:
            raise AppStoreConnectError(
                f"{method} {path} returned invalid JSON"
            ) from error
        if not isinstance(decoded, dict):
            raise AppStoreConnectError(f"{method} {path} returned a non-object response")
        return decoded


def one_resource(payload: dict[str, Any], label: str) -> dict[str, Any]:
    resources = payload.get("data")
    if not isinstance(resources, list) or len(resources) != 1:
        count = len(resources) if isinstance(resources, list) else "invalid"
        raise AppStoreConnectError(f"expected exactly one {label}; got {count}")
    resource = resources[0]
    if not isinstance(resource, dict) or not resource.get("id"):
        raise AppStoreConnectError(f"{label} response is missing its resource ID")
    return resource


def resolve_app(client: Client, bundle_id: str) -> dict[str, Any]:
    payload = client.request(
        "GET",
        "/v1/apps",
        query={"filter[bundleId]": bundle_id, "limit": "2"},
    )
    assert payload is not None
    resource = one_resource(payload, f"app with bundle ID {bundle_id}")
    actual_bundle = (resource.get("attributes") or {}).get("bundleId")
    if actual_bundle != bundle_id:
        raise AppStoreConnectError(
            f"resolved app has bundle ID {actual_bundle!r}, expected {bundle_id!r}"
        )
    return resource


def list_builds(
    client: Client,
    app_id: str,
    build_number: str,
    marketing_version: str,
) -> list[dict[str, Any]]:
    payload = client.request(
        "GET",
        "/v1/builds",
        query={
            "filter[app]": app_id,
            "filter[version]": build_number,
            "filter[preReleaseVersion.version]": marketing_version,
            "filter[preReleaseVersion.platform]": "IOS",
            "limit": "2",
        },
    )
    assert payload is not None
    resources = payload.get("data")
    if not isinstance(resources, list):
        raise AppStoreConnectError("build listing returned invalid data")
    return [resource for resource in resources if isinstance(resource, dict)]


def check_unused(
    client: Client,
    bundle_id: str,
    build_number: str,
    marketing_version: str,
) -> None:
    app = resolve_app(client, bundle_id)
    builds = list_builds(client, app["id"], build_number, marketing_version)
    if builds:
        states = ", ".join(
            str((build.get("attributes") or {}).get("processingState", "UNKNOWN"))
            for build in builds
        )
        raise AppStoreConnectError(
            f"{bundle_id} {marketing_version} ({build_number}) already exists "
            f"in App Store Connect ({states})"
        )
    print(
        f"PASS App Store Connect build number is unused: "
        f"{bundle_id} {marketing_version} ({build_number})"
    )


def validate_internal_group(
    client: Client, group_id: str, expected_app_id: str
) -> dict[str, Any]:
    payload = client.request(
        "GET",
        f"/v1/betaGroups/{urllib.parse.quote(group_id, safe='')}",
        query={"include": "app"},
    )
    assert payload is not None
    group = payload.get("data")
    if not isinstance(group, dict) or group.get("id") != group_id:
        raise AppStoreConnectError("beta group lookup returned the wrong resource")
    attributes = group.get("attributes") or {}
    if attributes.get("isInternalGroup") is not True:
        raise AppStoreConnectError(
            f"beta group {attributes.get('name', group_id)!r} is not an internal group"
        )
    relationships = group.get("relationships") or {}
    app_data = ((relationships.get("app") or {}).get("data") or {})
    if app_data.get("id") != expected_app_id:
        raise AppStoreConnectError("beta group belongs to a different app")
    return group


def wait_for_valid_build(
    client: Client,
    bundle_id: str,
    build_number: str,
    marketing_version: str,
    timeout_seconds: int,
    interval_seconds: int,
) -> tuple[dict[str, Any], dict[str, Any]]:
    app = resolve_app(client, bundle_id)
    deadline = time.monotonic() + timeout_seconds
    last_state = "NOT_VISIBLE"
    while time.monotonic() < deadline:
        builds = list_builds(client, app["id"], build_number, marketing_version)
        if len(builds) > 1:
            raise AppStoreConnectError(
                f"multiple App Store Connect builds matched {marketing_version} ({build_number})"
            )
        if builds:
            build = builds[0]
            attributes = build.get("attributes") or {}
            state = str(attributes.get("processingState", "UNKNOWN"))
            if state != last_state:
                print(f"App Store Connect processing state: {state}", flush=True)
                last_state = state
            if state in TERMINAL_FAILURE_STATES:
                raise AppStoreConnectError(
                    f"Apple processing ended in terminal state {state}"
                )
            if state == "VALID":
                if attributes.get("usesNonExemptEncryption") is not False:
                    raise AppStoreConnectError(
                        "processed build does not declare usesNonExemptEncryption=false"
                    )
                return app, build
        elif last_state != "NOT_VISIBLE":
            last_state = "NOT_VISIBLE"
            print("App Store Connect build is not visible yet", flush=True)
        time.sleep(interval_seconds)
    raise AppStoreConnectError(
        f"timed out after {timeout_seconds}s waiting for "
        f"{marketing_version} ({build_number}) to become VALID"
    )


def distribute_to_group(
    client: Client,
    group_id: str,
    app_id: str,
    build_id: str,
) -> dict[str, Any]:
    group = validate_internal_group(client, group_id, app_id)
    attributes = group.get("attributes") or {}
    if attributes.get("hasAccessToAllBuilds") is True:
        print(
            f"Internal group {attributes.get('name', group_id)!r} "
            "already grants access to all builds",
            flush=True,
        )
        return group

    relationship_path = (
        f"/v1/betaGroups/{urllib.parse.quote(group_id, safe='')}"
        "/relationships/builds"
    )
    relationship = client.request("GET", relationship_path)
    assert relationship is not None
    resources = relationship.get("data")
    if not isinstance(resources, list):
        raise AppStoreConnectError("beta group build relationship returned invalid data")
    related_build_ids: set[str] = set()
    for resource in resources:
        if (
            not isinstance(resource, dict)
            or resource.get("type") != "builds"
            or not isinstance(resource.get("id"), str)
        ):
            raise AppStoreConnectError(
                "beta group build relationship contains an invalid resource"
            )
        related_build_ids.add(resource["id"])
    if build_id in related_build_ids:
        print(
            f"Build is already assigned to internal group "
            f"{attributes.get('name', group_id)!r}",
            flush=True,
        )
        return group

    client.request(
        "POST",
        relationship_path,
        body={"data": [{"type": "builds", "id": build_id}]},
        expected_status=204,
    )
    return group


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_receipt(
    output: pathlib.Path,
    *,
    app: dict[str, Any],
    build: dict[str, Any],
    group: dict[str, Any],
    bundle_id: str,
    marketing_version: str,
    build_number: str,
    ipa: pathlib.Path,
    delivery_uuid: str,
) -> None:
    attributes = build.get("attributes") or {}
    group_attributes = group.get("attributes") or {}
    receipt = {
        "schema_version": 1,
        "app_id": app["id"],
        "build_id": build["id"],
        "bundle_id": bundle_id,
        "marketing_version": marketing_version,
        "build_number": build_number,
        "processing_state": attributes.get("processingState"),
        "uses_non_exempt_encryption": attributes.get("usesNonExemptEncryption"),
        "uploaded_date": attributes.get("uploadedDate"),
        "delivery_uuid": delivery_uuid,
        "internal_group_id": group["id"],
        "internal_group_name": group_attributes.get("name"),
        "internal_group_has_access_to_all_builds": group_attributes.get(
            "hasAccessToAllBuilds"
        ),
        "distributed": True,
        "ipa_sha256": sha256(ipa),
        "source_sha": os.environ.get("GITHUB_SHA", ""),
        "source_ref": os.environ.get("GITHUB_REF", ""),
        "verified_utc": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def positive_integer(value: str) -> str:
    if not value.isdigit() or value.startswith("0") or len(value) > 18:
        raise argparse.ArgumentTypeError("must be a positive integer of at most 18 digits")
    return value


def common_parser(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--private-key", required=True, type=pathlib.Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--marketing-version", required=True)
    parser.add_argument("--build-number", required=True, type=positive_integer)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    unused = subparsers.add_parser(
        "check-unused", help="fail if this app/version/build already exists"
    )
    common_parser(unused)

    wait = subparsers.add_parser(
        "wait-and-distribute",
        help="wait for VALID processing and assign the build to an internal group",
    )
    common_parser(wait)
    wait.add_argument("--group-id", required=True)
    wait.add_argument("--ipa", required=True, type=pathlib.Path)
    wait.add_argument("--delivery-uuid", default="")
    wait.add_argument("--output", required=True, type=pathlib.Path)
    wait.add_argument("--timeout-seconds", type=int, default=2400)
    wait.add_argument("--interval-seconds", type=int, default=30)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.private_key.is_file():
        print("FATAL: App Store Connect private key is missing", file=sys.stderr)
        return 1
    client = Client(args.key_id, args.issuer_id, args.private_key)
    try:
        if args.command == "check-unused":
            check_unused(
                client,
                args.bundle_id,
                args.build_number,
                args.marketing_version,
            )
            return 0

        if args.timeout_seconds < 1 or args.interval_seconds < 1:
            raise AppStoreConnectError("poll timeout and interval must be positive")
        if not args.ipa.is_file() or args.ipa.stat().st_size < 1:
            raise AppStoreConnectError("IPA is missing or empty")
        app, build = wait_for_valid_build(
            client,
            args.bundle_id,
            args.build_number,
            args.marketing_version,
            args.timeout_seconds,
            args.interval_seconds,
        )
        group = distribute_to_group(client, args.group_id, app["id"], build["id"])
        write_receipt(
            args.output,
            app=app,
            build=build,
            group=group,
            bundle_id=args.bundle_id,
            marketing_version=args.marketing_version,
            build_number=args.build_number,
            ipa=args.ipa,
            delivery_uuid=args.delivery_uuid,
        )
        print(
            f"PASS TestFlight distribution: {args.marketing_version} "
            f"({args.build_number}) is VALID and assigned to "
            f"{(group.get('attributes') or {}).get('name', args.group_id)!r}"
        )
        return 0
    except (AppStoreConnectError, OSError, subprocess.SubprocessError) as error:
        print(f"FATAL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
