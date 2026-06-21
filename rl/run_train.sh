#!/usr/bin/env bash
# Orchestrate a headless RL training run: start the Python PPO server, then launch
# the Godot client (headless, no window) which connects to it. No focus-stealing.
#
# Usage: rl/run_train.sh [timesteps]   (default 4096 = quick smoke test)
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TIMESTEPS="${1:-4096}"
RESTORE="${2:-}"   # optional: path to a checkpoint .zip to continue from
mkdir -p rl/logs
: > rl/logs/trainer.log; : > rl/logs/godot.log

echo "[orch] starting PPO server (timesteps=$TIMESTEPS${RESTORE:+, restore=$RESTORE})..."
rl/.venv/bin/python rl/train_sb3.py --timesteps "$TIMESTEPS" --speedup 8 ${RESTORE:+--restore "$RESTORE"} > rl/logs/trainer.log 2>&1 &
TRAINER=$!

# give the server a moment to bind the port, then launch the Godot client
sleep 7
echo "[orch] launching Godot client (headless)..."
# --capture gates telemetry/score submission (no backend pollution during training);
# it does NOT activate the heuristic autopilot (that's --autopilot), so no conflict.
"$GODOT" --headless --path . res://rl/train.tscn --capture --speedup=8 --port=11008 > rl/logs/godot.log 2>&1 &
GODOT_PID=$!

wait "$TRAINER"; RC=$?
echo "[orch] trainer exited rc=$RC; stopping godot client"
kill "$GODOT_PID" 2>/dev/null
pkill -f "res://rl/train.tscn" 2>/dev/null

echo ""; echo "==== trainer.log (tail) ===="; tail -30 rl/logs/trainer.log
echo ""; echo "==== godot.log (tail) ===="; tail -25 rl/logs/godot.log
