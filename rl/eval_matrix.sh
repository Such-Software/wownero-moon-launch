#!/usr/bin/env bash
# =============================================================================
# rl/eval_matrix.sh  —  Per-level autopilot/RL evaluation matrix (WP-C2)
# =============================================================================
#
# Runs the headless `--sim` harness (game/test/SimHarness.gd) across the full
# campaign and every pilot config, then tabulates a win-rate matrix so we can
# measure BEFORE tuning (this blocks C3/C4). One command -> one markdown report.
#
# For each level 1..11 and each of four configs:
#     * base       AP_EVADE off,  heuristic landing
#     * evade      AP_EVADE=1,     heuristic landing
#     * rl         AP_EVADE off,  SML_RL_LAND=1 (RL lander does the touchdown)
#     * evade+rl   AP_EVADE=1,     SML_RL_LAND=1
# it runs N (default 20) episodes and parses the single `SIM_RESULT` line each
# episode prints (see SimHarness.gd:_report):
#
#     SIM_RESULT outcome=WIN level=1 t=12.34 fuel=44.0 frames=740
#     SIM_RESULT outcome=DEATH level=2 t=8.10 fuel=0.0 frames=486 cause=out_of_fuel
#
#   outcome : WIN | DEATH | TIMEOUT
#   t       : game-seconds to the outcome (used for mean time-to-land on WINs)
#   cause   : (DEATH only) hazard | out_of_fuel | crash  (forensics bucket that
#             mirrors rocket.gd:583-591; SimHarness computes it the same way)
#
# The invocation matches game/test/README.md's sweep example:
#     SIM_LEVEL=$n SIM_TIME_SCALE=$ts \
#       godot --headless --autopilot --sim res://game/levels/$n/Level$n.tscn
#
# Output: reports/eval_matrix_<UTC-date>.md  (rows = levels, cols = configs).
#
# -----------------------------------------------------------------------------
# Env knobs (all optional):
#   GODOT           Godot binary (default /Applications/Godot.app/Contents/MacOS/Godot)
#   EVAL_N          episodes per cell (default 20)
#   SIM_TIME_SCALE  Engine.time_scale for the sims (default 1.5; keep <=1.5 for
#                   honest WIN/DEATH per SimHarness/README). Faster == less fidelity.
#   SIM_MAX_TIME    per-episode game-seconds before TIMEOUT (default 90, harness default)
#   EVAL_LEVELS     space-separated level list (default "1 2 3 4 5 6 7 8 9 10 11")
#   EVAL_CONFIGS    space-separated config list (default "base evade rl evade_rl")
#   EVAL_OUT        output markdown path (default reports/eval_matrix_<date>.md)
#
# Usage:
#   rl/eval_matrix.sh                       # full 11x4 matrix, 20 eps/cell
#   EVAL_N=5 EVAL_LEVELS="1 2" rl/eval_matrix.sh   # quick smoke
#
# NOTE: this needs the game running headless (a working Godot binary + import),
# so it is meant to be RUN by a human/CI, not by the agent that wrote it.
# =============================================================================
set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO_ROOT="$(pwd)"

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
EVAL_N="${EVAL_N:-20}"
SIM_TIME_SCALE="${SIM_TIME_SCALE:-1.5}"
SIM_MAX_TIME="${SIM_MAX_TIME:-90}"
EVAL_LEVELS="${EVAL_LEVELS:-1 2 3 4 5 6 7 8 9 10 11}"
EVAL_CONFIGS="${EVAL_CONFIGS:-base evade rl evade_rl}"
DATE_UTC="$(date -u +%Y-%m-%d)"
EVAL_OUT="${EVAL_OUT:-reports/eval_matrix_${DATE_UTC}.md}"

