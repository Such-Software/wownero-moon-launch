#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 tools/ci/check_release_contract.py

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

LOG_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/such-moon-launch-ci"
mkdir -p "$LOG_ROOT"

set -o pipefail
"$GODOT_BIN" --headless --path . --editor --quit 2>&1 | tee "$LOG_ROOT/import.log"
if grep -Eiq \
  'SCRIPT ERROR|PARSE ERROR|Error importing|Failed to (load|open).*(res://|resource)|Cannot open.*res://' \
  "$LOG_ROOT/import.log"; then
  echo "FATAL: Godot import reported a script, resource, or import error." >&2
  exit 1
fi

"$GODOT_BIN" --headless --path . \
  -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add "res://test/" --ignoreHeadlessMode 2>&1 | tee "$LOG_ROOT/gdunit.log"

echo "PASS Such Moon Launch verification"
