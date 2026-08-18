#!/usr/bin/env python3
"""Write the App Platform client configuration into project.godot before export.

PlatformSession.config_value reads ProjectSettings("such/app_platform/<name>")
and falls back to the process environment. On a phone there is no environment to
fall back to, so a build that never wrote these settings ships a client that
fails closed and cannot reach its own runtime. Nothing wrote them until now:
neither project.godot, nor tools/, nor either workflow directory mentioned them.

This runs inside the build workspace against a copy of the project, so the
checked-in project.godot is never modified and a developer's tree cannot be left
holding a server key.

Values arrive from the environment rather than the command line, because one of
them is the Nakama client server key. It is embedded in every shipped build and
is still a credential in transit: a process argument is world-readable on the
host and lands in shell history, while an environment variable passed by the
runner is neither.

Nothing here prints a value, on success or failure.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys


# The exact settings PlatformSession reads, and nothing else. An unknown name
# here would write a setting no code consults, which reads as configured while
# doing nothing.
REQUIRED = (
    "SUCH_APP_IDP_TICKET_URL",
    "SUCH_APP_NAKAMA_ENDPOINT",
    "SUCH_APP_NAKAMA_SERVER_KEY",
)

SECTION = "such"
KEY_PREFIX = "app_platform/"

# Mirrors ENDPOINT_PATTERN in PlatformSession.gd: scheme://host[:port], nothing
# else. Kept in step deliberately; a value this script accepts and the client
# rejects would fail at runtime on a device instead of here.
ENDPOINT = re.compile(r"^(https?)://([A-Za-z0-9][A-Za-z0-9.-]{0,253})(:([0-9]{1,5}))?$")
TICKET_URL = re.compile(r"^https://[A-Za-z0-9][A-Za-z0-9.-]{0,253}(:[0-9]{1,5})?/[A-Za-z0-9/_-]*$")
SERVER_KEY = re.compile(r"^[A-Za-z0-9_-]{24,}$")


def read_values(release: bool) -> dict[str, str]:
    values: dict[str, str] = {}
    missing: list[str] = []
    for name in REQUIRED:
        value = os.environ.get(name, "").strip()
        if not value:
            missing.append(name)
            continue
        values[name] = value
    if missing:
        raise SystemExit(
            "FATAL: missing platform configuration: " + ", ".join(sorted(missing))
        )

    endpoint = values["SUCH_APP_NAKAMA_ENDPOINT"]
    if not ENDPOINT.match(endpoint):
        raise SystemExit("FATAL: SUCH_APP_NAKAMA_ENDPOINT is not scheme://host[:port]")
    if release and not endpoint.startswith("https://"):
        raise SystemExit("FATAL: a release build requires an https Nakama endpoint")
    if not TICKET_URL.match(values["SUCH_APP_IDP_TICKET_URL"]):
        raise SystemExit("FATAL: SUCH_APP_IDP_TICKET_URL is not an https URL with a path")
    if not SERVER_KEY.match(values["SUCH_APP_NAKAMA_SERVER_KEY"]):
        # Shape only. The value is never echoed.
        raise SystemExit("FATAL: SUCH_APP_NAKAMA_SERVER_KEY does not match the expected shape")
    return values


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def inject(project: Path, values: dict[str, str]) -> None:
    text = project.read_text(encoding="utf-8")
    if f"\n[{SECTION}]\n" in text:
        raise SystemExit(
            f"FATAL: project.godot already has a [{SECTION}] section; refusing to "
            "merge into settings this script does not own"
        )
    # Blank line after the header, matching how Godot writes its own sections.
    lines = [f"\n[{SECTION}]\n\n"]
    for name in REQUIRED:
        key = KEY_PREFIX + name.lower()
        lines.append(f'{key}="{escape(values[name])}"\n')
    project.write_text(text.rstrip("\n") + "\n" + "".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument(
        "--release",
        action="store_true",
        help="require https, for any build that leaves this machine",
    )
    options = parser.parse_args()

    if not options.project.is_file() or options.project.is_symlink():
        raise SystemExit("FATAL: project.godot is missing or unsafe")

    values = read_values(options.release)
    inject(options.project, values)
    # Names only. The whole point of reading from the environment is that no
    # value reaches a log or a terminal.
    print("injected platform configuration: " + ", ".join(sorted(values)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
