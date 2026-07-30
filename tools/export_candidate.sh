#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PRESET="${1:-}"
case "$PRESET" in
  Web)               ARTIFACT="index.html" ;;
  Android)           ARTIFACT="SuchMoonLaunch.aab" ;;
  iOS)               ARTIFACT="SuchMoonLaunch.ipa" ;;
  "Windows Desktop") ARTIFACT="SuchMoonLaunch.exe" ;;
  macOS)             ARTIFACT="SuchMoonLaunch.dmg" ;;
  Linux)             ARTIFACT="SuchMoonLaunch.x86_64" ;;
  *)
    echo 'Usage: tools/export_candidate.sh {Web|Android|iOS|Windows Desktop|macOS|Linux}' >&2
    exit 2
    ;;
esac

WORKTREE_DIRTY="false"
if [[ -n "$(git status --porcelain)" ]]; then
  WORKTREE_DIRTY="true"
fi
if [[ "$WORKTREE_DIRTY" == "true" && "${SML_ALLOW_DIRTY:-0}" != "1" ]]; then
  echo "FATAL: candidates require a clean checkout (or SML_ALLOW_DIRTY=1 for local review)." >&2
  exit 1
fi

GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
if [[ -z "$GODOT_BIN" ]]; then
  GODOT_BIN="$(command -v godot || command -v godot4 || true)"
fi
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "FATAL: set GODOT_BIN to a Godot 4.6.1 executable." >&2
  exit 1
fi

ACTUAL_VERSION="$("$GODOT_BIN" --version)"
grep -Fq "4.6.1" <<<"$ACTUAL_VERSION" || {
  echo "FATAL: Such Moon Launch candidates require Godot 4.6.1." >&2
  exit 1
}

BUILD_ROOT="${SUCH_BUILD_ROOT:-$HOME/Build/such-moon-launch}"
mkdir -p "$BUILD_ROOT"
BUILD_ROOT="$(cd "$BUILD_ROOT" && pwd)"
SHA="$(git rev-parse HEAD)"
RUN_ID="${SML_BUILD_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-${SHA:0:12}}"
PRODUCT_DIR="$BUILD_ROOT/products/$RUN_ID"
LOG_DIR="$BUILD_ROOT/logs/$RUN_ID"
mkdir -p "$PRODUCT_DIR" "$LOG_DIR"

PROJECT_CACHE_LINK="$ROOT/.godot"
PROJECT_CACHE="${SML_PROJECT_CACHE:-$BUILD_ROOT/cache/godot-project/$RUN_ID}"
OWNS_PROJECT_CACHE_LINK=0

cleanup_transient_build_state() {
  case "${SML_FIREBASE_STAGE_DIR:-}" in
    "${TMPDIR:-/tmp}"/sml-firebase-aar.*) rm -rf -- "$SML_FIREBASE_STAGE_DIR" ;;
    "") ;;
    *) echo "WARNING: refusing to remove unexpected Firebase staging directory." >&2 ;;
  esac
  if [[ "$OWNS_PROJECT_CACHE_LINK" == "1" &&
        -L "$PROJECT_CACHE_LINK" &&
        "$(readlink "$PROJECT_CACHE_LINK")" == "$PROJECT_CACHE" ]]; then
    rm -f "$PROJECT_CACHE_LINK"
  fi
}
trap cleanup_transient_build_state EXIT

if [[ -e "$PROJECT_CACHE_LINK" || -L "$PROJECT_CACHE_LINK" ]]; then
  if [[ -n "${SML_PROJECT_CACHE:-}" &&
        -L "$PROJECT_CACHE_LINK" &&
        "$(readlink "$PROJECT_CACHE_LINK")" == "$SML_PROJECT_CACHE" ]]; then
    PROJECT_CACHE="$SML_PROJECT_CACHE"
    echo "Using runner-managed Godot project cache ($PROJECT_CACHE)"
  else
    echo "FATAL: source checkout contains an unmanaged Godot project cache." >&2
    echo "Use a clean release worktree or an ownership-checked SML_PROJECT_CACHE link." >&2
    exit 1
  fi
else
  mkdir -p "$PROJECT_CACHE"
  ln -s "$PROJECT_CACHE" "$PROJECT_CACHE_LINK"
  OWNS_PROJECT_CACHE_LINK=1
fi
export SML_PROJECT_CACHE="$PROJECT_CACHE"

