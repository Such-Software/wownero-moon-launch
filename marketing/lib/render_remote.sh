#!/usr/bin/env bash
# Render a gameplay level on the Linux render host via xvfb (a virtual framebuffer
# = NO physical display) and pull the social-format MP4s back. Nothing ever opens a
# window on the laptop. This is the macOS-Movie-Maker workaround: the game can even
# run fullscreen on the server -- it renders into the fake display nobody sees.
#
# Prereq: run marketing/lib/deb_setup.sh on the host once.
#
# Usage:
#   marketing/lib/render_remote.sh <level> <seconds> [out_base]
# Examples:
#   marketing/lib/render_remote.sh 1 15
#   RENDER_HOST=deb GODOT_DRIVER=opengl3 marketing/lib/render_remote.sh 3 20 out/l3
#
# Env:
#   RENDER_HOST       ssh host alias            (default: deb)
#   RENDER_REMOTE_DIR project dir on the host   (default: moonlaunch-render, ~ relative)
#   GODOT_REMOTE      godot binary path on host (default: $HOME/godot/Godot_v4.6.1-stable_linux.x86_64)
#   GODOT_DRIVER      "" = Godot default (Vulkan/lavapipe); set "opengl3" for llvmpipe fallback
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${RENDER_HOST:-deb}"
REMOTE_DIR="${RENDER_REMOTE_DIR:-moonlaunch-render}"
GODOT_REMOTE="${GODOT_REMOTE:-\$HOME/godot/Godot_v4.6.1-stable_linux.x86_64}"
DRIVER="${GODOT_DRIVER:-}"

LEVEL="${1:-1}"; DURATION="${2:-15}"; OUT_BASE="${3:-out/remote_level_${LEVEL}}"
FRAMES=$((DURATION * 60))
SCENE="res://game/levels/${LEVEL}/Level${LEVEL}.tscn"
DRIVER_ARG=""; [ -n "$DRIVER" ] && DRIVER_ARG="--rendering-driver $DRIVER"
REMOTE_AVI="/tmp/ml_render_${LEVEL}.avi"

# Fail fast with a clear message if the host is unreachable (e.g. Nebula down).
if ! ssh -o ConnectTimeout=12 -o BatchMode=yes "$HOST" 'true' 2>/dev/null; then
  echo "[remote-render] ERROR: cannot reach '$HOST'. Is Nebula up + the host online?" >&2
  echo "  test with: ssh $HOST true" >&2
  exit 3
fi

echo "[remote-render] syncing project -> $HOST:$REMOTE_DIR ..."
# Exclude everything not needed to RENDER a level. builds/ alone is ~3.6GB of
# exported APK/IPA artifacts; android/ios are mobile build dirs. --delete-excluded
# also reclaims them on deb if an earlier sync already copied them.
rsync -az --delete --delete-excluded \
  --exclude '.git' --exclude 'out' --exclude '.import' \
  --exclude 'builds' --exclude 'android' --exclude 'ios' \
  --exclude 'screenshots' --exclude 'reports' \
  --exclude 'rl/.venv' --exclude 'rl/logs' --exclude 'rl/checkpoints' \
  --exclude '.signing' --exclude 'override.cfg' \
  "$PROJ/" "$HOST:$REMOTE_DIR/"

echo "[remote-render] rendering Level $LEVEL ($FRAMES frames @ 60fps) under xvfb ..."
# Pass the hybrid-pilot env through so we can render the RL-piloted run (SML_RL_LAND=1).
RL_ENV="SML_RL_LAND='${SML_RL_LAND:-}' SML_RL_DETERMINISTIC='${SML_RL_DETERMINISTIC:-}'"
ssh "$HOST" "cd '$REMOTE_DIR' && $RL_ENV xvfb-run -a $GODOT_REMOTE $DRIVER_ARG \
  --path . --resolution 1280x720 --write-movie '$REMOTE_AVI' \
  --quit-after $FRAMES --capture --autopilot '$SCENE' 2>&1 \
  | grep -E 'frames at|Done recording|RL landing ENABLED|SCRIPT ERROR' || true"

echo "[remote-render] pulling video back ..."
mkdir -p "$PROJ/out"
rsync -az "$HOST:$REMOTE_AVI" "$PROJ/out/.remote_${LEVEL}.avi"

echo "[remote-render] assembling social formats locally ..."
"$PROJ/marketing/lib/assemble.sh" --out "$OUT_BASE" "$PROJ/out/.remote_${LEVEL}.avi"
rm -f "$PROJ/out/.remote_${LEVEL}.avi"
echo "[remote-render] DONE -> ${OUT_BASE}_16x9.mp4  ${OUT_BASE}_1x1.mp4  ${OUT_BASE}_9x16.mp4"
