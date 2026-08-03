#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 tools/check_app_platform.py --expect-app moon_launch
python3 tools/ci/check_app_platform_baseline.py
python3 tools/ci/check_web_commerce.py
node tools/ci/test_web_checkout.mjs
python3 tools/ci/check_nakama_runtime.py
python3 tools/ci/check_nakama_godot_sdk.py
python3 tools/ci/check_release_contract.py
python3 tools/ci/check_android_release_contract.py
python3 tools/ci/check_marketing_workspace.py
python3 tools/ci/test_app_store_connect.py
node website/scripts/validate.mjs

if [[ "${SML_SKIP_NAKAMA_BUILD:-0}" != "1" ]]; then
  bash tools/ci/build_nakama_runtime.sh
fi
if [[ "${SML_SKIP_WEBSITE_BUILD:-0}" != "1" ]]; then
  bash tools/ci/build_website.sh
fi
if [[ -n "${SML_POSTGRES_TEST_IMAGE:-}" ]]; then
  bash tools/ci/test_nakama_postgres.sh
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
echo "Godot $ACTUAL_VERSION"
grep -Fq "4.6.1" <<<"$ACTUAL_VERSION" || {
  echo "FATAL: Such Moon Launch verification requires Godot 4.6.1." >&2
  exit 1
}

BUILD_ROOT="${SML_BUILD_ROOT:-${SML_CI_BUILD_ROOT:-${SUCH_BUILD_ROOT:-$HOME/Build/such-moon-launch}}}"
VERIFY_ID="${SML_VERIFY_RUN_ID:-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}}"
LOG_ROOT="$BUILD_ROOT/tests/$VERIFY_ID"
REPORT_ROOT="$LOG_ROOT/reports"
REPORT_LINK=".sml-ci-reports"
PROJECT_CACHE="$LOG_ROOT/project-cache"
PROJECT_CACHE_LINK=".godot"
OWNS_PROJECT_CACHE_LINK=0
mkdir -p "$LOG_ROOT" "$REPORT_ROOT"
if [[ -e "$REPORT_LINK" || -L "$REPORT_LINK" ]]; then
  echo "FATAL: temporary GdUnit report link is already occupied." >&2
  exit 1
fi
if [[ -e "$PROJECT_CACHE_LINK" || -L "$PROJECT_CACHE_LINK" ]]; then
  if [[ -n "${SML_PROJECT_CACHE:-}" &&
        -L "$PROJECT_CACHE_LINK" &&
        "$(readlink "$PROJECT_CACHE_LINK")" == "$SML_PROJECT_CACHE" ]]; then
    PROJECT_CACHE="$SML_PROJECT_CACHE"
    echo "Using runner-managed Godot project cache ($PROJECT_CACHE)"
  else
    echo "FATAL: source checkout already contains an unmanaged Godot project cache." >&2
    exit 1
  fi
else
  mkdir -p "$PROJECT_CACHE"
  ln -s "$PROJECT_CACHE" "$PROJECT_CACHE_LINK"
  OWNS_PROJECT_CACHE_LINK=1
fi
ln -s "$REPORT_ROOT" "$REPORT_LINK"

cleanup_transient_links() {
  if [[ -L "$REPORT_LINK" && "$(readlink "$REPORT_LINK")" == "$REPORT_ROOT" ]]; then
    rm -f "$REPORT_LINK"
  fi
  if [[ "$OWNS_PROJECT_CACHE_LINK" == "1" &&
        -L "$PROJECT_CACHE_LINK" &&
        "$(readlink "$PROJECT_CACHE_LINK")" == "$PROJECT_CACHE" ]]; then
    rm -f "$PROJECT_CACHE_LINK"
  fi
}
trap cleanup_transient_links EXIT

set -o pipefail
"$GODOT_BIN" --headless --path . --editor --quit 2>&1 | tee "$LOG_ROOT/import.log"
if grep -Eiq \
  '(^|[[:space:]])ERROR:|Unicode parsing error|^Error loading configuration|SCRIPT ERROR|PARSE ERROR|Error importing|Failed to (load|open).*(res://|resource)|Cannot open.*res://' \
  "$LOG_ROOT/import.log"; then
  echo "FATAL: Godot import reported an engine, script, resource, or import error." >&2
  exit 1
fi

SML_TEST_MODE=1 "$GODOT_BIN" --headless --path . \
  -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add "res://test/" --ignoreHeadlessMode \
  --report-directory "res://$REPORT_LINK" 2>&1 | tee "$LOG_ROOT/gdunit.log"

RESULTS_XML="$(find "$REPORT_ROOT" -type f -name results.xml -print -quit)"
if [[ -z "$RESULTS_XML" ]]; then
  echo "FATAL: GdUnit passed without writing its report below Build." >&2
  exit 1
fi

echo "PASS Such Moon Launch verification ($LOG_ROOT)"
