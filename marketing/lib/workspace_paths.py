"""Portable workspace paths for Moon Launch marketing generators.

Source dependencies are read from ``~/src`` by default. Generated drafts,
caches, frames, and videos are written below ``~/Build`` unless the caller
provides an explicit Build-rooted run directory.
"""

from __future__ import annotations

import os
import re
import shutil
from pathlib import Path


PROJECT_SLUG = "such-moon-launch"
_SAFE_RUN_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$")


def _resolved(path: Path) -> Path:
    return path.resolve(strict=False)


def _is_within(path: Path, parent: Path) -> bool:
    return path == parent or parent in path.parents


def _reject_recovery_source(path: Path) -> None:
    parts = path.parts
    for index in range(len(parts) - 1):
        if parts[index : index + 2] == ("Seafile", "Source"):
            raise ValueError("Seafile Source is Fleet-managed recovery, never a work path")


def such_graphics_source() -> Path:
    """Return the configured real source checkout for Such Graphics."""
    configured = os.environ.get("SUCH_GRAPHICS_SRC")
    if configured:
        source = _resolved(Path(configured).expanduser())
    else:
        source = _resolved(Path.home() / "src" / "such-graphics")

    source_root = _resolved(Path.home() / "src")
    _reject_recovery_source(source)
    if not _is_within(source, source_root):
        raise ValueError("SUCH_GRAPHICS_SRC must identify a real checkout below ~/src")
    return source


def marketing_run_root() -> Path:
    """Return the disposable output root for this marketing run."""
    configured_build_root = os.environ.get("SUCH_BUILD_ROOT")
    if configured_build_root:
        build_root = _resolved(Path(configured_build_root).expanduser())
    else:
        build_root = _resolved(Path.home() / "Build")
    workstation_build_root = _resolved(Path.home() / "Build")
    _reject_recovery_source(build_root)
    if not _is_within(build_root, workstation_build_root):
        raise ValueError("SUCH_BUILD_ROOT must remain below ~/Build")

    configured_run_root = os.environ.get("SML_MARKETING_RUN_ROOT")
    if configured_run_root:
        run_root = _resolved(Path(configured_run_root).expanduser())
    else:
        run_id = os.environ.get("SML_MARKETING_RUN_ID", "local")
        if not _SAFE_RUN_ID.fullmatch(run_id):
            raise ValueError(
                "SML_MARKETING_RUN_ID must use only letters, digits, '.', '_', or '-'"
            )
        run_root = build_root / "scratch" / PROJECT_SLUG / "marketing" / run_id

    _reject_recovery_source(run_root)
    if not _is_within(run_root, build_root):
        raise ValueError("SML_MARKETING_RUN_ROOT must remain below SUCH_BUILD_ROOT")
    return run_root


def blender_executable() -> str:
    """Return an explicit Blender binary or a portable platform default."""
    configured = os.environ.get("SML_BLENDER_BIN")
    if configured:
        return str(Path(configured).expanduser())

    on_path = shutil.which("blender")
    if on_path:
        return on_path
    return "/Applications/Blender.app/Contents/MacOS/Blender"
