# Such Moon Launch: roadmap

Internal planning. Live state in [memory] + per-area READMEs; this is the durable
"what's next" list.

## v1.1.0 (next release)

- **Firebase telemetry migration.** The event-dup bug is **client-side** in
  `Telemetry.gd` (re-enqueue logic); fix it via the Firebase SDK rather than
  patching. Migrate standard product analytics (funnels, retention) to Firebase.
- **Enriched "death forensics" balance events** (do this in the *same* telemetry
  pass). The AI play-tester validated exactly which dimensions matter:
  `cause_type` (crash | hazard | out-of-fuel | timeout), `hazard_name`,
  `% through level` / `dist_to_target`, `speed_at_death`, `fuel_at_death`,
  `time_into_level`, `attempt_number`. Current `level_death` only logs a coarse
  cause (crash-body name).
- **Split sinks by data shape.** Firebase/GA4 for funnels + retention + the dup
  fix (bucket any balance fields, GA4 hates high-cardinality numeric). Keep/enrich
  our own `/v1/events` Postgres for the raw forensics (full SQL, no limits).
- **Remove the temporary remote ad-config flag** (`/v1/moonlaunch/adconfig`) once
  real-ad fill is stable; hardcode real ads.

## AI play-tester / pilot

- **Now:** heuristic phased controller, reliably wins **L1 + L3**, all headless
  (`game/test/`). Flight/gravity-assist/landing solved.
- **Ceiling hit:** reactive heuristic plateaus ~2/11; the Martian is a beatable
  contact-chaser but evasion makes it arrive too fast to land, and L5-11 have
  exotic hazards it can't model. See `game/test/README.md`.
- **Next rung (to beat all levels):** either predictive interception-avoidance +
  per-hazard handling, or **RL/ML** — and the headless sim harness is already a
  ready-made training environment (fast, parallel, parseable reward, no render).

## Race mode (future, depends on the bot)

- **Human vs robot.** First step = **ghost races** against a recorded bot run on a
  level (single-player, easy; `moonlaunch_scores` already stores per-level times).
- Later: live/async online PVP races. Requires the bot to clear all levels at
  human-competitive times first.

## Balance

- **Verify human-beatability per level from live completions** (do real players
  beat L2-11? answers whether levels are fair before we chase an all-levels bot).
- **The difficulty cliff is the Martian on every level from 2 onward** (bot + live
  funnel both point here). Consider softening L2's introduction of it.

## Marketing video system

- Built + proven end-to-end (`marketing/`): capture any scene -> ffmpeg -> 9:16 /
  1:1 / 16:9. 3D mascot stage is GLB-ready (Meshy).
- **To produce:** the AI-pilot short (needs Meshy Cosmonaut Doge + Martian GLBs +
  a music bed). Render only on demand (it opens a window; do it off the laptop).
