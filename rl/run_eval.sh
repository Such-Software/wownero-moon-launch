#!/usr/bin/env bash
# Evaluate the trained policy on the UNMODIFIED Level 1 (natural start, no curriculum).
# Headless, no window. Reads the [RL] landing rate the Godot agent logs.
# Usage: rl/run_eval.sh [steps]
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
STEPS="${1:-30000}"
mkdir -p rl/logs
: > rl/logs/eval.log; : > rl/logs/godot_eval.log

echo "[orch] starting eval policy server (steps=$STEPS)..."
rl/.venv/bin/python rl/eval_sb3.py --steps "$STEPS" --speedup 8 > rl/logs/eval.log 2>&1 &
EVALPID=$!
sleep 7
echo "[orch] launching Godot client (headless, RL_EVAL=1 -> natural Level-1 start)..."
RL_EVAL=1 "$GODOT" --headless --path . res://rl/train.tscn --capture --speedup=8 --port=11008 > rl/logs/godot_eval.log 2>&1 &
GPID=$!

wait "$EVALPID"
kill "$GPID" 2>/dev/null; pkill -f "res://rl/train.tscn" 2>/dev/null

echo ""; echo "=== eval.log ==="; tail -6 rl/logs/eval.log
echo ""; echo "=== landings on NATURAL Level 1 ([RL] lines) ==="
grep "\[RL\]" rl/logs/godot_eval.log 2>/dev/null | tail -8
