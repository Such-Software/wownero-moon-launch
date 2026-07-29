#!/usr/bin/env bash

# Shared workstation-boundary guard for generated marketing media.

sml_marketing_build_root() {
  printf '%s\n' "${SUCH_BUILD_ROOT:-$HOME/Build}"
}

sml_require_safe_run_id() {
  local run_id="$1"
  if [[ ! "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$ ]]; then
    echo "FATAL: marketing run IDs may use only letters, digits, '.', '_', and '-'." >&2
    return 1
  fi
}

sml_require_remote_build_path() {
  local remote_path="$1"
  if [[ ! "$remote_path" =~ ^Build/[A-Za-z0-9._/-]+$ ]]; then
    echo "FATAL: remote render paths must be relative paths below ~/Build." >&2
    return 1
  fi
  case "/$remote_path/" in
    *"/../"* | *"/./"* | *"//"*)
      echo "FATAL: remote render paths must not contain traversal components." >&2
      return 1
      ;;
  esac
}

sml_require_build_output() {
  local output_path="$1"
  local output_dir
  local build_root
  local workstation_build_root
  local resolved_output_dir
  local resolved_build_root

  output_dir="$(dirname "$output_path")"
  build_root="$(sml_marketing_build_root)"
  resolved_output_dir="$(
    python3 -c \
      'import pathlib, sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve(strict=False))' \
      "$output_dir"
  )"
  resolved_build_root="$(
    python3 -c \
      'import pathlib, sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve(strict=False))' \
      "$build_root"
  )"
  workstation_build_root="$(
    python3 -c \
      'import pathlib; print((pathlib.Path.home() / "Build").resolve(strict=False))'
  )"

  case "$resolved_build_root/" in
    *"/Seafile/Source/"*)
      echo "FATAL: Seafile Source is Fleet-managed recovery, never a Build root." >&2
      return 1
      ;;
  esac

  case "$resolved_build_root/" in
    "$workstation_build_root/"*) ;;
    *)
      echo "FATAL: SUCH_BUILD_ROOT must remain below $workstation_build_root" >&2
      return 1
      ;;
  esac

  case "$resolved_output_dir/" in
    "$resolved_build_root/"*) ;;
    *)
      echo "FATAL: marketing output must remain below $resolved_build_root" >&2
      echo "Resolved output directory: $resolved_output_dir" >&2
      return 1
      ;;
  esac

  mkdir -p "$resolved_output_dir" "$resolved_build_root"
}
