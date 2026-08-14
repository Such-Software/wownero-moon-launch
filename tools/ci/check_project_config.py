#!/usr/bin/env python3
"""Guard project.godot against the Godot editor's destructive rewrites.

A cold-cache `godot --editor --quit` pass (which tools/ci/verify.sh runs) mints
resource UIDs and rewrites project.godot in two ways that must never be
committed:

1. Autoload script paths are replaced with `uid://` references. That breaks
   check_android_release_contract.py, which pins the Google Play Games autoload
   to its exact res:// path, and makes the autoload table unreadable to humans
   and to every other parser in tools/.
2. The whole file is re-serialized from the in-memory config, which silently
   drops every `;` comment -- including the [input] block documenting the
   gamepad button map, the only place that mapping is written down.

Commit ab6ef4e had to hand-revert exactly this. This check makes the corruption
fail loudly at the step that caused it instead of surfacing later as an
unrelated-looking "candidates require a clean checkout" abort from
tools/export_candidate.sh.
"""

from __future__ import annotations

import pathlib
import sys

# Documented [input] comment markers that the editor's re-serialization drops.
# Matching on substrings keeps this robust to reflowing the surrounding prose.
REQUIRED_INPUT_COMMENT_MARKERS = (
    "Gamepad bindings",
    "JOY_BUTTON_A",
    "JOY_AXIS_TRIGGER_RIGHT",
)


def fail(message: str) -> None:
    raise ValueError(message)


def check_autoloads_are_paths(text: str) -> int:
    """Every autoload must name a res:// script, never a uid:// reference."""
    in_autoload = False
    checked = 0
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            in_autoload = line == "[autoload]"
            continue
        if not in_autoload or not line or line.startswith(";") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        checked += 1
        if "uid://" in value:
            fail(
                f"autoload {name.strip()} is a uid:// reference ({value.strip()}). "
                "The Godot editor rewrote project.godot; restore the res:// path "
                "with `git checkout project.godot`."
            )
    if checked == 0:
        fail("no autoloads found in project.godot -- the [autoload] section is missing")
    return checked


def check_input_comments_survive(text: str) -> None:
    """The editor drops ';' comments when it re-serializes project.godot."""
    missing = [m for m in REQUIRED_INPUT_COMMENT_MARKERS if m not in text]
    if missing:
        fail(
            "project.godot lost its documented [input] comments "
            f"(missing: {', '.join(missing)}). The Godot editor re-serialized the "
            "file and dropped every ';' comment; restore with "
            "`git checkout project.godot`."
        )


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parents[2]
    project = repo / "project.godot"
    try:
        text = project.read_text(encoding="utf-8")
        autoloads = check_autoloads_are_paths(text)
        check_input_comments_survive(text)
        print(f"PASS project.godot config ({autoloads} autoloads, [input] comments intact)")
        return 0
    except (OSError, ValueError) as error:
        print(f"FAIL project.godot config: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
