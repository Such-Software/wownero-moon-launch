#!/usr/bin/env bash
# Orchestrate a single gameplay render straight to MP4, normalizing aspect ratios.
# Uses the project's existing capture and assembly mechanics.
#
# Usage:
#   ./rl/render_level.sh <level_num> <duration_sec> [output_base_path] [extra_godot_args...]
#
# Examples:
#   ./rl/render_level.sh 1 15               # renders Level 1 for 15s to out/rendered_level_1_*
#   ./rl/render_level.sh 3 20 my_folder/l3   # renders Level 3 for 20s to my_folder/l3_*
set -euo pipefail


cd "$(dirname "${BASH_SOURCE[0]}")/.."

LEVEL="${1:-1}"
DURATION="${2:-20}"
OUT_BASE="${3:-out/rendered_level_${LEVEL}}"
shift 3 || true


FRAMES=$((DURATION * 60))
TMP_AVI="out/.tmp_render_${LEVEL}.avi"

echo "=================================================="
echo "[render-script] Rendering Level ${LEVEL} for ${DURATION}s (${FRAMES} frames)..."
echo "=================================================="

# 1. Capture the gameplay headless-safely with autopilot enabled
./marketing/lib/capture.sh \
  "res://game/levels/${LEVEL}/Level${LEVEL}.tscn" \
  "${TMP_AVI}" \
  "${FRAMES}" \
  --autopilot \
  "$@"



echo "[render-script] Capture complete. Assembling social formats via marketing library..."

# 2. Process and normalize the AVI master into 16:9, 1:1 and 9:16 social MP4 formats
./marketing/lib/assemble.sh \
  --out "${OUT_BASE}" \
  "${TMP_AVI}"



# 3. Cleanup temp video
rm -f "${TMP_AVI}"

echo "=================================================="
echo "[render-script] SUCCESS! Saved outputs to:"
echo "  - ${OUT_BASE}_16x9.mp4"
echo "  - ${OUT_BASE}_1x1.mp4"
echo "  - ${OUT_BASE}_9x16.mp4"
echo "=================================================="
