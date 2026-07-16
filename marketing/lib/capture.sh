#!/usr/bin/env bash
# Render a Godot scene (gameplay level OR a marketing scene) to a video clip via
# Movie Maker. true --headless renders nothing (no framebuffer), and Movie Maker
# forces the window fullscreen (overriding --windowed) -- on macOS that yanks you
# to a new Space. The fix: a TEMPORARY override.cfg sets the project window mode to
# WINDOWED for this run only, so the window is born windowed and --position shoves
# it fully off-screen -- nothing ever appears or steals focus. project.godot (which
# ships fullscreen) and headless sims are untouched.
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
RES="${MK_RES:-1920x1080}"

if [ "$#" -lt 3 ]; then
  echo "usage: capture.sh <res-scene> <out.avi> <quit-after-frames> [godot args...]" >&2
  exit 2
fi
SCENE="$1"; OUT="$2"; FRAMES="$3"; shift 3
mkdir -p "$(dirname "$OUT")"

echo "[capture] $SCENE -> $OUT (${FRAMES}f @ ${RES})"

# Movie Maker forces a visible, focused window (fullscreen on macOS => a new Space),
# and macOS refuses to move a window fully off-screen. A temporary override.cfg flips
# the project window mode to MINIMIZED (mode=1) for this run, so the window lives in
# the Dock -- never on-screen, never steals focus -- yet Movie Maker still renders it.
# Removed on exit; any pre-existing override.cfg is preserved and restored.
OVERRIDE="$PROJ/override.cfg"; OVR_BAK=""
[ -f "$OVERRIDE" ] && { OVR_BAK="$OVERRIDE.capbak"; mv "$OVERRIDE" "$OVR_BAK"; }
restore_override() {
  rm -f "$OVERRIDE"
  [ -n "$OVR_BAK" ] && [ -f "$OVR_BAK" ] && mv "$OVR_BAK" "$OVERRIDE"
}
trap restore_override EXIT
cat > "$OVERRIDE" <<'OVR'
[display]

window/size/mode=1
OVR

# --capture keeps telemetry/scores disabled even for non-gameplay scenes (the
# autopilot guard only covers gameplay segments launched with --autopilot).
# IMPORTANT: do NOT pass --position -- it forces the window back OUT of minimized
# mode and onto the screen. The minimized override alone keeps it in the Dock.
"$GODOT" --path "$PROJ" --resolution "$RES" \
  --write-movie "$OUT" --quit-after "$FRAMES" --capture "$@" "$SCENE" 2>&1 \
  | grep -E "frames at|Done recording|SCRIPT ERROR" || true

restore_override; trap - EXIT
