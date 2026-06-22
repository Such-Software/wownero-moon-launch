# RL pilot — state + plan (branch: `rl-training`)

Durable handoff doc (written 2026-06-21, context-limit safe). Company lessons live in
`~/src/docs/ml-pipeline-learnings.md` + `~/src/docs/harnesses/reinforcement-learning-game-agent.md`.

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
`land_tol` drop 110→40. If `wins` stays 0 with `closest_ever`~46 for a long stretch, the
landing-from-transit is its own narrow-goal problem → may need a descent-speed curriculum
(cap approach speed near the Moon, relax over training) or more obs.

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