if [[ "$PRESET" == "Android" ]]; then
  KEYSTORE="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}"
  FIREBASE_CONFIG="${SML_ANDROID_GOOGLE_SERVICES_PATH:-}"
  [[ -f "$KEYSTORE" ]] || { echo "FATAL: Android release keystore not found." >&2; exit 1; }
  [[ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" ]] || { echo "FATAL: Android release alias is empty." >&2; exit 1; }
  [[ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]] || { echo "FATAL: Android release password is empty." >&2; exit 1; }
  [[ -f "$FIREBASE_CONFIG" ]] || { echo "FATAL: Vaultwarden-provisioned google-services.json not found." >&2; exit 1; }
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD

  python3 - "$FIREBASE_CONFIG" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
project_id = config.get("project_info", {}).get("project_id")
if project_id != "suchsoftwareapps":
    raise SystemExit(
        f"FATAL: Android Firebase project must be 'suchsoftwareapps', got {project_id!r}"
    )
matches = [
    client
    for client in config.get("client", [])
    if client.get("client_info", {})
    .get("android_client_info", {})
    .get("package_name")
    == "com.suchsoftware.suchmoonlaunch"
]
if len(matches) != 1:
    raise SystemExit(
        "FATAL: google-services.json must contain exactly one Such Moon Launch client"
    )
if not matches[0].get("client_info", {}).get("mobilesdk_app_id"):
    raise SystemExit("FATAL: Such Moon Launch Firebase client has no mobilesdk_app_id")
PY

  BASE_FIREBASE_AAR="addons/BloomwordFirebase/bin/release/BloomwordFirebase-release.aar"
  [[ -f "$BASE_FIREBASE_AAR" ]] || {
    echo "FATAL: tracked BloomwordFirebase release AAR is missing." >&2
    exit 1
  }
  FIREBASE_INTERMEDIATE="$BUILD_ROOT/intermediates/firebase/$RUN_ID"
  SML_FIREBASE_STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sml-firebase-aar.XXXXXX")"
  mkdir -p "$FIREBASE_INTERMEDIATE" "$SML_FIREBASE_STAGE_DIR/assets"
  SML_FIREBASE_ANDROID_AAR="$FIREBASE_INTERMEDIATE/BloomwordFirebase-release.aar"
  cp "$BASE_FIREBASE_AAR" "$SML_FIREBASE_ANDROID_AAR"
  cp "$FIREBASE_CONFIG" "$SML_FIREBASE_STAGE_DIR/assets/google-services.json"
  (
    cd "$SML_FIREBASE_STAGE_DIR"
    zip -q -u "$SML_FIREBASE_ANDROID_AAR" assets/google-services.json
  )
  unzip -l "$SML_FIREBASE_ANDROID_AAR" | grep -Eq \
    'assets/google-services\.json$' || {
      echo "FATAL: prepared Firebase AAR has no packaged client config." >&2
      exit 1
    }
  export SML_FIREBASE_ANDROID_AAR

  [[ -f android/build/build.gradle ]] || {
    echo "FATAL: install the Godot Android build template at android/build first." >&2
    exit 1
  }
  python3 tools/ci/prepare_android_template.py --root android/build
  export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$BUILD_ROOT/cache/gradle}"
fi

if [[ "${SML_SKIP_VERIFY:-0}" != "1" ]]; then
  GODOT_BIN="$GODOT_BIN" bash tools/ci/verify.sh | tee "$LOG_DIR/verify.log"
fi

if [[ "$PRESET" == "Web" ]]; then
  mkdir -p "$PRODUCT_DIR/web"
  OUTPUT="$PRODUCT_DIR/web/$ARTIFACT"
else
  OUTPUT="$PRODUCT_DIR/$ARTIFACT"
fi

"$GODOT_BIN" --headless --path . --export-release "$PRESET" "$OUTPUT" \
  2>&1 | tee "$LOG_DIR/export.log"

{
  printf 'project=such-moon-launch\n'
  printf 'git_sha=%s\n' "$SHA"
  printf 'git_ref=%s\n' "$(git symbolic-ref --short -q HEAD || printf detached)"
  printf 'worktree_dirty=%s\n' "$WORKTREE_DIRTY"
  printf 'release_eligible=%s\n' "$([[ "$WORKTREE_DIRTY" == "false" ]] && printf true || printf false)"
  printf 'preset=%s\n' "$PRESET"
  printf 'godot=%s\n' "$ACTUAL_VERSION"
  printf 'built_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$PRODUCT_DIR/provenance.txt"

if [[ "$PRESET" == "Web" ]]; then
  (
    cd "$PRODUCT_DIR"
    find web -type f -print0 | sort -z | xargs -0 sha256sum
  ) > "$PRODUCT_DIR/SHA256SUMS"
else
  (
    cd "$PRODUCT_DIR"
    sha256sum "$ARTIFACT"
  ) > "$PRODUCT_DIR/SHA256SUMS"
fi

if [[ "$WORKTREE_DIRTY" == "true" ]]; then
  echo "Audit product (dirty checkout; NOT FOR RELEASE): $PRODUCT_DIR"
else
  echo "Candidate: $PRODUCT_DIR"
fi
