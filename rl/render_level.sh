#!/usr/bin/env bash
2. # Orchestrate a single gameplay render straight to MP4, normalizing aspect ratios.
3. # Uses the project's existing capture and assembly mechanics.
4. #
5. # Usage:
6. #   ./rl/render_level.sh <level_num> <duration_sec> [output_base_path] [extra_godot_args...]
7. #
8. # Examples:
9. #   ./rl/render_level.sh 1 15               # renders Level 1 for 15s to out/rendered_level_1_*
10. #   ./rl/render_level.sh 3 20 my_folder/l3   # renders Level 3 for 20s to my_folder/l3_*
11. set -euo pipefail
12. 
13. cd "$(dirname "${BASH_SOURCE[0]}")/.."
14. 
15. LEVEL="${1:-1}"
16. SECONDS="${2:-20}"
17. OUT_BASE="${3:-out/rendered_level_${LEVEL}}"
18. shift 3 || true
19. 
20. FRAMES=$((SECONDS * 60))
21. TMP_AVI="out/.tmp_render_${LEVEL}.avi"
22. 
23. echo "=================================================="
24. echo "[render-script] Rendering Level ${LEVEL} for ${SECONDS}s (${FRAMES} frames)..."
25. echo "=================================================="
26. 
27. # 1. Capture the gameplay headless-safely with autopilot enabled
28. ./marketing/lib/capture.sh \
29.   "res://game/levels/${LEVEL}/Level${LEVEL}.tscn" \
30.   "${TMP_AVI}" \
31.   "${FRAMES}" \
32.   --autopilot \
33.   "$@"
34. 
35. echo "[render-script] Capture complete. Assembling social formats via marketing library..."
36. 
37. # 2. Process and normalize the AVI master into 16:9, 1:1 and 9:16 social MP4 formats
38. ./marketing/lib/assemble.sh \
39.   --out "${OUT_BASE}" \
40.   "${TMP_AVI}"
41. 
42. # 3. Cleanup temp video
43. rm -f "${TMP_AVI}"
44. 
45. echo "=================================================="
46. echo "[render-script] SUCCESS! Saved outputs to:"
47. echo "  - ${OUT_BASE}_16x9.mp4"
48. echo "  - ${OUT_BASE}_1x1.mp4"
49. echo "  - ${OUT_BASE}_9x16.mp4"
50. echo "=================================================="
51. 