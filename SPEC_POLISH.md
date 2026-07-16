# SPEC: Polish, Onboarding & Promo Program (2026-07)

Implementation spec for the July 2026 polish push. Covers: controls onboarding (tilt
complaints), intro/tutorial overhaul, RL pilot smoothing + "beats all levels",
starfield/visual polish, video-pipeline quality, and (phase 2) talking characters in
promos.

**How to use this doc:** each Work Package (WP) is self-contained — an agent should be
able to implement one WP with only this doc + the referenced files. Line numbers were
verified 2026-07-16; if the file has drifted, grep for the quoted function/const names.
Run WPs in the waves listed at the bottom (they're grouped to avoid same-file conflicts).

---

## Global conventions (read before starting ANY WP)

1. **Save-schema changes** go through `globalvar.gd`: add the field to `get_save_data()`
   (~line 630) and `_apply_save_data()` (~line 684) **with a default for missing keys**
   — existing installs must load old saves cleanly. Never rename existing keys.
2. **Capture/headless gating**: any new popup, hint, or tutorial UI must be skipped when
   `"--capture"`, `"--autopilot"`, or `"--sim"` is in `OS.get_cmdline_args()` — copy the
   pattern at `game/gui/menu/Menu.gd:1076-1078`. Exception: honor an env override
   `SML_SHOW_HINTS=1` so promo videos can deliberately show hint UI.
3. **UI style**: all menu-adjacent UI is built in code. Reuse `_build_styled_popup()`
   and `BS.apply_space_style()` (see `Menu.gd`), match existing font sizes/colors.
4. **Analytics**: new funnel events go through `game/net/Analytics.gd` (GA4, bucketed)
   and/or `game/net/Telemetry.gd` (own backend, raw). Both are already disabled under
   capture flags centrally — do not add per-callsite gating.
5. **Commits**: plain messages, no AI-attribution footers.
6. **Verification**: desktop-run a scene with the Godot binary used by
   `marketing/lib/capture.sh` (default `/Applications/Godot.app/Contents/MacOS/Godot
   --path . <scene>`). Autopilot/headless verification: see `rl/run_eval.sh` and
   `game/test/SimHarness.gd` for the `--sim` runner and its `SIM_RESULT` output line.
   **Never background a Godot `--export-*` run** (it hangs; run exports foreground).
7. **Engine**: Godot 4.6.x, typed GDScript, tabs. Match surrounding style.

**Key shared state (for reference):**
- Control scheme (mobile): `globalvar.gd:36-38` — `enum ControlScheme { TILT, JOYSTICK }`,
  `control_scheme` (default TILT), persisted key `control_scheme`.
- Desktop control (NEW, added by WP-A1/A4): `enum DesktopControl { KEYBOARD, GAMEPAD }`,
  persisted `desktop_control` (default KEYBOARD). On desktop BOTH keyboard and gamepad
  inputs stay live at once; this setting only chooses which control HINTS/glyphs to show.
- Input-hint helper (NEW, added by WP-A1, used by B1/B6): `globalvar.active_input_hint()`
  returns one of `{KEYBOARD, GAMEPAD, TILT, TOUCH_JOYSTICK}` from platform + the two
  settings above. Every place that branches control-instruction text must use this
  helper instead of re-deriving `is_mobile`/`control_scheme` inline.
- First-run flags: `globalvar.gd:14-15` — `tutorial_shown` (L1 tutorial, set on first L1
  win in `game/gui/victory/Victory.gd:54-56`), `welcome_shown` (menu welcome popup).
- Tilt tuning consts: `globalvar.gd:40-74` (`TILT_SENSITIVITY 2.0`, `TILT_DEADZONE`,
  polarity consts). Tilt is applied in `game/rocket/rocket.gd:343-398`
  (`_integrate_forces`), calibrated via `_calibrate_tilt()` (rocket.gd:295).
- Mobile HUD/buttons are built at level load in `game/gui/MobileUI.gd:_setup_mobile()`
  (joystick visibility decided once at line ~97).

---

## WS-A — Controls & Settings

### WP-A1: First-run control picker (platform/device-adaptive)  (S, high priority)

**Problem:** tilt is the silent default; the existing toggle is buried in the Options
popup (`Menu.gd:678-714`). Players who hate tilt churn before finding it.

**Change:** extend the existing first-launch welcome popup
(`Menu.gd:_show_first_time_nickname_prompt`, lines 1072-1150, gated by
`globalvar.welcome_shown`). Add a control section whose CONTENT adapts to platform +
connected devices. Also add the `desktop_control` setting + `active_input_hint()` helper
described in the shared-state notes (persist `desktop_control`, convention #1). This WP
depends on WP-A4 for gamepad bindings to be *functional*, but A1 can land first — the
picker only sets the hint preference; both input paths work regardless.

**Two large tappable option cards, EQUAL visual weight — NO nudging one over the other**
(decision from John, 2026-07-16: do not bias the player). Selecting highlights the
chosen card and sets the relevant setting.

- **Mobile** (`OS.get_name() == "Android" or "iOS"`): "How do you want to steer?"
  - **📱 Tilt** — "Roll your phone to turn"   ·   **🕹 Joystick** — "On-screen stick"
  - No default selection, no skip: **Start Game stays disabled until one is picked**
    (both are one tap; nickname can still be blank). This is the anti-churn point —
    tilt must not be a silent default. Present them in a neutral order, equal styling,
    no "recommended" badge.
  - Sets `globalvar.control_scheme`.
- **Desktop WITH a gamepad connected** (`Input.get_connected_joypads().size() > 0` at
  popup time): "Choose your controls"
  - **⌨ Keyboard** — "Arrow keys + Space"   ·   **🎮 Gamepad** — "Stick + buttons"
  - Here keyboard IS a safe default (unlike tilt on mobile), so **pre-select Keyboard
    and leave Start enabled** — the player may just hit Start. Equal styling, no nudge;
    the pre-selection is a safe default, not a recommendation badge.
  - Sets `globalvar.desktop_control`. (Both inputs stay live; this picks hint glyphs.)
- **Desktop with NO gamepad**: popup unchanged — nickname only, no control section.
- Footer hint under any control section: "Change anytime in Options or Pause."
- On commit: existing behavior (`welcome_shown = true`, `save_game()`) plus fire a new
  analytics event `control_scheme_chosen` with the chosen style name
  (`tilt`/`joystick`/`keyboard`/`gamepad`) — this is how we learn the real split.
- Existing players (`welcome_shown` already true) are never shown this; their saved
  settings are untouched.
- Popup is already capture-gated (Menu.gd:1076-1078) — keep that.

**Acceptance:** fresh install (delete `user://savegame.json`) — mobile shows Tilt|Joystick
with Start disabled until one is picked and neither visually favored; desktop with a pad
plugged in shows Keyboard|Gamepad (Keyboard pre-selected, Start enabled); desktop with no
pad shows nickname-only; choice persists across restart; `--capture` runs never see the
popup.

### WP-A2: Live scheme hot-swap + pause-menu toggle  (S, high priority)

**Problem:** `MobileUI._setup_mobile()` evaluates joystick visibility once at level load
(`game/gui/MobileUI.gd:97`); switching schemes mid-game does nothing until reload. And
the moment of tilt frustration is mid-level, where there's no toggle at all.

**Change:**
1. Add a signal `control_scheme_changed` to `globalvar.gd`, emitted from a small setter
   whenever `control_scheme` is assigned (update the Options toggle at `Menu.gd:700-704`
   and WP-A1's picker to use it).
2. `MobileUI.gd` connects to it and updates `_joystick.visible` live.
3. `game/rocket/rocket.gd` — verify `_is_tilt_mode()` (lines 286-292) is evaluated per
   frame (it is, via `_integrate_forces`); trigger `_calibrate_tilt()` when switching
   *into* TILT mid-level so the baseline is fresh.
4. Add a **Controls** row to the in-game pause popup (`popupMenu` in
   `game/TextsIngame.tscn:75-106`, logic in `MobileUI.gd` — pause handling near lines
   216-220). Same cycle-button pattern as the Options popup, calls `save_game()`.
   Platform-aware: **mobile** cycles Tilt/Joystick (`control_scheme`); **desktop** cycles
   Keyboard/Gamepad (`desktop_control`) — show the desktop row only when
   `Input.get_connected_joypads()` is non-empty.
5. **Gamepad hotplug (desktop):** connect `Input.joy_connection_changed`; when a pad is
   first connected mid-session and `desktop_control` is still KEYBOARD, fire a one-time
   `HintService.show_hint("gamepad_detected", "Controller detected — switch to gamepad in Pause/Options")`
   (WP-B0 provides HintService). Refresh any visible control hints on the signal.

**Acceptance:** toggling in pause mid-Level-1 shows/hides the joystick immediately and
steering switches without a level reload; tilt baseline re-calibrates (no stuck turn);
on desktop, plugging in a controller surfaces the one-time hint and the pause Controls
row appears.

### WP-A3: Options expansion — tilt sensitivity + audio toggles  (M, medium priority)

1. **Tilt sensitivity**: convert `TILT_SENSITIVITY` (`globalvar.gd:42`) from `const` to
   `var tilt_sensitivity := 2.0` (keep a `const TILT_SENSITIVITY_DEFAULT := 2.0`).
   Update the reference in `rocket.gd` (tilt pipeline, lines 343-398). Persist it
   (convention #1). Add a slider (range 1.0–4.0, step 0.25) to the Controls section of
   the Options popup (`Menu.gd:678-714`), visible only when scheme == TILT.
2. **Audio toggles**: the game currently has NO audio settings (only per-node
   `volume_db`). Scope tightly: add two persisted bools `music_enabled`, `sfx_enabled`
   (default true). Create two audio buses ("Music", "SFX") in `default_bus_layout` or
   via `AudioServer` at startup in `globalvar.gd`; assign the background-music players
   (menu `introwavybgm`, level BGM — grep `AudioStreamPlayer` for `bgm`) to Music and
   everything else to SFX (bulk approach: set bus on the known music players, leave the
   rest on Master and mute SFX by muting Master-minus-music is NOT possible — instead
   assign SFX bus explicitly to the rocket/UI/pickup players; if that sprawls, limit v1
   to a Music toggle only and note it). Two checkboxes in Options.
3. **Desktop control display**: in the Options popup, on desktop, add a
   Keyboard/Gamepad cycle row bound to `desktop_control` (same pattern as the mobile
   Controls row at `Menu.gd:678-714`), shown only when `Input.get_connected_joypads()`
   is non-empty. Hint: "Keyboard and controller both work — this picks which button
   hints you see."

**Acceptance:** sensitivity slider changes steering response in-level immediately and
persists; music toggle silences/restores BGM at menu and in-level; desktop
Keyboard/Gamepad row appears only with a pad connected and drives the hint style; old
saves load with defaults.

### WP-A4: Gamepad input bindings (desktop)  (S, high priority — pairs with A1)

**Problem:** a controller can only *rotate* today — `ui_left`/`ui_right` keep Godot's
default joypad bindings, but every custom action (`thrust`, `revthrust`, `fire`,
`missile`, `laser`, `emp`, `self_destruct`, `quit`) is keyboard-only (verified in
`project.godot` `[input]`). So "Gamepad" in the A1 picker is meaningless until bindings
exist.

**Change (edit `project.godot` `[input]` section ONLY):** add `InputEventJoypadButton`
(and where natural `InputEventJoypadMotion` for triggers) events alongside the existing
keyboard events — do NOT remove the keyboard events (both stay live):
- `thrust` → bottom face button (`JOY_BUTTON_A` = 0) and/or right trigger
  (`JOY_AXIS_TRIGGER_RIGHT` = 5, positive).
- `revthrust` → right face button (`JOY_BUTTON_B` = 1) and/or left trigger
  (`JOY_AXIS_TRIGGER_LEFT` = 4).
- `fire` → left face button (`JOY_BUTTON_X` = 2) or right shoulder (`JOY_BUTTON_RIGHT_SHOULDER` = 10).
- `missile` → top face (`JOY_BUTTON_Y` = 3); `laser` → left shoulder
  (`JOY_BUTTON_LEFT_SHOULDER` = 9); `emp` → click of a stick or a shoulder — pick
  sensible distinct buttons, document the mapping in a comment block or in
  `docs/` / the Help gamepad text.
- Pause → `JOY_BUTTON_START` (6) (wire wherever Escape is handled, `MobileUI.gd:216-220`
  — but that's a MobileUI edit; if it collides with the A-agent's MobileUI ownership,
  hand it to the A-agent via cross_file_needs and keep A4 to project.godot only).
- Leave `ui_left`/`ui_right` as-is (they already carry joypad defaults for rotate); if
  you want an explicit left-stick-X binding, add it without removing the built-ins.
- **Match the exact `Object(InputEventJoypadButton, ...)` serialization Godot 4.6 uses**
  — the safest path is to open the project's Input Map in the editor mentally / copy the
  field order from an existing `InputEventKey` block and swap the type; each action's
  `"events"` array just gains another entry. Keep `"deadzone": 0.5`.

**File-ownership note:** `project.godot` is edited by WP-B0 (`[autoload]`) in Wave 1;
A4 edits a DIFFERENT section (`[input]`) and runs in Wave 2 after B0 merges — no overlap,
but never run concurrently with B0.

**Acceptance:** headless import is clean (`Godot --headless --path . --quit-after 2`);
with a controller connected, thrust/reverse/fire map to buttons and rotate works on the
stick. **Real feel requires a physical gamepad — flag for John's manual check**; static
acceptance is: input map parses, all actions retain their keyboard events, new joypad
events present.

---

## WS-B — Onboarding & Teaching

### WP-B0: `HintService` autoload  (S, high priority — blocks B3/B4)

A tiny singleton consolidating the four hand-rolled toast/label patterns
(`rocket.gd:763-789` bounce toast, `rocket.gd:923-991` floating labels,
`Level1.gd:32-116` tutorial label, `Menu.gd:1759` menu toast).

**API:**
```gdscript
HintService.show_hint(id: String, text: String, duration := 4.0) # one-time, keyed
HintService.toast(text: String, duration := 3.0)                 # always shows
HintService.was_shown(id: String) -> bool
```
- One-time hints record `id` into a persisted `seen_hints: Array[String]` in the save
  (convention #1); reset with Reset Progress (`globalvar.gd:749-750` area).
- Visual: a single top-center banner label styled exactly like the L1 tutorial label
  (`Level1.gd:36-46`: size 24, green `Color(0.4,1.0,0.6)`, shadow), HOLD→FADE like the
  Level1 state machine. Queue if multiple hints fire at once — never overlap.
- Lives on its own `CanvasLayer` (high layer index) so it works in any scene.
- Suppressed under capture flags unless `SML_SHOW_HINTS=1` (convention #2).
- Register as autoload in `project.godot` after `globalvar`.
- Fire analytics `hint_shown(id)` (bucketed, Analytics.gd).

**Acceptance:** calling `show_hint("test", ...)` twice across a restart shows it exactly
once; toast queues don't overlap; no visual during `--capture` runs.

### WP-B1: Action-gated Level 1 tutorial + coach marks  (M, highest onboarding priority)

**Problem:** the L1 tutorial (`game/levels/1/Level1.gd:32-116`) is a timer-driven
message loop (4s hold → fade → next) that advances regardless of player behavior.

**Change:** rewrite the step engine so each step **waits for the thing it teaches**.
Message text is chosen by `globalvar.active_input_hint()` (WP-A1) across FOUR styles —
`TILT`, `TOUCH_JOYSTICK`, `KEYBOARD`, `GAMEPAD` — replacing the current two-way
mobile/desktop branch in `_build_tutorial_messages` (`Level1.gd:55-80`):

| # | Message per input-hint style | Advance when |
|---|---|---|
| 1 | "Welcome, Pilot!" (all) | 2s timer (title beat) |
| 2 | tilt/joystick: "Hold THRUST to fly up" · keyboard: "Press UP to thrust" · gamepad: "Press Ⓐ / right trigger to thrust" | `Input.is_action_pressed("thrust")` held ≥ 0.5s |
| 3 | tilt: "Tilt phone LEFT / RIGHT to turn" · joystick: "Use the joystick to rotate" · keyboard: "LEFT / RIGHT to rotate" · gamepad: "Left stick to rotate" | cumulative rotation input ≥ ~0.5 rad of turn |
| 4 | tilt/joystick: "Tap REVERSE to slow your descent" · keyboard: "Press DOWN for reverse thrust" · gamepad: "Press Ⓑ / left trigger for reverse" | `revthrust` pressed ≥ 0.3s |
| 5 | "Slingshot! Swing around Earth…" (all) | slingshot detected (see below) OR 20s fallback |
| 6 | "Don't fly straight at it…" | merged into 5's hold text — drop as separate step |
| 7 | "Land slowly and upright on the Moon!" (all) | shows when within ~600px of Moon; stays until landing mode activates |

- **Slingshot hook:** rocket already detects a slingshot (gold `SLINGSHOT! +N` label,
  `game/rocket/rocket.gd:940-991`). Add a `slingshot_achieved` signal on the rocket (or
  a group broadcast) and connect from Level1.
- Steps that wait on input should re-pulse the message (gentle alpha pulse) rather than
  fade out, and each waiting step gets a **stall nudge**: if no qualifying input for
  10s, re-show the message with a subtle shake.
- **Coach marks** (adapt to `active_input_hint()`): while step 2/4 waits, pulse-scale
  the matching on-screen button on touch (`MobileUI.gd` — `_thrust_btn`/`_reverse_btn`,
  lines 99-115; add a getter or a `highlight(btn_name, on)` method). Step 3: `JOYSTICK`
  pulses the joystick; `TILT` shows a small phone-tilt icon wobble (a Label with "📱↔"
  is fine v1); `KEYBOARD`/`GAMEPAD` desktop styles need no on-screen button highlight
  (skip coach marks, the text carries it).
- Keep: only when `not globalvar.tutorial_shown` and not race mode (`Level1.gd:25-29`);
  flag still set on first L1 victory (`Victory.gd:54-56`).
- Analytics: `tutorial_step(step_index)` on each advance — this gives the funnel.
- Input style can change mid-tutorial (WP-A2 scheme toggle, or a gamepad hotplug):
  rebuild the message text on `control_scheme_changed` / `Input.joy_connection_changed`.

**Acceptance:** on a fresh save, each step visibly waits for its action (verified by
playing on desktop with keys); slingshot step advances on an actual slingshot; the whole
sequence never soft-locks (fallbacks fire); `--capture --autopilot` L1 renders show no
tutorial UI.

### WP-B2: Off-screen target arrow  (S, high priority)

**Problem:** nothing points at the destination during 2D flight; guidance is proximity
beeps (`rocket.gd:459-468`) plus the landing overlay only once close.

**Change:** new `game/gui/hud/TargetArrow.gd` + instancing from `MobileUI.gd` (it
already builds the rest of the HUD, lines ~196-205):
- Reads the rocket's current `target` (same reference used by the death forensics at
  `rocket.gd:579` and the beeps). Every frame: if the target is **off-screen**, draw a
  small chevron at the screen edge along the direction to the target, with distance in
  px rounded to 10s (e.g. "▲ MOON 1240"); if on-screen, hide.
- Style: thin, semi-transparent (~60% alpha), the level-target accent color; must not
  read as a gameplay object. Fade out entirely when landing mode is active
  (`game/rocket/LandingMode.gd` sets its own overlay).
- Show on all levels. (It also helps videos: the arrow telegraphs intent in B-roll.)
- Respect waypoint/checkpoint targets if the target node changes mid-level (L5+).

**Acceptance:** L1 fresh run — arrow points to the Moon whenever it's off-screen,
disappears on-screen and in landing mode; works after a wormhole/waypoint target swap
(spot-check L5 or L8).

### WP-B3: Death-cause advice on the death screen  (S, high priority)

**Problem:** `DeathScreen.gd` shows "MISSION FAILED" + retry buttons, zero teaching.
All the forensics already exist at death time: `rocket.gd:575-610` computes
`cause_type` ("crash" / "hazard" / "out_of_fuel"), `hazard_name`, `speed`, `fuel_frac`,
`dist_to_target`, `attempt`, `pct_through`.

**Change:**
1. In `rocket.gd`, right where the forensics dict is built (line ~596), also stash it:
   `globalvar.last_death = { ...same fields... }` (transient var, NOT persisted).
2. In `game/gui/death/DeathScreen.gd` (layout at lines 54-75), add one advice `Label`
   (wrapped, ~13px, soft yellow) between the subtitle and the separator, chosen from
   `globalvar.last_death`:
   - `crash` + `speed` > safe-landing threshold → "Came in at %d px/s — safe touchdown
     is under 40. Feather REVERSE on approach." (Read the real thresholds from wherever
     `LandingMode.gd`/rocket define them — Help claims safe 40 / crash 100 px/s; use the
     actual consts, don't hardcode.)
   - `crash` on a non-target body → "You hit %s. Use short thrust bursts to adjust
     course early — gravity does the rest."
   - `out_of_fuel` → "Ran dry. Thrust in bursts, coast between them, and grab fuel
     canisters."
   - `hazard` → per-hazard one-liners keyed by `hazard_name` (Martian: "Martians chase —
     outrun them or fire back."; BlackHole: "Black holes pull hard — keep your distance
     and speed."; SolarWind, Wormhole, Mothership, GammaRay, Asteroid similar; write the
     table in a const dict).
   - Fallback: generic "Slow, upright, and patient wins."
3. Escalation: if `attempt >= 3` on the same level, append "Tip: upgrades in the Shop
   make this easier." (shop is the monetization loop — gentle, once per screen).

**Acceptance:** die three ways on desktop (crash fast into Moon, run out of fuel, hit a
Martian on L2) — each shows the matching line; no advice row if `last_death` is empty
(e.g., self-destruct edge case) rather than a crash.

### WP-B4: First-encounter hazard banners  (M, medium priority — needs B0)

One-time `HintService.show_hint()` per hazard **type** the first time the player meets
it, replacing the need to pre-read Help page 7 (`Help.gd:417-450` has the canonical
descriptions — source the copy from there, shortened to one line):
- Trigger: on level start, for each hazard type present in the scene (Martians node,
  GammaRay, Asteroid spawner, Nebula, SolarWind, BlackHole, Wormhole, Mothership — the
  hazard escalation per level is L2 Martian, L3 gamma, L4 asteroid, L6 solar wind, L7
  nebula, L8 wormhole, L9 black hole, L11 mothership), fire
  `show_hint("hazard_martian", "MARTIANS — they chase! Outrun them or fire back")` etc.
  Stagger multiple new hazards 5s apart (HintService queue handles it).
- Implementation: a small helper in a shared level script or autoload that scans
  `get_tree()` groups at level `_ready` — prefer group tags (`is_in_group("hazard")`
  already exists, see `rocket.gd:586`) + node-name mapping over per-level edits.
- Weapons counterpart: when a weapon button first appears (upgrade purchased,
  `MobileUI.gd:118-162`), one-time hint for it ("MISSILE armed — tap 🚀 to fire").

**Acceptance:** fresh save, play L1→L2 — Martian banner appears once on L2, never
again (including after death/retry); banners never show under `--capture` (unless
`SML_SHOW_HINTS=1`).

### WP-B5: "Watch demo" after repeated L1 failures  (M, medium priority)

The heuristic AutoPilot already beats L1. Offer it as a live demo:
- On `DeathScreen`, when `globalvar.nowlevel == 1` **and** `globalvar.level_attempt >= 3`
  **and** `not globalvar.tutorial_shown`: add a "🤖 Watch a demo flight" button.
- Pressing it restarts L1 with the autopilot flying: add a `start_demo()` method to
  `game/test/AutoPilot.gd` mirroring `start_race()` (lines ~373-392) — note `_ready()`
  disables physics processing in non-debug builds without `--autopilot`
  (AutoPilot.gd:84-88), so `start_demo()` must re-enable `set_physics_process(true)` and
  set `active = true` with global-Input routing (`direct_control = false`).
- Overlay a persistent banner: "AUTOPILOT DEMO — tap anywhere to take over". Any touch /
  key press calls a `stop_demo()` that releases all inputs (`_release_all()`,
  AutoPilot.gd:339-341) and hands control back without restarting.
- Demo completion does NOT set `tutorial_shown`, does not submit scores/telemetry rows
  as a real run: check how victory/score submission is gated and gate demo mode the
  same way capture runs are (grep the `--capture` gates in `rocket.gd:711`,
  `ScoreClient.gd:38`) — a `globalvar.demo_mode` transient flag checked in those spots
  is acceptable.
- Analytics: `demo_watched` event with `took_over: bool`.

**Acceptance:** die 3× on L1 with a fresh save → button appears; demo flies and lands;
tapping mid-demo returns control instantly; no leaderboard/score submission from a demo
run; victory during an untouched demo returns to the death/menu flow without marking
level progress.

### WP-B6: Help quick-start restructure  (S, low priority)

`game/gui/help/Help.gd` is a 12-page text guide that front-loads endgame content.
- Rewrite page 1 as **"Quick Start"**: three short sections — Launch (thrust + turn),
  Slingshot (arc around Earth, don't aim straight), Land (slow + upright + hold 3s) —
  sourced from the existing Controls/Landing/Slingshot pages, ≤8 lines total, BBCode
  colored like the rest (`_style()`, Help.gd:185-195).
- Reorder `PAGE_TITLES` (Help.gd:7-20): Quick Start, Controls, Landing, Fuel,
  Hazards, Slingshots/Waypoints, then the meta pages (Upgrades, Weapons, Crypto,
  Difficulty, Stars/Scoring, Leaderboard, Skins).
- No new systems; text-only change. Keep page count and swipe/keys/ESC navigation
  working (nav code at Help.gd:198-224).
- **Controls page**: the existing page describes keyboard + mobile only. Add a
  **Gamepad** subsection listing the WP-A4 button map, and where the page currently
  hardcodes which controls to show, drive it off `globalvar.active_input_hint()` so the
  *most relevant* scheme is shown first (Quick Start and Controls both lead with the
  player's actual style, other styles below).

**Acceptance:** Help opens on Quick Start; all pages reachable; counter shows the new
order; gamepad controls documented; the active input style is surfaced first; no BBCode
rendering glitches.

---

## WS-C — RL pilot & "beats all levels"

### WP-C1: Fix RL deploy twitch — action repeat + deterministic capture  (S, do first)

**Root cause (verified):** training uses `action_repeat = 8` (`rl/train.tscn:11` — one
action held 8 physics ticks) but deployment re-queries the policy **every physics
frame** and **samples stochastically** by default: `AutoPilot.gd:_rl_drive` (lines
326-336, called from `_physics_process`), `_rl_deterministic := false`
(AutoPilot.gd:63). Result: the thrust bit re-rolls at 60 Hz → engine flicker, and the
policy runs out-of-distribution.

**Change (in `game/test/AutoPilot.gd`):**
1. Add `const RL_ACTION_REPEAT := 8` and a frame counter; in `_rl_drive`, only call
   `_policy.predict()` every 8th physics frame and **hold** the pressed/released state
   between decisions. Reset the counter on handoff entry so the first frame decides.
2. Keep temperature/stochastic sampling as the *personality* mechanism (it's what makes
   `rookie`/`cowboy` land differently, AutoPilot.gd:71-76) — the repeat alone removes
   the 60 Hz flicker.
3. In `marketing/lib/render_remote.sh` (and document in `marketing/README.md`): default
   `SML_RL_DETERMINISTIC=1` for capture unless the storyboard explicitly wants variance.

**Acceptance:** with `SML_RL_LAND=1`, thrust toggles at ≤ ~8 Hz (log action changes per
second, or eyeball a rendered clip — exhaust no longer strobes); run the landing eval
(`rl/run_eval.sh` / `rl/eval_sb3.py`) before/after — success rate must be **≥ baseline**
(expect improvement; if it regresses >5 points, report, don't merge).

### WP-C2: Per-level eval matrix  (S, blocks C3/C4)

Build the measurement before more tuning. New `rl/eval_matrix.sh`:
- For each level 1-11 × {AP_EVADE off, AP_EVADE=1} × {heuristic landing, SML_RL_LAND=1}:
  run N=20 headless `--sim` episodes (see `game/test/SimHarness.gd` + `rl/run_eval.sh`
  for the invocation pattern and the parseable `SIM_RESULT` line; time-scale up with the
  existing `SIM_TIME_SCALE` knob).
- Parse results into a markdown win-rate table written to `reports/eval_matrix_<date>.md`
  (repo already has `reports/`), rows=levels, columns=configs, plus mean time-to-land.
- Also log per-episode failure causes if `SIM_RESULT` carries them (it should — check;
  if not, extend SimHarness to print cause_type from the same forensics used at
  `rocket.gd:583-591`).

**Acceptance:** one command produces the full table on the current build; document
runtime; wire nothing into CI yet.

### WP-C3: Hazard-aware transit — autopilot beats all 11 levels  (M/L)

**Do after C2.** The evasion scaffolding already exists: `avoid_range`, `avoid_gain`,
`hazard_range`, `hazard_gain`, `flee_speed`, `safe_zone`, and an `AP_EVADE` env toggle
(AutoPilot.gd:99-106). The known ceiling (header comment, AutoPilot.gd:20-23) is the
Martian + stacked hazards from L2+.

- Start from the C2 matrix with `AP_EVADE=1`: identify which levels fail and why.
- Tune/extend the evasion: likely gaps are (a) Martian *projectiles* (missiles) not
  tracked, only the body; (b) no arbitration when evasion pulls into the gravity well;
  (c) black-hole avoidance needing a hard keep-out radius rather than a gain. Iterate
  with `AP_*` env overrides first (no code), then bake improved defaults / new logic.
- Target: **≥80% win rate on every level 1-11** with `SML_RL_LAND=1` deterministic
  (good enough for video takes with a retry loop; 100% not required).
- Re-run C2 matrix and commit the updated table to `reports/`.

**Acceptance:** the committed before/after matrix shows ≥80% on all 11 levels; a
`render_remote.sh` capture of L9 or L10 completes with a landing on ≤3 takes.

### WP-C4 (stretch, research): RL transit with hazard observations

Only if C3 stalls or for the "pure RL beats the game" story. Extend the 15-dim obs
(`rl/RocketAIController.gd:210-222`) with nearest-hazard channels (offset, velocity,
type one-hot), domain-randomize hazard count/placement in `rl/train.tscn`, curriculum
from 0→N hazards. Reference: `~/src/docs/harnesses/reinforcement-learning-game-agent.md`
and `rl/PLAN.md` (whose reverse-curriculum + gate approach is proven here). Keep the
Hybrid Handoff (transit policy hands off to the existing landing policy at 220px,
`AutoPilot.gd:59`). Out of scope for the polish push — separate branch.

---

## WS-D — Visual polish

### WP-D1: Starfield twinkle v2  (S, high priority)

**Problem:** stars technically twinkle (`game/starfield.gdshader:46`) but
`twinkle_speed = 1.5` rad/s ⇒ a full sine cycle takes ~4.2s, ampl. 0.5-1.0 — reads as
static in a 15s clip, and the 60→30fps + crf-20 re-encode flattens it further.

**Change (in `game/starfield.gdshader`; params set in `game/ParallaxBackground.tscn`):**
1. Per-star speed variance: scale the twinkle arg by `(0.6 + 1.2 * hash(cell + 0.3))`
   so stars desynchronize in *rate*, not just phase.
2. Sharpen the waveform for the near layer: `twinkle = pow(0.5 + 0.5*sin(...), k)` with
   k≈2-3 — dwell-dim then flash, which reads as "blinking".
3. Add a sparkle pop: for ~10% of stars (`hash(cell+0.5) > 0.9`), add a second
   high-frequency component (`0.5 + 0.5*sin(TIME * 6.0 + phase)`) multiplied in — an
   occasional bright glint.
4. Raise default `twinkle_speed` 1.5 → 2.5 (uniform range already 0.1-5.0).
5. Keep it cheap: no new textures, no branching beyond the existing density early-out.
6. Bump `shader_parameter/twinkle_speed` in `ParallaxBackground.tscn` accordingly.
   NOTE: this .tscn has uncommitted comment-stripping edits — coordinate with the repo
   owner's working tree; don't revert their diff.

**Acceptance:** run L1 on desktop — stars visibly blink within any 5s window at
1x speed; render 10s via `marketing/lib/render_remote.sh 1 10` and confirm twinkle
survives the assembled MP4 (this also validates the E-pipeline); GPU cost unchanged
(it's the same per-pixel work).

### WP-D2: Animated starfield on menu/UI screens  (S, medium priority)

Menu, Victory, RaceResult, and Help use a **static JPG** (`art/backgrounds/starfield.jpg`
in `game/gui/menu/Menu.tscn:3`, `game/gui/victory/Victory.tscn:4`,
`game/gui/race/RaceResult.tscn:4`, `game/gui/help/Help.tscn`). Replace each background
`TextureRect` with a `ColorRect` + the starfield `ShaderMaterial` (same setup as
`game/ParallaxBackground.tscn`'s Starfield node — full-rect anchors suffice here since
these are static screens, no camera). Keep node names so scripts referencing
`Background` still resolve. Check draw order (background must stay behind the animated
menu ships, `Menu.gd:95-109`).

**Acceptance:** all four screens show the animated field; menu FPS unchanged on a phone
(shader is already running in every level, so this is strictly not-worse); web export
sanity check (shader compiles on WebGL — run the web preset or confirm `canvas_item`
shader features used are GLES3-safe; they are — no derivatives/textureLod).

### WP-D3: Thrust particle ramp  (S, medium priority)

Binary thrust makes exhaust strobe (worst with the RL pilot, still harsh for humans).
In `game/rocket/rocket.gd` where thrust state toggles the particle nodes (`RearThrust`,
`RevThrust`, `ExhaustTrail` — authored in `game/rocket/Rocket.tscn:180-235`): instead of
hard `emitting = true/false`, tween `amount_ratio` (Godot 4.x GPUParticles2D) up over
~0.08s and down over ~0.25s, keeping `emitting = true` while ratio > 0. Audio: if the
thrust loop hard-cuts, apply the same short fade to its volume_db. Physics unchanged —
this is strictly visual/audio.

**Acceptance:** tapping thrust rapidly on desktop produces smooth exhaust swell/decay
instead of strobing; capture a 5s clip with the RL lander (`SML_RL_LAND=1`, before C1
lands if parallel) and confirm the engine no longer flickers frame-to-frame.

---

## WS-E — Video pipeline quality

### WP-E1: 1080p / 60fps end-to-end  (S, high priority)

Today: capture hardcodes 1280x720 (`marketing/lib/render_remote.sh:58`; `capture.sh:25`
default `MK_RES=1280x720`), and `assemble.sh:42-47` normalizes to 1280x720 **30fps** —
then the 1:1/9:16 socials crop 720px and *upscale* to 1080 (`assemble.sh:96-99`).

- `capture.sh`: default `MK_RES=1920x1080`.
- `render_remote.sh`: `--resolution 1920x1080` (make it `${MK_RES:-1920x1080}`).
- `assemble.sh`: normalize at `1920x1080`, `fps=60` (make both env-overridable:
  `MK_OUT_RES`, `MK_FPS`); crops become `crop=1080:1080:420:0` for 1x1 and the 9:16 path
  crops `608:1080` → scale `1080:1920` **or** pads — keep current framing semantics,
  just at full resolution. Audio/codec settings unchanged (`crf 20`, `+faststart`).
- Update the stale `--position 6000,6000` note in `marketing/README.md:73-74` (the
  override.cfg minimized-window approach in capture.sh:48-52 is current) and document
  the new env knobs.
- Mind remote render time: 1080p60 under lavapipe is ~2-3× slower — note expected
  duration in the README; `GODOT_DRIVER=opengl3` fallback exists.

**Acceptance:** `render_remote.sh 1 10` produces a 1080p60 16:9 and 1080x1080 /
1080x1920 outputs with no upscaling step (verify with `ffprobe`); old invocations
still work (env defaults only).

### WP-E2: Native portrait 9:16 capture  (M, medium priority)

Cropping landscape gameplay wastes the vertical format. `~/src/such-graphics` already
solved this for this game: `scripts/capture-wownero-gameplay.py` (temporary marketing
camera, native portrait) plus `scripts/godot/marketing_camera_overlay.gd` and
`marketing_slingshot_pilot.gd`. Task: evaluate and integrate the simplest path —
either (a) call the such-graphics script from `marketing/lib/` for portrait takes, or
(b) port its marketing-camera approach into this repo as `SML_PORTRAIT=1` +
`--resolution 1080x1920` in `render_remote.sh` (HUD anchors must be checked at portrait
aspect — MobileUI positions by viewport size, `MobileUI.gd:89-115`, so it should
adapt; verify). Document the chosen path in `marketing/README.md`.

**Acceptance:** one command yields a native 1080x1920 gameplay clip of L1 with usable
framing (rocket + target in frame through the slingshot), HUD not clipped.

### WP-E3: Deterministic takes  (S, medium priority)

Captured runs aren't reproducible: `globalvar.gd:268,621` call `rng.randomize()`,
`WarpTunnel.gd:246` seeds from wall-clock, RL sampling is stochastic by default.
- Add `SML_SEED` env: when set (or when `--capture` is present), seed Godot's global
  RNG and the `globalvar` RNGs with it (default seed 1337 under capture), and make
  `WarpTunnel` use it.
- `SML_RL_DETERMINISTIC=1` default under capture (coordinate with WP-C1 which touches
  the same line in `render_remote.sh` — same wave or same agent).
- Document: "same command ⇒ same take" in `marketing/README.md`, with the caveat that
  physics timing is already fixed by Movie Maker's fixed timestep.

**Acceptance:** two consecutive `render_remote.sh 1 10` runs with `SML_SEED=42` produce
frame-identical (or visually indistinguishable — compare a few extracted frames) clips.

### WP-E4: QA render + twinkle verification  (S, after D1+E1)

- Render the standard 10s L1 clip through the full remote pipeline; check with
  `such-graphics video-qa` (see `~/src/docs/harnesses/video-generation-harness.md` for
  invocation) plus manual check: stars blink, no strobing exhaust, arrow/HUD legible at
  1080p.
- Add a `marketing/lib/qa_clip.sh` one-liner wrapping this so it becomes the smoke test
  after any visual change.

**Acceptance:** committed `qa_clip.sh`; a passing QA note (or found issues filed in
TODO.md) for the current build.

---

## WS-F — Phase 2: talking characters in promo (cross-repo, after A-E)

Context: `~/src/such-graphics` has implemented-but-unwired modules — `lipsync.py`,
`puppet.py` (named-group SVG puppets, `examples/puppets/sprout.svg` + `broccoli.svg`),
`dialogue.py` (multi-speaker, cached VO), `subtitles.py` — per
`docs/architecture/talking-characters.md` ("one alignment, three consumers"; ship
`performance.json`). **Nothing calls them end-to-end yet.**

- **WP-F1** (in such-graphics): a CLI driver — script in → VO synth + alignment →
  `performance.json` → puppet + subtitle render → transparent-background clip out.
  Follow the design doc; smallest path is the 2D parametric tier.
- **WP-F2** (this repo): "mission control commentator" promo format — a puppet clip
  composited (corner overlay) onto autopilot gameplay via `assemble.sh` (needs an
  overlay step: `ffmpeg -filter_complex overlay` with alpha — extend assemble or add
  `marketing/lib/overlay.sh`). Storyboard it in `marketing/videos/mission_control/`.
- **WP-F3**: real assets — Meshy GLB mascot(s) into `marketing/assets/characters/`
  (Stage3D at `marketing/stage/Stage3D.gd` currently renders a placeholder box), music
  bed + VO dirs (`marketing/assets/{music,vo}/`), per
  `~/src/docs/harnesses/video-generation-harness.md`.

Acceptance criteria TBD when phase 2 starts — do not block A-E on this.

---

## Execution plan (waves = parallel-safe groups)

**File-contention map (the reason for the waves):**
- `Menu.gd`: A1, A3 (D2 touches Menu.tscn only — OK alongside with care)
- `globalvar.gd`: A1 (desktop_control + active_input_hint helper), A2 (signal), A3 (vars), B0 (seen_hints), B3 (last_death) — all small; within a wave, ONE agent owns globalvar edits or they run in different waves
- `project.godot`: B0 (`[autoload]`, Wave 1), A4 (`[input]`, Wave 2) — DIFFERENT sections, DIFFERENT waves; never concurrent
- `rocket.gd`: B3 (1 line), D3 (thrust particles) — different regions, but same wave only if agents coordinate
- `MobileUI.gd`: A2 (hot-swap + pause row + hotplug), B1 (coach-mark `highlight()` method), B2 (TargetArrow mount) — the Wave-2 A-agent OWNS MobileUI.gd and pre-adds the `highlight(btn_name,on)` getter B1 needs; B2 mounts its arrow on the generic HUD `CanvasLayer`/`UIOverLay`, NOT via a MobileUI edit, to stay off the hot file
- `AutoPilot.gd`: C1, B5, C3
- `render_remote.sh`/`assemble.sh`/`capture.sh`: C1(one line), E1, E3 — bundled into ONE Wave-1 agent (WP-E)
- `Level1.gd`: B1 only

**Wave 1 (independent, start immediately):**
- C1 (AutoPilot action repeat) — also owns the `render_remote.sh` deterministic default
- C2 (eval matrix)
- D1 (starfield shader)
- D3 (thrust ramp — rocket.gd particles only)
- E1+E3 bundled (pipeline scripts)
- B0 (HintService — owns globalvar `seen_hints` this wave)

**Wave 2 (after wave 1 merges):**
- A1+A2+A3 as ONE agent (Menu.gd + MobileUI.gd + TextsIngame.tscn + globalvar settings
  surface incl. `desktop_control` + `active_input_hint()` helper). Pre-adds the
  `highlight(btn_name,on)` method B1 needs.
- A4 (gamepad bindings — `project.godot` `[input]` ONLY; disjoint from the A-agent)
- B1 (Level1 tutorial; uses `active_input_hint()` + `control_scheme_changed` from the
  A-agent — sequence B1 to start after the A-agent lands the helper, or have B1 add a
  safe fallback if the helper isn't present yet)
- B2 (TargetArrow — new file, mounts on the generic HUD layer, no MobileUI edit)
- B3 (death advice — owns `last_death` in globalvar + rocket.gd one-liner)
- D2 (menu backgrounds — .tscn only)

  Note: A-agent and B1 both read/derive control text; the A-agent owns the
  `active_input_hint()` helper, so run the A-agent FIRST in Wave 2 (or as an earlier
  sub-phase) and let B1/B3/B2 follow — a short two-phase pipeline, not a flat fan-out.

**Wave 3:**
- B4 (hazard banners), B5 (demo mode), B6 (help restructure)
- C3 (hazard-aware transit — driven by C2's table)
- E2 (portrait capture), E4 (QA clip)

**Phase 2:** F1 → F2/F3.

**Measurement (after ship):** funnel on `control_scheme_chosen` split,
`tutorial_step` drop-off, L1 `level_death.attempt` distribution before first win,
`demo_watched`, and the existing death forensics — compare 2 weeks pre/post.

**Decisions (owner: John):**
1. ~~Whether the picker should nudge Joystick~~ **RESOLVED 2026-07-16: NO nudge —
   both options equal weight, no "recommended" badge. Desktop additionally offers
   Keyboard vs Gamepad when a controller is connected (WP-A1 + WP-A4), keyboard
   pre-selected as a safe default (not a nudge). The `control_scheme_chosen` split will
   still tell us the real preference.**
2. Audio-toggle scope in A3 (Music-only v1 is acceptable). — still open
3. C4 go/no-go — decide after C3's matrix. — still open
4. Phase 2 kickoff timing. — still open
5. Gamepad button map (WP-A4) — proposed Ⓐ=thrust, Ⓑ=reverse, Ⓧ=fire, etc.; John to
   confirm/adjust once tried on a real controller.
