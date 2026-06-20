#!/usr/bin/env bash
# Render a Godot scene (gameplay level OR a marketing scene) to a video clip via
# Movie Maker. Movie Maker must render, so this opens a window, but we shove it
# OFF-SCREEN (--position 6000,6000) so it does not steal focus or land on top of
# you. This is the only step that opens a window; headless sims never do.
#
# Usage:
#   capture.sh <res-scene-path> <out.avi> <quit-after-frames> [extra godot args...]
#
# Examples:
#   # gameplay (autopilot flies it):
#   capture.sh res://game/levels/1/Level1.tscn out/seg_01.avi 900 --autopilot
#   # 3D mascot (env vars configure Stage3D):
#   MK_GLB=res://marketing/assets/characters/doge.glb MK_CAPTION="wow" \
#     capture.sh res://marketing/stage/Stage3D.tscn out/seg_02.avi 300
#
# Frames are at 60fps (Movie Maker default), so 300 frames = 5s of video.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RES="${MK_RES:-1280x720}"

if [ "$#" -lt 3 ]; then
  echo "usage: capture.sh <res-scene> <out.avi> <quit-after-frames> [godot args...]" >&2
  exit 2
fi
SCENE="$1"; OUT="$2"; FRAMES="$3"; shift 3
mkdir -p "$(dirname "$OUT")"

echo "[capture] $SCENE -> $OUT (${FRAMES}f @ ${RES})"
"$GODOT" --path "$PROJ" --resolution "$RES" --position 6000,6000 \
  --write-movie "$OUT" --quit-after "$FRAMES" "$@" "$SCENE" 2>&1 \
  | grep -E "frames at|Done recording|SCRIPT ERROR" || true
