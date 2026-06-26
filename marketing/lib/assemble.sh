#!/usr/bin/env bash
# Assemble ordered segment clips into a finished promo, in all three social
# formats. Robust two-stage approach: normalize every input to a common format
# first, then concat (so mixed sources, e.g. Movie Maker .avi + .mp4, just work).
#
# Usage:
#   assemble.sh --out out/myvid/final [--music bed.mp3] [--vo voice.wav] \
#       [--music-gain 0.25] clip1.avi clip2.avi clip3.mp4 ...
#
# Audio:
#   - no --vo, no --music : keep each clip's own audio.
#   - --music only        : music bed under the original audio.
#   - --vo                : voiceover on top; if --music too, bed sits under VO.
#
# Outputs: <out>_16x9.mp4, <out>_1x1.mp4, <out>_9x16.mp4
set -euo pipefail

OUT=""; MUSIC=""; VO=""; MUSIC_GAIN="0.25"
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
mkdir -p "$(dirname "$OUT")"
TMP="$(dirname "$OUT")/.assemble_tmp"; mkdir -p "$TMP"

# 1) normalize each clip to 1280x720 30fps, silent video track only
echo "[assemble] normalizing ${#CLIPS[@]} segment(s)"
LIST="$TMP/list.txt"; : > "$LIST"
i=0
for c in "${CLIPS[@]}"; do
  n="$TMP/norm_$(printf '%02d' "$i").mp4"
  ffmpeg -y -loglevel error -i "$c" \
    -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30" \
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
      -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30" \
      -c:v libx264 -pix_fmt yuv420p -crf 20 -c:a aac -ar 48000 -ac 2 "$n" 2>/dev/null \
      || ffmpeg -y -loglevel error -i "$c" -f lavfi -t 0.1 -i anullsrc=r=48000:cl=stereo \
         -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30" \
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
  -vf "crop=720:720:280:0,scale=1080:1080" -c:v libx264 -pix_fmt yuv420p -crf 20 \
  -movflags +faststart -c:a aac "${OUT}_1x1.mp4"
ffmpeg -y -loglevel error -i "$MASTER" \
  -vf "crop=720:720:280:0,scale=1080:1080,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 \
  -movflags +faststart -c:a aac "${OUT}_9x16.mp4"

rm -rf "$TMP"
echo "[assemble] done: ${OUT}_16x9.mp4  ${OUT}_1x1.mp4  ${OUT}_9x16.mp4"
