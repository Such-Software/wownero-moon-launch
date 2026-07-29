#!/usr/bin/env bash
# Assemble a PORTRAIT (1080x1920) promo: normalize each clip to a common
# res/fps/codec (keeping its own audio, silence for clips that have none), concat,
# then lay a music bed UNDER the clip audio (VO stays on top). Unlike assemble.sh
# this keeps a native portrait master (no center-square crop).
#
# usage: make_promo.sh <out.mp4> <music.mp3> <clip1> <clip2> ...
set -euo pipefail
OUT="$1"; MUSIC="$2"; shift 2
W=1080; H=1920; FPS=30
VF="scale=$W:$H:force_original_aspect_ratio=decrease,pad=$W:$H:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=$FPS"
TMP="$(mktemp -d)"; LIST="$TMP/list.txt"; : > "$LIST"
i=0
for c in "$@"; do
  n="$TMP/n$(printf '%02d' "$i").mp4"
  if ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$c" 2>/dev/null | grep -q audio; then
    ffmpeg -y -loglevel error -i "$c" -vf "$VF" -map 0:v:0 -map 0:a:0 \
      -c:v libx264 -pix_fmt yuv420p -crf 20 -c:a aac -ar 48000 -ac 2 "$n"
  else  # no audio (e.g. the CTA) -> attach silence so concat stays uniform
    ffmpeg -y -loglevel error -i "$c" -f lavfi -i anullsrc=r=48000:cl=stereo \
      -vf "$VF" -map 0:v:0 -map 1:a:0 -shortest \
      -c:v libx264 -pix_fmt yuv420p -crf 20 -c:a aac -ar 48000 -ac 2 "$n"
  fi
  echo "file '$n'" >> "$LIST"; i=$((i+1))
done
CAT="$TMP/cat.mp4"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST" -c copy "$CAT"
# music bed under the clip audio; fade the bed out at the end.
DUR="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$CAT")"
FOUT="$(awk "BEGIN{printf \"%.2f\", $DUR-1.0}")"
ffmpeg -y -loglevel error -i "$CAT" -stream_loop -1 -i "$MUSIC" -filter_complex \
  "[1:a]volume=0.18,afade=t=out:st=${FOUT}:d=1.0[m];\
   [0:a][m]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -ar 48000 -movflags +faststart "$OUT"
rm -rf "$TMP"
echo "OK $OUT ($(printf '%.1f' "$DUR")s)"
