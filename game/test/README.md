# Autopilot + headless sim harness

A heuristic **autopilot** that flies the rocket, and a **headless harness** that
runs it through a level and reports the outcome. Two uses:

1. **Balance play-testing** — run levels headlessly (no window) and see whether a
   competent gravity-assist pilot can clear them, how fast, and with how much fuel.
2. **Promo B-roll** — drive the rocket during a Movie Maker capture so we get
   clean gameplay footage without a human at the controls.

It is *not* machine learning — it's a hand-tuned phased controller. RL would be
weeks of work for a job a few hundred lines of control logic does well enough.

## Files

| File | Role |
|------|------|
| `AutoPilot.gd` | The pilot. Autoload `AutoPilot`. Drives `ui_left/ui_right/thrust`. |
| `SimHarness.gd` | The harness. Autoload `SimHarness`. Runs one level, prints a result, quits. |
| `../net/Telemetry.gd` | Has a `--sim`/`--autopilot` guard so bot runs never log events. |
| `../net/ScoreClient.gd` | Same guard so bot runs never post to the leaderboard. |

Both autoloads are registered in `project.godot`. **Both are completely inert in
normal play**: `AutoPilot` disables its own processing unless it's a debug build
or `--autopilot` was passed; `SimHarness` disables itself unless `--sim` was
passed. Mobile and production builds never run a line of this. It drives the
rocket only through the same inputs a keyboard player uses, so `rocket.gd` itself
is unchanged.

## How the pilot works (AutoPilot.gd)

Three phases, chosen each physics frame from the rocket's own nav data
(`target`, `_all_gravity_bodies`, `linear_velocity`, `rotation`):

- **ESCAPE** — while within `escape_radius` of the nearest non-target body (the
  well the rocket launches in, e.g. Earth), point *radially outward* and thrust
  to climb out. The launch point is deep in that well; you have to get out before
  heading anywhere, or you fall back and (literally) go to sleep on the surface.
- **TRANSFER** — once clear, aim at the landing target, bending the heading away
  from any close non-target body (`avoid_*`) so we curve around intervening
  planets instead of flying through them.
- **APPROACH** — folded into TRANSFER. Within `approach_radius` the target speed
  eases from `seek_speed` down to `land_speed`. Because steering in TRANSFER aims
  at the *velocity correction* (`desired_vel - vel`), the nose automatically
  swings retrograde to brake when we're closing too fast — without that we blow
  past the target and orbit it forever.

Two non-obvious mechanisms that took the most debugging:

- **Cascaded orientation controller.** The rocket has torque 5000 / mass 5 — huge
  angular authority — so a plain proportional controller overshoots wildly and
  oscillates. Instead: outer loop turns heading error into a *desired turn rate*
  (→ 0 as you near the heading), inner loop bang-bangs torque to track that rate.
  Robust without needing the exact moment of inertia.
- **Keep-awake.** A `RigidBody2D` that comes to rest *sleeps*, and a sleeping body
  stops calling `_integrate_forces`, so our inputs would silently do nothing. The
  pilot sets `can_sleep = false` while active. (Only affects autopilot runs.)

## Running headless sims (SimHarness.gd)

No window, no Movie Maker, quits the instant the outcome is known:

```sh
godot --headless --autopilot --sim res://game/levels/1/Level1.tscn
# -> SIM_RESULT outcome=WIN level=1 t=12.34 fuel=44.0 frames=740
```

Outcomes: `WIN` (touched the target under landing speed), `DEATH` (crashed /
hazard), `TIMEOUT` (didn't resolve within the time budget).

Env knobs:

| Env | Default | Meaning |
|-----|---------|---------|
| `SIM_LEVEL` | scene's | Sets `globalvar.nowlevel` (upgrades/scaling/report). |
| `SIM_MAX_TIME` | 90 | Seconds of game-time before TIMEOUT. |
| `SIM_TIME_SCALE` | 1.0 | `Engine.time_scale`; >1 runs faster but hurts landing fidelity. Keep ≤1.5 for honest WIN/DEATH. |

Sweep a whole campaign:

```sh
for n in $(seq 1 11); do
  SIM_LEVEL=$n SIM_TIME_SCALE=1.5 \
    godot --headless --autopilot --sim res://game/levels/$n/Level$n.tscn 2>&1 \
    | grep SIM_RESULT
done
```

The pilot also prints a throttled trajectory line (`AP ESC/XFER ...`) every 30
physics frames — handy for seeing *why* a run failed (stuck, overshooting, etc.).

## Tuning the pilot

Every knob is overridable per-run via an `AP_*` env var, so you can sweep without
recompiling:

| Env / var | Default | Meaning |
|-----------|---------|---------|
| `AP_SEEK_SPEED` | 120 | Transfer cruise speed (px/s). Lower = easier to brake. |
| `AP_APPROACH_RADIUS` | 420 | Start easing speed down this far from target. Bigger = brake earlier. |
| `AP_LAND_SPEED` | 22 | Desired touchdown speed (must stay under rocket `landingspeed` = 40). |
| `AP_ANGLE_TOL` | 0.22 | Only thrust when heading error is within this (rad). |
| `AP_TURN_GAIN` | 4.0 | Desired turn rate per rad of heading error. |
| `AP_MAX_TURN_RATE` | 4.5 | Cap on desired turn rate (rad/s). |
| `AP_ESCAPE_RADIUS` | 320 | Climb radially until this far from the launch body. |
| `AP_RADIAL_BIAS` | 1.0 | Escape: weight of the straight-out component. |
| `AP_TANGENT_BIAS` | 0.0 | Escape: sideways lead for a prettier slingshot arc. 0 = pure radial (stable). |
| `AP_AVOID_RANGE` | 260 | Transfer: bend away from non-target bodies within this. |
| `AP_AVOID_GAIN` | 1.6 | Transfer: how hard to bend around them. |
| `AP_EVADE` | off | `1` enables chaser evasion (WIP, see ceiling below). |
| `AP_HAZARD_RANGE` | 210 | Evade: sidestep a chaser within this. |
| `AP_HAZARD_GAIN` | 1.5 | Evade: sidestep strength. |
| `AP_FLEE_SPEED` | 78 | Evade: don't slow below this while threatened (above Martian's 40). |
| `AP_SAFE_ZONE` | 130 | Evade: within this of the pad the Martian backs off; brake normally. |

