#!/usr/bin/env bash
# Assemble ordered segment clips into a finished promo, in all three social
# formats. Robust two-stage approach: normalize every input to a common format
# first, then concat (so mixed sources, e.g. Movie Maker .avi + .mp4, just work).
#
# Usage:
#   assemble.sh --out "$HOME/Build/scratch/such-moon-launch/marketing/myvid/final" \
#       [--music bed.mp3] [--vo voice.wav] [--music-gain 0.25] \
#       clip1.avi clip2.avi clip3.mp4 ...
#
# Audio:
#   - no --vo, no --music : keep each clip's own audio.
#   - --music only        : music bed under the original audio.
#   - --vo                : voiceover on top; if --music too, bed sits under VO.
#
# Outputs: <out>_16x9.mp4, <out>_1x1.mp4, <out>_9x16.mp4
#
# Env:
#   MK_OUT_RES  master/16:9 resolution   (default: 1920x1080 -- 1080p)
#   MK_FPS      master frame rate        (default: 60)
# The 1:1 and 9:16 socials crop a native centered square (side = master height) out of
# the master with no upscaling. The square is derived from MK_OUT_RES, so overriding the
# master resolution (e.g. a 720p take) keeps the crops valid -- nothing is hardcoded to 1080.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workspace_paths.sh"
OUT=""; MUSIC=""; VO=""; MUSIC_GAIN="0.25"
OUT_RES="${MK_OUT_RES:-1920x1080}"; OUT_W="${OUT_RES%x*}"; OUT_H="${OUT_RES#*x}"
FPS="${MK_FPS:-60}"
# Social crops derived from the master so any MK_OUT_RES stays valid (landscape OR
# portrait, e.g. SML_PORTRAIT=1080x1920): the square side is the SHORTER master
# dimension, centered on the long axis. V_H forced even for yuv420p.
if [ "$OUT_W" -le "$OUT_H" ]; then SQ="$OUT_W"; else SQ="$OUT_H"; fi
SQ_X=$(( (OUT_W - SQ) / 2 )); SQ_Y=$(( (OUT_H - SQ) / 2 )); V_H=$(( (SQ * 16 / 9) / 2 * 2 ))
CLIPS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2;;
    --music) MUSIC="$2"; shift 2;;
    --vo) VO="$2"; shift 2;;
    --music-gain) MUSIC_GAIN="$2"; shift 2;;
    *) CLIPS+=("$1"); shift;;
  esac
done
if [ -z "$OUT" ] || [ "${#CLIPS[@]}" -eq 0 ]; then
  echo "usage: assemble.sh --out <base> [--music f] [--vo f] clip1 clip2 ..." >&2
  exit 2
fi
sml_require_build_output "$OUT"
TMP="$(mktemp -d "$(dirname "$OUT")/.assemble_tmp.XXXXXX")"
cleanup_tmp() {
  rm -rf -- "$TMP"
}
trap cleanup_tmp EXIT

# 1) normalize each clip to the master res/fps (1920x1080 60fps), silent video track only
echo "[assemble] normalizing ${#CLIPS[@]} segment(s) at ${OUT_W}x${OUT_H} ${FPS}fps"
LIST="$TMP/list.txt"; : > "$LIST"
i=0
for c in "${CLIPS[@]}"; do
  n="$TMP/norm_$(printf '%02d' "$i").mp4"
  ffmpeg -y -loglevel error -i "$c" \
    -vf "scale=${OUT_W}:${OUT_H}:force_original_aspect_ratio=decrease,pad=${OUT_W}:${OUT_H}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=${FPS}" \
    -an -c:v libx264 -pix_fmt yuv420p -crf 20 "$n"
  echo "file '$(basename "$n")'" >> "$LIST"
  i=$((i+1))
done

# 2) concat into a silent 16:9 master
MASTER_V="$TMP/master_v.mp4"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST" -c copy "$MASTER_V"

# 3) build the audio bed (optional) and mux into the master
MASTER="$TMP/master.mp4"
if [ -z "$MUSIC" ] && [ -z "$VO" ]; then
  # keep original per-clip audio: re-concat WITH audio (re-encode to be safe)
  : > "$TMP/list_a.txt"
  i=0
  for c in "${CLIPS[@]}"; do
    n="$TMP/na_$(printf '%02d' "$i").mp4"
    ffmpeg -y -loglevel error -i "$c" \
      -vf "scale=${OUT_W}:${OUT_H}:force_original_aspect_ratio=decrease,pad=${OUT_W}:${OUT_H}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=${FPS}" \
      -c:v libx264 -pix_fmt yuv420p -crf 20 -c:a aac -ar 48000 -ac 2 "$n" 2>/dev/null \
      || ffmpeg -y -loglevel error -i "$c" -f lavfi -t 0.1 -i anullsrc=r=48000:cl=stereo \
         -vf "scale=${OUT_W}:${OUT_H}:force_original_aspect_ratio=decrease,pad=${OUT_W}:${OUT_H}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=${FPS}" \
         -shortest -c:v libx264 -pix_fmt yuv420p -crf 20 -c:a aac "$n"
    echo "file '$(basename "$n")'" >> "$TMP/list_a.txt"
    i=$((i+1))
  done
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list_a.txt" -c copy "$MASTER"
else
  # synthesize the bed: music (looped, quieted) and/or VO, sized to the video
  AINPUTS=(); FILTERS=(); idx=1
  AINPUTS+=(-i "$MASTER_V")  # input 0 = video (silent)
  mixparts=()
  if [ -n "$MUSIC" ]; then
    AINPUTS+=(-stream_loop -1 -i "$MUSIC")
    FILTERS+=("[${idx}:a]volume=${MUSIC_GAIN}[mus]"); mixparts+=("[mus]"); idx=$((idx+1))
  fi
  if [ -n "$VO" ]; then
    AINPUTS+=(-i "$VO")
    FILTERS+=("[${idx}:a]volume=1.0[vo]"); mixparts+=("[vo]"); idx=$((idx+1))
  fi
  nmix="${#mixparts[@]}"
  FC="$(IFS=';'; echo "${FILTERS[*]}")"
  FC="${FC};${mixparts[*]}amix=inputs=${nmix}:duration=first:dropout_transition=0[aout]"
  ffmpeg -y -loglevel error "${AINPUTS[@]}" -filter_complex "$FC" \
    -map 0:v -map "[aout]" -c:v copy -c:a aac -shortest "$MASTER"
fi

# 4) emit the three formats from the master
echo "[assemble] exporting formats"
ffmpeg -y -loglevel error -i "$MASTER" -c:v libx264 -pix_fmt yuv420p -crf 20 \
  -movflags +faststart -c:a aac "${OUT}_16x9.mp4"
ffmpeg -y -loglevel error -i "$MASTER" \
  -vf "crop=${SQ}:${SQ}:${SQ_X}:${SQ_Y}" -c:v libx264 -pix_fmt yuv420p -crf 20 \
  -movflags +faststart -c:a aac "${OUT}_1x1.mp4"
ffmpeg -y -loglevel error -i "$MASTER" \
  -vf "crop=${SQ}:${SQ}:${SQ_X}:${SQ_Y},pad=${SQ}:${V_H}:(ow-iw)/2:(oh-ih)/2:color=black" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 \
  -movflags +faststart -c:a aac "${OUT}_9x16.mp4"

cleanup_tmp
trap - EXIT
echo "[assemble] done: ${OUT}_16x9.mp4  ${OUT}_1x1.mp4  ${OUT}_9x16.mp4"
