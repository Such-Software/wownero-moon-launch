#!/usr/bin/env python3
"""Verify that marketing generators respect workstation path boundaries."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
from contextlib import contextmanager


sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[2]
MARKETING_LIB = ROOT / "marketing" / "lib"
PATH_HELPER = MARKETING_LIB / "workspace_paths.py"
SHELL_PATH_HELPER = MARKETING_LIB / "workspace_paths.sh"
FORBIDDEN_TEXT = (
    "/Users/",
    "/private/tmp/",
    "marketing/out",
    "Seafile/Source",
)


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


@contextmanager
def environment(**values: str | None):
    previous = {name: os.environ.get(name) for name in values}
    try:
        for name, value in values.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        yield
    finally:
        for name, value in previous.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value


def load_helper():
    spec = importlib.util.spec_from_file_location("sml_workspace_paths", PATH_HELPER)
    if spec is None or spec.loader is None:
        fail("cannot load marketing workspace path helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def marketing_sources(glob: str) -> list[pathlib.Path]:
    output = subprocess.check_output(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            glob,
        ],
        cwd=ROOT,
        text=True,
    )
    return sorted(ROOT / line for line in output.splitlines() if line)


def shell_policy_call(
    *,
    home: pathlib.Path,
    build_root: pathlib.Path,
    function_name: str,
    argument: pathlib.Path | str,
) -> subprocess.CompletedProcess[str]:
    environment_values = os.environ.copy()
    environment_values.update(
        {
            "HOME": str(home),
            "SUCH_BUILD_ROOT": str(build_root),
        }
    )
    return subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; "$2" "$3"',
            "marketing-workspace-policy",
            str(SHELL_PATH_HELPER),
            function_name,
            str(argument),
        ],
        cwd=ROOT,
        env=environment_values,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def expect_rejected(callable_value, label: str) -> None:
    try:
        callable_value()
    except ValueError:
        return
    fail(f"{label} was not rejected")


def main() -> None:
    python_sources = marketing_sources("marketing/lib/*.py")
    shell_sources = marketing_sources("marketing/lib/*.sh")
    sources = python_sources + shell_sources
    if PATH_HELPER not in python_sources:
        fail("marketing workspace path helper is missing")
    if SHELL_PATH_HELPER not in shell_sources:
        fail("marketing shell workspace path helper is missing")

    for path in sources:
        source = path.read_text(encoding="utf-8")
        for marker in FORBIDDEN_TEXT:
            if marker not in source:
                continue
            if path in (PATH_HELPER, SHELL_PATH_HELPER) and marker == "Seafile/Source":
                continue
            fail(f"{path.relative_to(ROOT)} contains forbidden path marker {marker!r}")

    helper = load_helper()
    # macOS aliases /tmp to /private/tmp. Normalize the synthetic home before
    # comparing it with helper results, which are deliberately resolved.
    fake_home = pathlib.Path("/tmp/sml-marketing-policy/home").resolve(strict=False)
    build_root = fake_home / "Build"
    source_root = fake_home / "src" / "such-graphics"
    with environment(
        HOME=str(fake_home),
        SUCH_BUILD_ROOT=str(build_root),
        SUCH_GRAPHICS_SRC=str(source_root),
        SML_MARKETING_RUN_ID="policy-check",
        SML_MARKETING_RUN_ROOT=None,
    ):
        if helper.such_graphics_source() != source_root:
            fail("Such Graphics default did not resolve below ~/src")
        expected = (
            build_root
            / "scratch"
            / "such-moon-launch"
            / "marketing"
            / "policy-check"
        )
        if helper.marketing_run_root() != expected:
            fail("marketing default did not resolve below the configured Build root")

    with environment(
        SUCH_BUILD_ROOT=str(build_root),
        SML_MARKETING_RUN_ROOT=str(fake_home / "Seafile" / "Source" / "draft"),
    ):
        expect_rejected(helper.marketing_run_root, "Seafile Source output")

    with environment(
        SUCH_BUILD_ROOT=str(build_root),
        SML_MARKETING_RUN_ROOT="/tmp/outside-build",
    ):
        expect_rejected(helper.marketing_run_root, "output outside Build")

    with environment(SUCH_GRAPHICS_SRC=str(fake_home / "Seafile" / "Source")):
        expect_rejected(helper.such_graphics_source, "Seafile Source dependency")

    with tempfile.TemporaryDirectory(prefix="sml-marketing-policy-", dir="/tmp") as temp:
        shell_home = pathlib.Path(temp) / "home"
        shell_build = shell_home / "Build"
        allowed = shell_policy_call(
            home=shell_home,
            build_root=shell_build,
            function_name="sml_require_build_output",
            argument=shell_build / "scratch" / "moon" / "clip.mp4",
        )
        if allowed.returncode != 0:
            fail(f"shell helper rejected Build output: {allowed.stderr.strip()}")

        outside = shell_policy_call(
            home=shell_home,
            build_root=shell_build,
            function_name="sml_require_build_output",
            argument=pathlib.Path(temp) / "outside" / "clip.mp4",
        )
        if outside.returncode == 0:
            fail("shell helper accepted output outside Build")

        recovery = shell_policy_call(
            home=shell_home,
            build_root=shell_home / "Seafile" / "Source",
            function_name="sml_require_build_output",
            argument=shell_home / "Seafile" / "Source" / "clip.mp4",
        )
        if recovery.returncode == 0:
            fail("shell helper accepted Seafile Source as a Build root")

        safe_run = shell_policy_call(
            home=shell_home,
            build_root=shell_build,
            function_name="sml_require_safe_run_id",
            argument="release-candidate-01",
        )
        if safe_run.returncode != 0:
            fail(f"shell helper rejected safe run ID: {safe_run.stderr.strip()}")

        unsafe_run = shell_policy_call(
            home=shell_home,
            build_root=shell_build,
            function_name="sml_require_safe_run_id",
            argument="../Source",
        )
        if unsafe_run.returncode == 0:
            fail("shell helper accepted unsafe run ID")

        safe_remote = shell_policy_call(
            home=shell_home,
            build_root=shell_build,
            function_name="sml_require_remote_build_path",
            argument="Build/such-moon-launch/render/source",
        )
        if safe_remote.returncode != 0:
            fail(
                "shell helper rejected safe remote Build path: "
                f"{safe_remote.stderr.strip()}"
            )

        unsafe_remote = shell_policy_call(
            home=shell_home,
            build_root=shell_build,
            function_name="sml_require_remote_build_path",
            argument="Seafile/Source/render",
        )
        if unsafe_remote.returncode == 0:
            fail("shell helper accepted remote path outside Build")

    print(
        "PASS marketing workspace policy "
        f"({len(python_sources)} Python and {len(shell_sources)} shell generators)"
    )


if __name__ == "__main__":
    main()