# Per-episode watchdog: this sweep launches up to levels*configs*N sequential
# Godot processes and relies on SimHarness calling quit(). If any one process
# hangs before printing SIM_RESULT, wrap it so it is killed and counted as an
# ERROR (empty line -> ERROR outcome below) instead of stalling the whole run.
# Uses GNU `timeout`, or `gtimeout` on macOS (brew install coreutils); if neither
# is present, runs without a watchdog.
EVAL_EP_TIMEOUT="${EVAL_EP_TIMEOUT:-180}"
WATCHDOG=""
if command -v timeout >/dev/null 2>&1; then WATCHDOG="timeout ${EVAL_EP_TIMEOUT}"
elif command -v gtimeout >/dev/null 2>&1; then WATCHDOG="gtimeout ${EVAL_EP_TIMEOUT}"
else echo "[eval_matrix] note: no timeout/gtimeout found — running without a per-episode watchdog." >&2
fi

if [ ! -x "$GODOT" ]; then
	echo "[eval_matrix] ERROR: Godot binary not found/executable at: $GODOT" >&2
	echo "[eval_matrix] set GODOT=/path/to/Godot and retry." >&2
	exit 1
fi

mkdir -p rl/logs reports
RAW_LOG="rl/logs/eval_matrix_${DATE_UTC}.log"
: > "$RAW_LOG"

# --- human-friendly column headers (parallel to EVAL_CONFIGS) ----------------
config_label() {
	case "$1" in
		base)     echo "base (no-evade, heuristic land)" ;;
		evade)    echo "AP_EVADE=1, heuristic land" ;;
		rl)       echo "no-evade, SML_RL_LAND=1" ;;
		evade_rl) echo "AP_EVADE=1, SML_RL_LAND=1" ;;
		*)        echo "$1" ;;
	esac
}

# --- translate a config name into the env vars that select it ----------------
# Echoes "AP_EVADE=x SML_RL_LAND=y" style assignments consumed via `env`.
config_env() {
	local ap="" rl=""
	case "$1" in
		base)     ap="0"; rl="0" ;;
		evade)    ap="1"; rl="0" ;;
		rl)       ap="0"; rl="1" ;;
		evade_rl) ap="1"; rl="1" ;;
		*)        ap="0"; rl="0" ;;
	esac
	printf 'AP_EVADE=%s SML_RL_LAND=%s' "$ap" "$rl"
}

# --- run ONE episode, echo "OUTCOME T CAUSE" (CAUSE empty on WIN/TIMEOUT) -----
run_episode() {
	local level="$1" config="$2"
	local cenv line
	cenv="$(config_env "$config")"
	local scene="res://game/levels/${level}/Level${level}.tscn"
	# Isolate each cfg's env; SIM_LEVEL keeps upgrades/scaling honest per level.
	# 2>&1 so an early crash still lands in the log; grep the LAST SIM_RESULT.
	line="$(env $cenv \
		SIM_LEVEL="$level" \
		SIM_TIME_SCALE="$SIM_TIME_SCALE" \
		SIM_MAX_TIME="$SIM_MAX_TIME" \
		$WATCHDOG "$GODOT" --headless --autopilot --sim "$scene" 2>&1 \
		| tee -a "$RAW_LOG" \
		| grep '^SIM_RESULT' | tail -1)"
	if [ -z "$line" ]; then
		# No parseable result (crash/import failure) -> count as an ERROR outcome.
		echo "ERROR 0 error"
		return
	fi
	# Field-extract from "SIM_RESULT outcome=WIN level=1 t=12.34 fuel=.. frames=.. [cause=..]"
	local outcome tval cause
	outcome="$(echo "$line" | sed -n 's/.*outcome=\([A-Z]*\).*/\1/p')"
	tval="$(echo "$line" | sed -n 's/.*[[:space:]]t=\([0-9.]*\).*/\1/p')"
	cause="$(echo "$line" | sed -n 's/.*cause=\([a-z_]*\).*/\1/p')"
	[ -z "$outcome" ] && outcome="ERROR"
	[ -z "$tval" ] && tval="0"
	[ -z "$cause" ] && cause="-"
	echo "$outcome $tval $cause"
}

