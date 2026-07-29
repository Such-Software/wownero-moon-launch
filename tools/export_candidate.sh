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

BUILD_ROOT="${SUCH_BUILD_ROOT:-$HOME/Build}"
SHA="$(git rev-parse HEAD)"
RUN_ID="${SML_BUILD_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-${SHA:0:12}}"
PRODUCT_DIR="$BUILD_ROOT/products/such-moon-launch/$RUN_ID"
LOG_DIR="$BUILD_ROOT/logs/such-moon-launch/$RUN_ID"
mkdir -p "$PRODUCT_DIR" "$LOG_DIR"

cleanup_android_material() {
  if [[ -n "${ANDROID_FIREBASE_LINK_TARGET:-}" &&
        -L google-services.json &&
        "$(readlink google-services.json)" == "$ANDROID_FIREBASE_LINK_TARGET" ]]; then
    rm -f google-services.json
  fi
}

if [[ "$PRESET" == "Android" ]]; then
  KEYSTORE="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$HOME/keys/suchsoftware/keystores/wowneromoonlaunch/release.keystore}"
  KEYSTORE_LEDGER="${SML_KEYSTORE_LEDGER:-$HOME/keys/suchsoftware/keystores/KEYSTORES.md}"
  if [[ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" ]]; then
    GODOT_ANDROID_KEYSTORE_RELEASE_USER="$(
      awk -F'|' '/wowneromoonlaunch\/release\.keystore/ {
        gsub(/^[ \t]+|[ \t]+$/, "", $3)
        gsub(/`/, "", $3)
        print $3
        exit
      }' "$KEYSTORE_LEDGER"
    )"
  fi
  if [[ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]]; then
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(
      awk -F'|' '/wowneromoonlaunch\/release\.keystore/ {
        gsub(/^[ \t]+|[ \t]+$/, "", $4)
        gsub(/`/, "", $4)
        print $4
        exit
      }' "$KEYSTORE_LEDGER"
    )"
  fi
  [[ -f "$KEYSTORE" ]] || { echo "FATAL: Android release keystore not found." >&2; exit 1; }
  [[ -n "$GODOT_ANDROID_KEYSTORE_RELEASE_USER" ]] || { echo "FATAL: Android release alias is empty." >&2; exit 1; }
  [[ -n "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" ]] || { echo "FATAL: Android release password is empty." >&2; exit 1; }
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD

  [[ -f android/google-services.json ]] || {
    echo "FATAL: android/google-services.json is required for Android Firebase." >&2
    exit 1
  }
  if [[ -e google-services.json || -L google-services.json ]]; then
    echo "FATAL: temporary root google-services.json path is already occupied." >&2
    exit 1
  fi
  ANDROID_FIREBASE_LINK_TARGET="android/google-services.json"
  ln -s "$ANDROID_FIREBASE_LINK_TARGET" google-services.json
  trap cleanup_android_material EXIT

  [[ -f android/build/build.gradle ]] || {
    echo "FATAL: install the Godot Android build template at android/build first." >&2
    exit 1
  }
  export GRADLE_USER_HOME="$BUILD_ROOT/cache/gradle/such-moon-launch"
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
