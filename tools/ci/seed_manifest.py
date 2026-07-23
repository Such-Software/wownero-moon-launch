#!/usr/bin/env python3
"""Verify the exact ignored iOS material staged on the private Mac runner."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_sha256(root: pathlib.Path) -> str:
    """sha256-tree-v1: hash each relative path and its content digest."""
    if not root.is_dir():
        raise ValueError(f"tree is missing or is not a directory: {root}")

    files = sorted(path for path in root.rglob("*") if path.is_file())
    if not files:
        raise ValueError(f"tree is empty: {root}")

    digest = hashlib.sha256()
    for path in files:
        relative = path.relative_to(root).as_posix()
        digest.update(b"file\0")
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(file_sha256(path).encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def load_entries(contract_path: pathlib.Path) -> list[dict[str, str]]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    seed = contract.get("seed")
    if not isinstance(seed, dict):
        raise ValueError("contract has no seed object")
    if seed.get("hash_algorithm") != "sha256-tree-v1":
        raise ValueError("contract must declare hash_algorithm=sha256-tree-v1")
    entries = seed.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("contract seed.entries must be a non-empty list")
    return entries


def safe_relative_path(raw: object) -> pathlib.PurePosixPath:
    if not isinstance(raw, str) or not raw:
        raise ValueError("seed entry path must be a non-empty string")
    path = pathlib.PurePosixPath(raw)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe seed entry path: {raw}")
    return path


def verify(contract_path: pathlib.Path, root: pathlib.Path, print_current: bool) -> int:
    failures = 0
    for entry in load_entries(contract_path):
        relative = safe_relative_path(entry.get("path"))
        kind = entry.get("kind")
        expected = entry.get("sha256")
        path = root.joinpath(*relative.parts)

        if kind == "file":
            if not path.is_file():
                print(f"FAIL missing file: {relative}", file=sys.stderr)
                failures += 1
                continue
            actual = file_sha256(path)
        elif kind == "tree":
            try:
                actual = tree_sha256(path)
            except ValueError as error:
                print(f"FAIL {error}", file=sys.stderr)
                failures += 1
                continue
        else:
            print(f"FAIL unsupported seed kind for {relative}: {kind}", file=sys.stderr)
            failures += 1
            continue

        if print_current:
            print(f"{relative}\t{actual}")
            continue

        if not isinstance(expected, str) or len(expected) != 64:
            print(f"FAIL invalid expected SHA-256 for {relative}", file=sys.stderr)
            failures += 1
        elif actual != expected:
            print(
                f"FAIL seed checksum mismatch for {relative}\n"
                f"  expected {expected}\n"
                f"  actual   {actual}",
                file=sys.stderr,
            )
            failures += 1
        else:
            print(f"PASS {relative} {actual}")

    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", default="ci/ios-app.json", type=pathlib.Path)
    parser.add_argument("--root", default=".", type=pathlib.Path)
    parser.add_argument(
        "--print-current",
        action="store_true",
        help="print current checksums instead of comparing them",
    )
    args = parser.parse_args()
    try:
        return 1 if verify(args.contract, args.root, args.print_current) else 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"FAIL seed manifest: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