# =============================================================================
# Run the grid. Results are accumulated into flat, index-addressed arrays
# (bash 3.2 on macOS has no associative arrays), index = level_i * NCFG + cfg_i.
# =============================================================================
# shellcheck disable=SC2206
LEVELS=($EVAL_LEVELS)
# shellcheck disable=SC2206
CONFIGS=($EVAL_CONFIGS)
NCFG=${#CONFIGS[@]}

declare -a WINS TIMEOUTS DEATHS ERRORS SUMT C_HAZARD C_FUEL C_CRASH
total_cells=$(( ${#LEVELS[@]} * NCFG ))
c=0
while [ "$c" -lt "$total_cells" ]; do
	WINS[$c]=0; TIMEOUTS[$c]=0; DEATHS[$c]=0; ERRORS[$c]=0; SUMT[$c]=0
	C_HAZARD[$c]=0; C_FUEL[$c]=0; C_CRASH[$c]=0
	c=$(( c + 1 ))
done

echo "[eval_matrix] build: $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "[eval_matrix] levels=[$EVAL_LEVELS] configs=[$EVAL_CONFIGS] N=$EVAL_N time_scale=$SIM_TIME_SCALE"
echo "[eval_matrix] this will run $(( total_cells * EVAL_N )) episodes; raw log -> $RAW_LOG"
START_TS=$(date +%s)

li=0
for level in "${LEVELS[@]}"; do
	ci=0
	for config in "${CONFIGS[@]}"; do
		idx=$(( li * NCFG + ci ))
		printf '[eval_matrix] L%-2s %-9s : ' "$level" "$config"
		ep=0
		while [ "$ep" -lt "$EVAL_N" ]; do
			set -- $(run_episode "$level" "$config")
			outcome="$1"; tval="$2"; cause="$3"
			case "$outcome" in
				WIN)
					WINS[$idx]=$(( ${WINS[$idx]} + 1 ))
					# accumulate WIN time (float) via awk; bash has no float math
					SUMT[$idx]=$(awk -v a="${SUMT[$idx]}" -v b="$tval" 'BEGIN{printf "%.4f", a+b}')
					printf 'W'
					;;
				DEATH)
					DEATHS[$idx]=$(( ${DEATHS[$idx]} + 1 ))
					case "$cause" in
						hazard)      C_HAZARD[$idx]=$(( ${C_HAZARD[$idx]} + 1 )) ;;
						out_of_fuel) C_FUEL[$idx]=$(( ${C_FUEL[$idx]} + 1 )) ;;
						*)           C_CRASH[$idx]=$(( ${C_CRASH[$idx]} + 1 )) ;;
					esac
					printf 'x'
					;;
				TIMEOUT)
					TIMEOUTS[$idx]=$(( ${TIMEOUTS[$idx]} + 1 ))
					printf '.'
					;;
				*)
					ERRORS[$idx]=$(( ${ERRORS[$idx]} + 1 ))
					printf '!'
					;;
			esac
			ep=$(( ep + 1 ))
		done
		wr=$(awk -v w="${WINS[$idx]}" -v n="$EVAL_N" 'BEGIN{printf "%.0f", (n>0? 100.0*w/n : 0)}')
		printf ' -> %s%% (%d/%d win)\n' "$wr" "${WINS[$idx]}" "$EVAL_N"
		ci=$(( ci + 1 ))
	done
	li=$(( li + 1 ))
done

END_TS=$(date +%s)
ELAPSED=$(( END_TS - START_TS ))
ELAPSED_MIN=$(awk -v s="$ELAPSED" 'BEGIN{printf "%.1f", s/60.0}')

