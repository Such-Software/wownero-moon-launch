# RL pilot — state + plan (branch: `rl-training`)

Durable handoff doc (written 2026-06-21, context-limit safe). Company lessons live in
`~/src/docs/ml-pipeline-learnings.md` + `~/src/docs/harnesses/reinforcement-learning-game-agent.md`.

## BOT STRATEGY — 4 goals, the RL path (user-confirmed 2026-06-22)
**Make RL WORK. The opponent is the trained RL policy running LIVE in-game — NOT a fixed
ghost** (ghosts repeat = boring). Stochastic action sampling → it varies every run AND
reacts to live state (hazards' current positions, the player in a race) = genuinely
adaptive. Goals: (1) RL plays all levels, (2) optional in-game live adaptive opponent,
(3) gameplay videos, (4) balance tester. Fastest RL path, IN ORDER:
1. **PARALLEL ENVS — do FIRST (the compute unlock).** Export a headless macOS binary
   (run scene = `rl/train.tscn`) → `train_sb3.py` with `env_path` + `n_parallel=8-16`
   (per-env port = base+p). 5-10×+ throughput turns the per-level grind from weeks → days.
   Everything else depends on this.
2. **Finish end-to-end L1.** Blocker = the **TILT gate** (arrives tipped off the slingshot).
   Add tilt to the relaxed-threshold curriculum: make `TILT_DEATH_ANGLE` a var, relax
   90°→35° under `--capture` (same pattern as crashspeed/landingspeed) + keep the upright
   reward. That clears the last mechanical gate.
3. **Curriculum to the hazard levels (L2+).** Add hazard positions/velocities to the obs;
   per-level (or one multi-level) training with the parallel compute. Martian (chaser)
   first, then wormhole/solarwind/blackhole/mothership.
4. **ONNX in-game = the deliverable for all 3 uses.** Install the onnxruntime GDExtension
   (plugin `onnx/` has only stubs now), export policy→ONNX, run via Sync
   `control_mode=ONNX_INFERENCE` (`deterministic_inference=FALSE` → stochastic = varied
   opponent). Same policy: **in-game = the live opponent**, **Movie Maker = B-roll**,
   **headless = the per-level balance tester** (cross-ref real-player telemetry; bot ≠
   human difficulty, so it's a competent-pilot lower bound + new-content beatability check).
The heuristic bot + headless SimHarness stay only as the interim tester + fallback WHILE
RL trains. **RL is the opponent. Next build: parallel envs.**

## TL;DR
Reliable **landing SOLVED** (~70% from rest near the Moon). The **full natural Level 1**
(start near Earth → slingshot/escape → transit → land) is **NOT solved yet**. Next:
parallel-env compute, then a *task-preserving* curriculum on the natural start. Then
hazard levels (L2+), then ONNX export to run the pilot in-game (race mode + B-roll).

## LATEST experiment (live, 2026-06-21)
Full-L1 attempt: **natural Earth start** (`RL_EVAL=1`) + **landing-tolerance curriculum**
(`_land_tol` 110→40 as land-rate climbs) + upright obs. **Reward fix this run: proximity
must be rewarded INDEPENDENTLY** — `-10 + prox*(6 + slow*3 + upright*3)`. (Gating prox
behind slow+upright — `prox*(slow*5+upright*5)` — removed the approach gradient, so on
the natural start `closest_ever` stayed ~540 / never escaped Earth.) **STATUS: the Earth-escape/slingshot is SOLVED on natural L1** — 150k validation dropped
`closest_ever` 542 → **46** (reaches the Moon from the real start). The decoupling fix
worked. Remaining: it reaches the Moon but isn't landing yet (`wins=0` even at
`land_tol=110`) — needs to learn the *landing-from-transit* (harder than from rest, it
arrives fast). Now running a **longer 1M run, restored from the approach policy**
(`rl/moonlaunch_ppo_approach.zip`) to learn the touchdown. Watch `wins` climb +
`land_tol` drop 110→40. CONFIRMED: it reaches the Moon reliably (closest~47) but did NOT land even at
`land_tol=110` over 100k — landing-from-transit IS its own narrow-goal problem (arrives
fast off the slingshot, never stumbles into a win → no signal). **Current move:** start
`_land_tol` very high (**260** = "reach Moon upright = win") to seed the win signal, then
ratchet to 40 (`LAND_TOL_STEP=12`). Run restored from `moonlaunch_ppo_approach.zip`,
natural start. **Watch `wins` climb + `land_tol` drop 260→40.** If wins still 0 at high
land_tol, the blocker is the un-relaxable TILT (35°) requirement, not speed → the agent
must learn to arrive upright (it has the tilt obs + upright reward; may need more training
or a heavier upright term). The approach policy backup is safe regardless.

**+ Added (key lever): dense POTENTIAL-based landing-readiness shaping** — reward the
*increase* in `near*slow*upright` within 220px of the Moon (`(readiness-_prev)*3`).
Potential-based so it can't be hover-farmed; positive so no avoidance. This is the
descent gradient the terminal-only reward lacked (teaches "slow + straighten as you
near the Moon"). Running with this + land_tol 260→40 + restored approach policy.

**THE LANDING BUG (found 06-22): the crashspeed gate.** 1M run = 0 wins despite
land_tol=260 + readiness shaping. Cause: rocket.gd collision checks **crash-death
(`crash_speed > crashspeed`, crashspeed=100) BEFORE moonland** — the fast slingshot
arrival died on the crash check every time, so relaxing only `landingspeed` was inert.
Worse, `crash_speed = max(current, _recent_max_speed)` so the *peak* transit speed counts.
**Fix:** the curriculum now relaxes **both** `landingspeed` AND `crashspeed` (260→40).
Run restored from approach policy. **Watch wins finally climb.** LESSON: read the full
terminal-logic ORDER — a death check that fires before the win check makes the win
structurally unreachable; relaxing the win threshold alone does nothing.

**UPDATE: crashspeed fix still = 0 wins at 382k → the last gate is TILT.** Win also needs
`|tilt rel. Moon| < TILT_DEATH_ANGLE (35°)` else rollover-death — and that's a `const` in
rocket.gd, NOT relaxed by the curriculum. The fast slingshot arrival lands *tipped*. Next
levers (pick one): (a) heavily weight the upright term in the reward/readiness so it
learns to arrive upright; (b) make TILT_DEATH_ANGLE relaxable under `--capture` (needs it
as a var, not const) and add it to the curriculum (tilt-tol 90°→35°); (c) **pragmatic:
we already have TWO solved skills — the Earth-slingshot approach AND landing-from-rest
(~70%, reverse curriculum). Consider composing them (heuristic/approach to get near+slow,
RL or scripted for the upright touchdown) rather than forcing one policy to do the whole
fast-arrival-then-upright-land, which is a deep stack of mechanical gates.** Compute
(parallel envs) + time would also help. Two real wins banked; the full end-to-end combo
is the hard last mile.

## What works — keep these (the recipe)
- **Upright obs + terminal reward = THE breakthrough.** Obs (13-dim) includes **tilt
  relative to the Moon** (sin/cos) + **descent rate** (radial vel) — the win needs touch
  *slow AND upright* (tilt < ~35°), and the terminal reward gives partial credit for
  close+slow+upright. Without the tilt obs the agent is blind to the win condition and
  rolls over every time.
- **`Engine.time_scale` re-asserted every frame** (the rocket's slow-mo + death handlers
  reset it, silently killing the Sync speedup and shrinking physics dt).
- **Landing-mode 3D overlay gated off under `--capture`** (cosmetic SubViewport churned
  every episode → render jitter at the descent).
- **Reset fully respawns** (deferred spawn + grace frames + grab a *live* rocket); set
  BOTH `done` and `needs_reset` on a terminal or it trains on "corpses".
- Telemetry/scores gated off under `--sim`/`--autopilot`/`--capture` (no backend spam).

## The gap + the fix (our newest lesson)
The reverse curriculum spawned the rocket **at rest near the Moon, random direction** —
so it learned the touchdown but **never the Earth-escape/slingshot**. Eval on the
unmodified L1: **0 wins, closest_ever=550** (never leaves the start). Warm-start
fine-tuning on natural L1 crashes instantly (distribution mismatch).
**Fix (next experiment):** train on the **NATURAL Earth start** (`RL_EVAL=1`) with a
curriculum that **preserves the task** — relax the landing tolerance early (agent sets
`_rocket.landingspeed` high, shrinks to 40 as the windowed land-rate climbs), tighten
over time. Keep the upright obs. **Rule: a curriculum must preserve the real start
condition** (don't teleport to an unrealistic, easier start).

## Plan (in order)
1. **Parallel envs (the compute unlock, do FIRST).** Add a macOS export preset to
   `export_presets.cfg`, export a headless binary with `rl/train.tscn` as the run scene,
   then `train_sb3.py` with `env_path=<binary>` + `n_parallel=N` (per-env port = base+p).
   ~5-10× speed → experiments go from hours to ~15 min.
2. **Full natural-L1 experiment** — natural start (`RL_EVAL=1`) + landing-tolerance
   curriculum + upright obs. **SHORT validation runs first** (~100-150k steps), long only
   once the recipe is validated.
3. **Hazard levels (the dream)** — extend to L2+ (Martian chaser, then wormhole/etc.),
   curriculum per level. Obs likely needs hazard positions/velocities added.
4. **ONNX export + in-game** — needs the **onnxruntime GDExtension** (NOT installed; the
   plugin's `onnx/` has only `csharp`/`wrapper` stubs). Then Sync `control_mode =
   ONNX_INFERENCE` runs the policy in-game (race mode + Movie Maker B-roll capture).

## Process (don't repeat)
- **SHORT runs for tuning/debugging** — catch the signal in ~50-150k steps (minutes);
  go to 1M only once the recipe is locked. We wasted hours on full runs during tuning.
- **One variable per experiment.** Instrument; watch *leading* indicators (`closest_ever`,
  steps/episode, `recent_land`), not cumulative win-rate.

## Files + commands
- Agent: `rl/RocketAIController.gd` · scene: `rl/train.tscn` (`reset_after`, `speed_up`)
- Trainer: `rl/train_sb3.py` (PPO; `--timesteps`, `--restore`) · Eval: `rl/eval_sb3.py`
- Orchestration: `rl/run_train.sh <steps> [restore.zip]` · `rl/run_eval.sh <steps>`
  - prefix `RL_EVAL=1` → spawn at the NATURAL L1 start (no curriculum reposition)
- Monitor: `grep "\[RL\]" rl/logs/godot.log | tail` (eval → `godot_eval.log`)
- Policies (git-ignored): `rl/moonlaunch_ppo_landing.zip` (landing-from-rest ~70%),
  `rl/moonlaunch_ppo.zip` (latest)
- venv: `rl/.venv` (python3.13 + torch + sb3 + godot-rl) · plugin: `addons/godot_rl_agents/`
- If headless run errors "class not declared" (AIController2D/Sync): rebuild the class
  cache with `godot --headless --editor --quit-after 80`.
- All RL artifacts git- AND syncthing-ignored (`.venv`, `*.zip`, `*.onnx`, checkpoints).