Example: `AP_SEEK_SPEED=90 AP_LAND_SPEED=18 godot --headless --autopilot --sim ...`

`SIM_RESULT` reports a `cause=hazard|crash` on deaths (hazard = killed via
`globalvar.sendDeath`, i.e. Martian / black hole / etc.; crash = a collision).

## Capturing video

Movie Maker **must render**, so unlike the sims this opens a window (and macOS
focuses it). Launch it off-screen to keep it out of your face:

```sh
godot --path . --resolution 1280x720 --position 6000,6000 \
  --write-movie builds/video/L1_win.avi --autopilot --quit-after 1200 \
  res://game/levels/1/Level1.tscn
```

`--quit-after` is in frames (Movie Maker runs at 60 fps). The game changes scene
to Victory when the bot wins, so size `--quit-after` to land a little past the
touchdown. Telemetry and score submission are disabled under `--autopilot`, so
captures don't touch the backend either.

Then format with ffmpeg (the source is 16:9 1280x720):

```sh
# 16:9 native (YouTube / Twitter / Bluesky)
ffmpeg -y -i L1_win.avi -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart L1_16x9.mp4
# 1:1 square (feed) — center crop
ffmpeg -y -i L1_win.avi -vf "crop=720:720:280:0,scale=1080:1080" -c:v libx264 -pix_fmt yuv420p -crf 20 L1_1x1.mp4
# 9:16 vertical (TikTok / Reels / Shorts) — static center crop (rocket-follow crop is a TODO)
ffmpeg -y -i L1_win.avi -vf "crop=405:720:437:0,scale=1080:1920" -c:v libx264 -pix_fmt yuv420p -crf 20 L1_9x16.mp4
```

`builds/video/` is git-ignored.

## Current results & known ceiling

NORMAL difficulty, base upgrades: **reliably wins Levels 1 and 3** (the flight,
gravity-assist, and landing are solved). Levels 2+ all carry a **Martian** and the
maps escalate — L5 Wormhole, L6 SolarWind, L11 BlackHole + Mothership.

**What we learned chasing all-levels (the `cause=` diagnostic made this visible):**

- The **Martian is a `CharacterBody2D` chaser that kills on contact** (not a
  shooter) and **backs off within 120px of any pad**. We're faster than it (120 vs
  40), so in open space we beat its chase. With `AP_EVADE=1` the bot sidesteps it
  and reaches the pad on the near levels.
- But it then **arrives too fast to land** (blitzing past the brake point) — so
  the deaths flip from `cause=hazard` to `cause=crash`. Flooring the flee speed
  helps but the window is tight on varied geometry, and a blunt evasion *derails
  clean levels* (it cost us L3 until we gated it off).
- The far levels (5-11) also have **non-`CharacterBody2D` hazards** (wormhole,
  solar wind, black hole, mothership) the chaser-evasion doesn't even see.

Net: a **reactive heuristic does not robustly clear the hazard levels.** Getting
there needs predictive interception-avoidance + per-hazard handling (or ML) — a
real project, not a tuning pass. Evasion is therefore **off by default** (`AP_EVADE`)
so we keep the clean L1/L3 baseline, with all the knobs + diagnostics preserved for
a future run at it. Honest balance signal stands: the difficulty cliff is the
Martian landing on every level from 2 onward.

## Upgrade ideas (if we come back to this)

- **Hazard dodging** — reactive avoidance of projectiles / Martian / asteroids.
  The big one: it's what unlocks the hazard levels, but it's a real subsystem.
- **Prettier slingshot arc** — raise `AP_TANGENT_BIAS` for footage; needs a
  stability pass on the escape heading (that's why it's 0 by default).
- **Landing polish** — touchdowns are correct but a bit fast; tune the
  approach-speed profile (e.g. a sqrt stopping-distance curve) for gentler, more
  cinematic landings.
- **Rocket-following vertical crop** — track the rocket's screen position to drive
  a dynamic 9:16 crop instead of the static center crop.
- **Batch sweep script** — a small runner that grid-searches `AP_*` and tabulates
  win-rate / time / fuel per config.