# =============================================================================
# Emit the markdown report.
# =============================================================================
{
	echo "# Autopilot / RL eval matrix — ${DATE_UTC}"
	echo ""
	echo "- **Build:** \`$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)\` on \`$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo ?)\`"
	echo "- **Episodes per cell (N):** ${EVAL_N}"
	echo "- **SIM_TIME_SCALE:** ${SIM_TIME_SCALE} &nbsp;•&nbsp; **SIM_MAX_TIME:** ${SIM_MAX_TIME}s"
	echo "- **Runtime:** ${ELAPSED_MIN} min ($(( total_cells * EVAL_N )) episodes)"
	echo "- **Raw log:** \`${RAW_LOG}\`"
	echo ""
	echo "Cells show **win rate** (WIN = touched the target under landing speed)."
	echo ""

	# ---- header row ----
	printf "| Level |"
	for config in "${CONFIGS[@]}"; do
		printf " %s |" "$(config_label "$config")"
	done
	printf "\n"
	printf "|:---:|"
	for config in "${CONFIGS[@]}"; do printf ":---:|"; done
	printf "\n"

	# ---- win-rate body ----
	li=0
	for level in "${LEVELS[@]}"; do
		printf "| **L%s** |" "$level"
		ci=0
		for config in "${CONFIGS[@]}"; do
			idx=$(( li * NCFG + ci ))
			wr=$(awk -v w="${WINS[$idx]}" -v n="$EVAL_N" 'BEGIN{printf "%.0f", (n>0? 100.0*w/n : 0)}')
			printf " %s%% (%d/%d) |" "$wr" "${WINS[$idx]}" "$EVAL_N"
			ci=$(( ci + 1 ))
		done
		printf "\n"
		li=$(( li + 1 ))
	done

	# ---- mean time-to-land (WINs only) ----
	echo ""
	echo "## Mean time-to-land (WIN episodes, game-seconds)"
	echo ""
	printf "| Level |"
	for config in "${CONFIGS[@]}"; do printf " %s |" "$(config_label "$config")"; done
	printf "\n"
	printf "|:---:|"
	for config in "${CONFIGS[@]}"; do printf ":---:|"; done
	printf "\n"
	li=0
	for level in "${LEVELS[@]}"; do
		printf "| **L%s** |" "$level"
		ci=0
		for config in "${CONFIGS[@]}"; do
			idx=$(( li * NCFG + ci ))
			mean=$(awk -v s="${SUMT[$idx]}" -v w="${WINS[$idx]}" 'BEGIN{ if (w>0) printf "%.2f", s/w; else printf "—" }')
			printf " %s |" "$mean"
			ci=$(( ci + 1 ))
		done
		printf "\n"
		li=$(( li + 1 ))
	done

	# ---- failure-cause breakdown ----
	echo ""
	echo "## Failure causes (DEATH episodes, per cell)"
	echo ""
	echo "Buckets mirror the death forensics (rocket.gd:583-591): \`hazard\` (killed via"
	echo "\`globalvar.sendDeath\`), \`out_of_fuel\` (dry tank), \`crash\` (collision). \`TO\` = TIMEOUT,"
	echo "\`ERR\` = no parseable SIM_RESULT (import/launch failure)."
	echo ""
	printf "| Level | Config | hazard | out_of_fuel | crash | TO | ERR |\n"
	printf "|:---:|:---|:---:|:---:|:---:|:---:|:---:|\n"
	li=0
	for level in "${LEVELS[@]}"; do
		ci=0
		for config in "${CONFIGS[@]}"; do
			idx=$(( li * NCFG + ci ))
			printf "| L%s | %s | %d | %d | %d | %d | %d |\n" \
				"$level" "$config" \
				"${C_HAZARD[$idx]}" "${C_FUEL[$idx]}" "${C_CRASH[$idx]}" \
				"${TIMEOUTS[$idx]}" "${ERRORS[$idx]}"
			ci=$(( ci + 1 ))
		done
		li=$(( li + 1 ))
	done
	echo ""
	echo "_Generated by \`rl/eval_matrix.sh\`._"
} > "$EVAL_OUT"

echo ""
echo "[eval_matrix] done in ${ELAPSED_MIN} min. Wrote: $EVAL_OUT"
