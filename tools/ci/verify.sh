#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 tools/ci/check_release_contract.py
python3 tools/ci/check_android_release_contract.py

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

BUILD_ROOT="${SML_BUILD_ROOT:-${SUCH_BUILD_ROOT:-$HOME/Build/such-moon-launch}}"
VERIFY_ID="${SML_VERIFY_RUN_ID:-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}}"
LOG_ROOT="$BUILD_ROOT/tests/$VERIFY_ID"
REPORT_ROOT="$LOG_ROOT/reports"
REPORT_LINK=".sml-ci-reports"
mkdir -p "$LOG_ROOT" "$REPORT_ROOT"
if [[ -e "$REPORT_LINK" || -L "$REPORT_LINK" ]]; then
  echo "FATAL: temporary GdUnit report link is already occupied." >&2
  exit 1
fi
ln -s "$REPORT_ROOT" "$REPORT_LINK"

cleanup_report_link() {
  if [[ -L "$REPORT_LINK" && "$(readlink "$REPORT_LINK")" == "$REPORT_ROOT" ]]; then
    rm -f "$REPORT_LINK"
  fi
}
trap cleanup_report_link EXIT

set -o pipefail
"$GODOT_BIN" --headless --path . --editor --quit 2>&1 | tee "$LOG_ROOT/import.log"
if grep -Eiq \
  'SCRIPT ERROR|PARSE ERROR|Error importing|Failed to (load|open).*(res://|resource)|Cannot open.*res://' \
  "$LOG_ROOT/import.log"; then
  echo "FATAL: Godot import reported a script, resource, or import error." >&2
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
