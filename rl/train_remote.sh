#!/usr/bin/env bash
# Train the RL lander on a many-core GPU box with PARALLEL Godot env instances.
#
# The heuristic autopilot is CPU-env-bound, not GPU-bound: the win is running many
# Godot training envs at once (n_parallel), which needs an EXPORTED headless Linux
# binary. This script syncs the project, exports that binary on the host, runs SB3
# PPO across n_parallel envs, and pulls the trained model + checkpoints back.
#
# The training binary boots res://rl/train.tscn and godot_rl_agents launches it with
# --disable-render-loop, which the game treats as "no live backend" (Telemetry/
# ScoreClient/Analytics all gate on it) -- training never pollutes production.
#
# One-time host setup (already done on such-aigen-one):
#   - $HOME/godot/Godot_v4.6.1-stable_linux.x86_64  (+ 4.6.1 export templates)
#   - a venv at $RL_VENV with: torch (cpu), stable-baselines3, godot-rl
#
# Usage:
#   rl/train_remote.sh [timesteps] [n_parallel]
# Examples:
#   rl/train_remote.sh 500000 16
#   RL_RESTORE=rl/moonlaunch_ppo.zip rl/train_remote.sh 1000000 24   # continue a run
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${RL_HOST:-such-aigen-one}"
REMOTE_DIR="${RL_REMOTE_DIR:-moonlaunch-rl}"
GODOT_REMOTE="${GODOT_REMOTE:-\$HOME/godot/Godot_v4.6.1-stable_linux.x86_64}"
VENV="${RL_VENV:-/root/rl-venv}"

TIMESTEPS="${1:-500000}"
N_PARALLEL="${2:-16}"
SPEEDUP="${SPEEDUP:-8}"
PORT="${RL_PORT:-12000}"
SAVE="${RL_SAVE:-rl/moonlaunch_ppo}"     # remote path (relative to $REMOTE_DIR), no .zip
RESTORE="${RL_RESTORE:-}"                # optional remote .zip to continue from

# Fail fast if the box is unreachable.
if ! ssh -o ConnectTimeout=12 -o BatchMode=yes "$HOST" 'true' 2>/dev/null; then
  echo "[rl-remote] ERROR: cannot reach '$HOST' (ssh $HOST true)." >&2
  exit 3
fi

echo "[rl-remote] syncing project -> $HOST:$REMOTE_DIR ..."
rsync -az --delete --delete-excluded \
  --exclude '.git' --exclude 'out' --exclude '.import' \
  --exclude 'builds' --exclude 'android' --exclude 'ios' \
  --exclude 'screenshots' --exclude 'reports' \
  --exclude 'rl/.venv' --exclude 'rl/logs' --exclude 'rl/checkpoints' \
  --exclude '.signing' --exclude 'override.cfg' \
  "$PROJ/" "$HOST:$REMOTE_DIR/"

echo "[rl-remote] exporting training binary + training ($TIMESTEPS steps, $N_PARALLEL envs) ..."
ssh "$HOST" \
  REMOTE_DIR="$REMOTE_DIR" GODOT="$GODOT_REMOTE" VENV="$VENV" \
  TIMESTEPS="$TIMESTEPS" N_PARALLEL="$N_PARALLEL" SPEEDUP="$SPEEDUP" \
  PORT="$PORT" SAVE="$SAVE" RESTORE="$RESTORE" 'bash -s' <<'REMOTE'
set -euo pipefail
cd "$REMOTE_DIR"
# The exported binary must BOOT the training scene (Sync connects to the PPO server).
sed -i 's|run/main_scene="res://game/gui/menu/Menu.tscn"|run/main_scene="res://rl/train.tscn"|' project.godot
mkdir -p builds
echo "[host] import + export headless Linux binary..."
"$GODOT" --headless --path . --import >/tmp/rl_import.log 2>&1
"$GODOT" --headless --path . --export-release "Linux" builds/rl-train.x86_64 >/tmp/rl_export.log 2>&1
test -x builds/rl-train.x86_64 || { echo "[host] export FAILED"; tail -20 /tmp/rl_export.log; exit 4; }
echo "[host] training..."
"$VENV/bin/python" rl/train_sb3.py \
  --env_path builds/rl-train.x86_64 \
  --n_parallel "$N_PARALLEL" --timesteps "$TIMESTEPS" --speedup "$SPEEDUP" --port "$PORT" \
  --save "$SAVE" ${RESTORE:+--restore "$RESTORE"}
REMOTE

echo "[rl-remote] pulling trained model + checkpoints back ..."
mkdir -p "$PROJ/rl/remote_out/checkpoints"
rsync -az "$HOST:$REMOTE_DIR/${SAVE}.zip" "$PROJ/rl/remote_out/" 2>/dev/null || echo "  (no ${SAVE}.zip)"
rsync -az "$HOST:$REMOTE_DIR/rl/checkpoints/" "$PROJ/rl/remote_out/checkpoints/" 2>/dev/null || true
echo "[rl-remote] DONE -> rl/remote_out/ ($(basename "$SAVE").zip + checkpoints)"
