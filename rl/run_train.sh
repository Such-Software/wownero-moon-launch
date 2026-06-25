#!/usr/bin/env bash
# Orchestrate a headless RL training run.
# Mode A (interactive): start Python PPO server + one local headless Godot client.
# Mode B (parallel export): use an exported env binary with n_parallel > 1.
#
# Usage:
#   rl/run_train.sh [timesteps] [restore.zip] [env_path] [n_parallel]
# Examples:
#   rl/run_train.sh 200000
#   rl/run_train.sh 500000 rl/moonlaunch_ppo.zip
#   rl/run_train.sh 500000 "" builds/rl-train.x86_64 8
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TIMESTEPS="${1:-4096}"
RESTORE="${2:-}"   # optional: path to a checkpoint .zip to continue from
ENV_PATH="${3:-}"  # optional: exported training binary path for n_parallel mode
N_PARALLEL="${4:-1}"
SPEEDUP="${SPEEDUP:-8}"
PORT_BASE="${PORT_BASE:-11008}"
mkdir -p rl/logs
: > rl/logs/trainer.log; : > rl/logs/godot.log

if [[ -z "$ENV_PATH" && "$N_PARALLEL" != "1" ]]; then
  echo "[orch] ERROR: n_parallel=$N_PARALLEL requires env_path (exported binary)." >&2
  exit 2
fi

PY_ARGS=(rl/train_sb3.py --timesteps "$TIMESTEPS" --speedup "$SPEEDUP" --n_parallel "$N_PARALLEL" --port "$PORT_BASE")
[[ -n "$RESTORE" ]] && PY_ARGS+=(--restore "$RESTORE")
[[ -n "$ENV_PATH" ]] && PY_ARGS+=(--env_path "$ENV_PATH")

echo "[orch] starting PPO server (timesteps=$TIMESTEPS n_parallel=$N_PARALLEL port=$PORT_BASE${RESTORE:+, restore=$RESTORE}${ENV_PATH:+, env_path=$ENV_PATH})..."
rl/.venv/bin/python "${PY_ARGS[@]}" > rl/logs/trainer.log 2>&1 &
TRAINER=$!
GODOT_PID=""

if [[ -z "$ENV_PATH" ]]; then
  # Interactive mode: give the Python server a moment to bind, then launch one
  # local client that connects to it.
  sleep 7
  echo "[orch] launching Godot client (headless interactive mode)..."
  # --capture gates telemetry/score submission (no backend pollution during training);
  # it does NOT activate the heuristic autopilot (that's --autopilot), so no conflict.
  "$GODOT" --headless --path . res://rl/train.tscn --capture --speedup="$SPEEDUP" --port="$PORT_BASE" > rl/logs/godot.log 2>&1 &
  GODOT_PID=$!
fi

wait "$TRAINER"; RC=$?
if [[ -n "$GODOT_PID" ]]; then
  echo "[orch] trainer exited rc=$RC; stopping godot client pid=$GODOT_PID"
  kill "$GODOT_PID" 2>/dev/null || true
else
  echo "[orch] trainer exited rc=$RC"
fi

echo ""; echo "==== trainer.log (tail) ===="; tail -30 rl/logs/trainer.log
if [[ -n "$GODOT_PID" ]]; then
  echo ""; echo "==== godot.log (tail) ===="; tail -25 rl/logs/godot.log
fi
