#!/usr/bin/env bash
# QA smoke-clip: render the standard ~10s Level-1 clip through the full GPU render
# pipeline and run an automated video QA on it. This is the smoke test to run after
# ANY visual change (starfield shader, thrust particles, HUD, camera, etc.) before
# committing -- one command in, PASS/CHECK summary out.
#
# What it does:
#   1) render_remote.sh 1 10 -> renders L1 for 10s on the GPU box and pulls the
#      three social formats into Build review space. Defaults target the 1080 Ti
#      box (such-aigen-one, display :0) for hardware Vulkan at 1080p; override via env.
#   2) QA the 16x9 master. Preferred: the such-graphics `video-qa` gate
#      (docs: ~/src/docs/harnesses/video-generation-harness.md), which checks size and
#      media integrity. If that CLI isn't on PATH we fall back to a best-effort ffprobe
#      that reports resolution + fps and pass/fails on the expected 1920x1080.
#
# The automated gate proves MEDIA integrity (right size/fps, decodes, not all-black).
# It CANNOT see scene meaning, so three things stay MANUAL WATCH items (printed below):
#   - stars blink / twinkle (starfield shader animates)
#   - exhaust does NOT strobe (thrust particle ramp is smooth)
#   - target arrow + HUD are legible at 1080p
#
# Usage:
#   marketing/lib/qa_clip.sh                       # GPU box (such-aigen-one :0), L1, 10s
#   RENDER_HOST=deb RENDER_DISPLAY= marketing/lib/qa_clip.sh   # software xvfb fallback
#   QA_SECONDS=15 marketing/lib/qa_clip.sh         # longer take
#   QA_OUT_BASE="$HOME/Build/review/such-moon-launch/qa_myfix" marketing/lib/qa_clip.sh
#
# Env:
#   RENDER_HOST      ssh host alias for the render box   (default: such-aigen-one)
#   RENDER_DISPLAY   GPU X display for hardware Vulkan    (default: :0)
#   QA_LEVEL         level to render                      (default: 1)
#   QA_SECONDS       clip length in seconds               (default: 10)
#   QA_OUT_BASE      output base path below Build         (default: Build review space)
#   QA_EXPECT_SIZE   expected WxH for the master          (default: 1920x1080)
#   ...plus anything render_remote.sh honours (MK_RES, SML_SEED, GODOT_DRIVER, ...).
#
# NOTE: this is a wrapper; all rendering happens in render_remote.sh. It does not run
# godot or training locally.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workspace_paths.sh"
# ---- config -----------------------------------------------------------------
# Default to the GPU box (1080 Ti) on its real X display so we exercise the hardware
# render path -- the same path the marketing renders ship on. Both are overridable so
# the smoke test still works against the software xvfb host (RENDER_DISPLAY= to disable).
export RENDER_HOST="${RENDER_HOST:-such-aigen-one}"
export RENDER_DISPLAY="${RENDER_DISPLAY-:0}"

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJ"
LEVEL="${QA_LEVEL:-1}"
SECONDS_LEN="${QA_SECONDS:-10}"
BUILD_ROOT="${SUCH_BUILD_ROOT:-$HOME/Build}"
RUN_ID="${SML_MARKETING_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
sml_require_safe_run_id "$RUN_ID"
OUT_BASE="${QA_OUT_BASE:-$BUILD_ROOT/review/such-moon-launch/marketing/$RUN_ID/qa_clip}"
sml_require_build_output "$OUT_BASE"
EXPECT_SIZE="${QA_EXPECT_SIZE:-1920x1080}"

# render_remote.sh emits <base>_16x9.mp4 / _1x1.mp4 / _9x16.mp4; the 16x9 is the
# full-res master we QA against.
MASTER="${OUT_BASE}_16x9.mp4"

