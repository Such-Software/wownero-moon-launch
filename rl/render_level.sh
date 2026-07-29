#!/usr/bin/env bash
# Orchestrate a single gameplay render straight to MP4, normalizing aspect ratios.
# Uses the project's existing capture and assembly mechanics.
#
# Usage:
#   ./rl/render_level.sh <level_num> <duration_sec> [output_base_path] [extra_godot_args...]
#
# Examples:
#   ./rl/render_level.sh 1 15               # renders to ~/Build/scratch/such-moon-launch/...
#   ./rl/render_level.sh 3 20 my_folder/l3   # renders Level 3 for 20s to my_folder/l3_*
set -euo pipefail


cd "$(dirname "${BASH_SOURCE[0]}")/.."

LEVEL="${1:-1}"
DURATION="${2:-20}"
BUILD_ROOT="${SUCH_BUILD_ROOT:-$HOME/Build}"
RUN_ID="${SML_MARKETING_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_BASE="${3:-$BUILD_ROOT/scratch/such-moon-launch/marketing/$RUN_ID/rendered_level_${LEVEL}}"
if (($# >= 3)); then
  shift 3
else
  shift "$#"
fi


FRAMES=$((DURATION * 60))
mkdir -p "$(dirname "$OUT_BASE")"
TMP_AVI="${OUT_BASE}.source.avi"

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
