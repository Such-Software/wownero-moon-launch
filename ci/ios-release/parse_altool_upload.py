#!/usr/bin/env python3
"""Turn raw ``altool`` output into a fail-closed upload receipt."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys
from typing import Iterable

TOOL_VERSION = "1.0.1"
SUCCESS = re.compile(
    r"No errors uploading|UPLOAD SUCCEEDED|successfully uploaded|"
    r"uploaded successfully|package has been uploaded",
    re.IGNORECASE,
)
DELIVERY_UUID = re.compile(
    r"(?:delivery[ -]?uuid|request[ -]?uuid|requestuuid)"
    r"[^0-9a-f]*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
    r"[0-9a-f]{4}-[0-9a-f]{12})",
    re.IGNORECASE,
)
FAILURE = re.compile(r"\b(?:error|failed|failure|rejected|invalid)\b", re.IGNORECASE)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--ipa", required=True, type=pathlib.Path)
    parser.add_argument("--app", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--source-sha", default="")
    parser.add_argument("--source-ref", default="")
    parser.add_argument("--exit-code", type=int, required=True)
    return parser.parse_args(list(argv))


def main(argv: Iterable[str] = sys.argv[1:]) -> int:
    args = parse_args(argv)
    log = args.log.read_text(encoding="utf-8", errors="replace")
    positive = bool(SUCCESS.search(log))
    failure_lines = [
        line
        for line in log.splitlines()
        if FAILURE.search(line) and not SUCCESS.search(line) and "0 error" not in line.lower()
    ]
    match = DELIVERY_UUID.search(log)
    accepted = positive and not failure_lines
    receipt = {
        "schema_version": 1,
        "tool": {
            "name": "such-fleet-ios-release/parse_altool_upload",
            "version": TOOL_VERSION,
        },
        "recorded_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "accepted": accepted,
        "app": args.app,
        "bundle_id": args.bundle_id,
        "version": args.version,
        "build_number": args.build_number,
        "source_sha": args.source_sha,
        "source_ref": args.source_ref,
        "ipa_sha256": sha256_file(args.ipa),
        "raw_log_sha256": sha256_file(args.log),
        "altool_exit_code": args.exit_code,
        "positive_acceptance_marker": positive,
        "failure_marker_lines": failure_lines[:20],
        "delivery_uuid": match.group(1) if match else None,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if not accepted:
        print(
            "altool receipt: REJECTED "
            f"(exit={args.exit_code}, positive_marker={positive}, "
            f"failure_lines={len(failure_lines)})",
            file=sys.stderr,
        )
        return 1
    print(
        "altool receipt: ACCEPTED "
        f"(exit={args.exit_code}, delivery_uuid={receipt['delivery_uuid'] or 'not-reported'})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