echo "=========================================================================="
echo " QA smoke-clip: Level ${LEVEL}, ${SECONDS_LEN}s  ->  ${OUT_BASE}_16x9.mp4"
echo "   render host : ${RENDER_HOST}  display: ${RENDER_DISPLAY:-<xvfb software>}"
echo "=========================================================================="

# ---- 1) render --------------------------------------------------------------
echo "[qa] rendering via render_remote.sh ..."
"${PROJ}/marketing/lib/render_remote.sh" "$LEVEL" "$SECONDS_LEN" "$OUT_BASE"

if [ ! -f "$MASTER" ]; then
	echo "[qa] ERROR: expected master not found: $MASTER" >&2
	exit 4
fi

# ---- 2) automated QA gate ---------------------------------------------------
# Preferred gate: the such-graphics `video-qa` tool (see
# ~/src/docs/harnesses/video-generation-harness.md). Its documented form is:
#   such-graphics video-qa <file> --expect-size WxH [--contact-sheet ...] ...
# We invoke it best-effort; if the CLI is absent (or errors on flags), fall back to a
# plain ffprobe that reports resolution + fps and pass/fails on the expected size.
QA_STATUS="PASS"
if command -v such-graphics >/dev/null 2>&1; then
	echo "[qa] running such-graphics video-qa ..."
	if such-graphics video-qa "$MASTER" --expect-size "$EXPECT_SIZE"; then
		echo "[qa] such-graphics video-qa: PASS"
	else
		echo "[qa] such-graphics video-qa: reported issues (see above)"
		QA_STATUS="CHECK"
	fi
else
	echo "[qa] such-graphics not on PATH -- falling back to ffprobe media check."
	if ! command -v ffprobe >/dev/null 2>&1; then
		echo "[qa] ERROR: neither such-graphics nor ffprobe available; cannot QA." >&2
		exit 5
	fi
	# width,height and avg frame rate of the first video stream.
	DIMS="$(ffprobe -v error -select_streams v:0 \
		-show_entries stream=width,height -of csv=p=0:s=x "$MASTER" 2>/dev/null || true)"
	FPS_RAW="$(ffprobe -v error -select_streams v:0 \
		-show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$MASTER" 2>/dev/null || true)"
	# avg_frame_rate is a "num/den" rational; reduce it to a decimal when we can.
	FPS="$FPS_RAW"
	if [[ "$FPS_RAW" == */* ]]; then
		NUM="${FPS_RAW%/*}"; DEN="${FPS_RAW#*/}"
		if [ "${DEN:-0}" != "0" ] && [ -n "${NUM:-}" ]; then
			FPS="$(awk "BEGIN{printf \"%.3f\", ${NUM}/${DEN}}" 2>/dev/null || echo "$FPS_RAW")"
		fi
	fi
	echo "[qa] ffprobe: resolution=${DIMS:-unknown}  fps=${FPS:-unknown}"
	if [ "$DIMS" = "$EXPECT_SIZE" ]; then
		echo "[qa] ffprobe media check: PASS (matches expected $EXPECT_SIZE)"
	else
		echo "[qa] ffprobe media check: CHECK (got '${DIMS:-none}', expected $EXPECT_SIZE)"
		QA_STATUS="CHECK"
	fi
fi

# ---- 3) summary -------------------------------------------------------------
echo "=========================================================================="
echo " QA summary for ${OUT_BASE}_16x9.mp4"
echo "   automated media gate : ${QA_STATUS}"
echo "   MANUAL WATCH (decode QA cannot see these -- eyeball the clip):"
echo "     [ ] stars blink / twinkle (starfield animates)"
echo "     [ ] exhaust does NOT strobe (thrust ramp is smooth)"
echo "     [ ] target arrow + HUD legible at 1080p"
echo "=========================================================================="

if [ "$QA_STATUS" = "PASS" ]; then
	echo "[qa] PASS (automated). Confirm the manual-watch items before shipping."
	exit 0
else
	echo "[qa] CHECK: automated gate flagged something -- review above + file in TODO.md."
	exit 1
fi
