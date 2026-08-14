extends Node
## Global game state singleton. Manages level progress, wallet, upgrades, save/load.
## Autoloaded — access from anywhere via `globalvar.xxx`.

# --- Signals ---
signal sendDeath
signal wallet_changed(new_total: int)
## Emitted whenever the control-hint preference changes — either the mobile
## control_scheme or the desktop_control. Live listeners (MobileUI joystick
## visibility, tilt recalibration, tutorial/HUD glyphs) refresh on this instead
## of only at level load. ALWAYS write those settings via set_control_scheme()/
## set_desktop_control() so this fires.
signal control_scheme_changed

# --- Level state ---
var nowlevel: int = 1
var finaltime: float = 0.0
var all_completed: bool = false
var highest_level_completed: int = 0  # Tracks progress for level select
var tutorial_shown: bool = false  # Level 1 tutorial prompts (first-time only)
var welcome_shown: bool = false   # First-launch nickname/welcome prompt (independent of tutorial)
const CURRENT_OPENING_INTRO_VERSION := 2
var opening_intro_version: int = 0  # Versioned so existing players see a materially improved opening once
var first_flight_briefing_shown: bool = false  # One-time pre-action Level 1 mission briefing
var seen_hints: Array[String] = []  # one-time HintService hint ids already shown (persisted)
## Google Play purchase tokens whose CONSUMABLE grant has already been credited.
## Play keeps returning an unconsumed purchase from query_purchases(), which the
## client runs on every launch and on every Restore Purchases tap — so without a
## record of what was already credited, a consumable whose consume call failed
## re-credits its Moonrocks on every single launch. Persisted, and capped because
## it only ever needs to outlive an in-flight consume.
var granted_purchase_tokens: Array[String] = []
const MAX_GRANTED_TOKENS := 64

# --- Endless mode ---
var endless_mode: bool = false
var endless_wave: int = 1
var endless_best_wave: int = 0

# --- Difficulty ---
enum Difficulty { EASY, NORMAL, HARD }
var difficulty: int = Difficulty.NORMAL
# Race/opponent mode (transient, NOT persisted): set by the menu before launching
# a race-enabled level. race_won is filled in when the race is decided.
var race_mode := false
var race_won := false
# Demo mode (transient, NOT persisted — never added to get_save_data). True while
# the heuristic AutoPilot flies a watchable "Watch a demo flight" run (WP-B5). A
# demo submits NO scores, marks NO progress and never sets tutorial_shown — it is
# gated in ScoreClient.submit_score and Victory. Set true by DeathScreen /
# AutoPilot.start_demo(); cleared by AutoPilot.stop_demo() on take-over, demo
# victory, or a demo crash. NOT reset in reset_level_stats (the demo reloads the
# level, and that must not clear the flag mid-transition).
var demo_mode := false

const DIFFICULTY_NAMES := { 0: "Easy", 1: "Normal", 2: "Hard" }

# Physics uses compact world-space units so the arcade-sized solar system remains
# playable. Player-facing speed is presentation-only: 100 world units/s reads as
# 1.00 km/s. Never apply this scale to physics, thresholds, scoring, or telemetry.
const DISPLAY_KM_S_PER_WORLD_SPEED := 0.01

func speed_to_display_km_s(world_speed: float) -> float:
	return maxf(world_speed, 0.0) * DISPLAY_KM_S_PER_WORLD_SPEED

func format_speed_km_s(world_speed: float) -> String:
	return "%.2f km/s" % speed_to_display_km_s(world_speed)

# --- Mobile control scheme ---
# Desktop uses keyboard (this setting is ignored). On mobile, the player can
# choose how to rotate the rocket. Thrust + reverse remain on-screen buttons
# in all modes.
## TILT: tilt-to-turn + on-screen thrust button (landscape).
## JOYSTICK: on-screen stick + thrust button, no tilt (landscape).
## FULL_TILT: no buttons — roll to turn, pitch to thrust — runs in PORTRAIT.
enum ControlScheme { TILT, JOYSTICK, FULL_TILT }
var control_scheme: int = ControlScheme.TILT
const CONTROL_SCHEME_NAMES := { 0: "Tilt", 1: "Joystick", 2: "Full Tilt" }

## Full-tilt (portrait) tuning. Pitch (device forward/back tilt) drives thrust:
## deadzone below which no thrust, then linear up to full. Turn reuses the tilt
## roll axis. ALL of the axis/polarity choices below are DEVICE-CALIBRATION values
## (like IOS/ANDROID_TILT_POLARITY) — verify + flip on a real phone in portrait.
const FULLTILT_THRUST_DEADZONE := 0.06   # normalized pitch below this = no thrust
const FULLTILT_THRUST_FULL := 0.5        # normalized pitch at/above this = full thrust
const FULLTILT_TURN_POLARITY := 1.0      # flip if roll steers the wrong way in portrait
const FULLTILT_THRUST_POLARITY := 1.0    # flip if you have to pitch the WRONG way to thrust
## true when the active scheme wants a portrait viewport (full-tilt on mobile).
func wants_portrait() -> bool:
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		return false
	return control_scheme == ControlScheme.FULL_TILT or orientation_pref == Orientation.PORTRAIT

## Apply the orientation the current scheme wants. Call on _ready and whenever the
## scheme changes. Full-tilt -> portrait; everything else -> sensor-landscape.
func apply_orientation() -> void:
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		return
	# Full-tilt is portrait by design; otherwise honor the orientation setting.
	# SENSOR_* locks to one orientation family (allows its 180° flip, never crosses).
	if wants_portrait():
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
	else:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)

# --- Desktop control preference ---
# On desktop BOTH keyboard and gamepad inputs stay live at once. This setting
# only chooses which control HINTS/glyphs to show (tutorial text, Help, coach
# marks, death advice). Default KEYBOARD — a safe default, not a nudge (WP-A1).
enum DesktopControl { KEYBOARD, GAMEPAD }
var desktop_control: int = DesktopControl.KEYBOARD
const DESKTOP_CONTROL_NAMES := { 0: "Keyboard", 1: "Gamepad" }

# --- Orientation (mobile) — portrait is FIRST-CLASS, independent of control scheme ---
# We LOCK to the chosen orientation (SENSOR_LANDSCAPE / SENSOR_PORTRAIT allow the
# two 180° flips of that orientation but never cross to the other) rather than free
# sensor-rotate, so tilt-steering can't flip the screen mid-play. First launch
# detects how the device is held and defaults to it (_detect_launch_orientation);
# the player can change it in Options. Full-tilt forces portrait regardless.
enum Orientation { LANDSCAPE, PORTRAIT }
var orientation_pref: int = Orientation.LANDSCAPE
const ORIENTATION_NAMES := { 0: "Landscape", 1: "Portrait" }

## UI scale compensation for portrait. With the 1024x600 landscape base + expand,
## landscape renders at ~1.8x (600-height-driven) but portrait at only ~1.05x
## (1024-width-driven) — so UI/text is ~1.7x SMALLER in portrait. Boost the content
## scale in portrait to restore a readable, consistent physical size. Because this
## also scales the gameplay WORLD, the rocket camera zoom is divided by it in
## portrait so the world view is unchanged (see rocket.gd _apply_portrait_view).
const PORTRAIT_UI_SCALE := 1.6

## Current content-scale multiplier, driven by the LIVE window aspect (not the
## mobile setting) so it is correct on-device AND for desktop portrait renders.
## Gameplay code that must undo the world zoom (the camera) divides by this.
func ui_scale() -> float:
	var ws := DisplayServer.window_get_size()
	return PORTRAIT_UI_SCALE if ws.y > ws.x else 1.0

## Push ui_scale() onto the root. Wired to the window's size_changed in _ready so
## rotation, resize, and render-time viewport swaps all keep the UI physically sized.
func _apply_ui_scale() -> void:
	var t := get_tree()
	if t == null or t.root == null:
		return
	t.root.content_scale_factor = ui_scale()

# --- Input-hint resolver ---
# Single source of truth for "which control style are we teaching right now?".
# Every place that branches control-instruction text (tutorial, Help, coach
# marks, death advice) must call active_input_hint() instead of re-deriving
# is_mobile/control_scheme inline.
enum InputHint { KEYBOARD, GAMEPAD, TILT, TOUCH_JOYSTICK, FULL_TILT }

func active_input_hint() -> int:
	## Resolve the active control-hint style from platform + the two settings.
	var os := OS.get_name()
	if os == "Android" or os == "iOS":
		if control_scheme == ControlScheme.FULL_TILT:
			return InputHint.FULL_TILT
		if control_scheme == ControlScheme.TILT:
			return InputHint.TILT
		return InputHint.TOUCH_JOYSTICK
	# Desktop (and Web-on-desktop): both inputs live; the setting picks glyphs.
	if desktop_control == DesktopControl.GAMEPAD:
		return InputHint.GAMEPAD
	return InputHint.KEYBOARD

# --- Control-setting writers (emit control_scheme_changed) ---
# Route ALL runtime writes to control_scheme / desktop_control through these so
# live listeners stay in sync. Bulk state loads (_apply_save_data /
# reset_progress) assign directly since no listener is connected yet there.
func set_control_scheme(scheme: int) -> void:
	control_scheme = scheme
	apply_orientation()  # full-tilt <-> other flips portrait/landscape live
	control_scheme_changed.emit()

func set_desktop_control(mode: int) -> void:
	desktop_control = mode
	control_scheme_changed.emit()

func set_orientation_pref(o: int) -> void:
	orientation_pref = o
	apply_orientation()
	control_scheme_changed.emit()  # HUD/glyph listeners also refresh on orientation

## First-run only: default the orientation to how the device is being held. The OS
## hands us a portrait-shaped window if the phone launched upright (project.godot
## uses "sensor" orientation), so read the window aspect BEFORE we lock anything.
func _detect_launch_orientation() -> void:
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		return
	var sz := DisplayServer.window_get_size()
	orientation_pref = Orientation.PORTRAIT if sz.y > sz.x else Orientation.LANDSCAPE

## Tilt sensitivity — multiplier on normalized tilt [-1..1] from calibrated
## baseline. Lower = needs more tilt for max steering. Tuned for ~30° = full.
## Now a runtime setting (Options slider, range 1.0–4.0); DEFAULT anchors it.
const TILT_SENSITIVITY_DEFAULT := 2.0
var tilt_sensitivity := TILT_SENSITIVITY_DEFAULT
## Deadzone — tilt amounts smaller than this register as zero. The low-pass
## filter handles sensor jitter, so this can be tight: 0.02 ≈ 1.1°.
const TILT_DEADZONE := 0.02
## Max angular velocity in tilt mode (rad/s). At full tilt the rocket spins
## at this rate. Set high enough for snappy turns but low enough that you
## can't whip into a 720° spin from a single twitch.
const TILT_MAX_ANGULAR_VELOCITY := 4.5
## If true, tilt applies TORQUE (force-based, momentum builds) instead of
## setting angular_velocity directly (proportional, instant stop on release).
## Torque feels more "spacecraft-like" but harder to control via tilt.
const TILT_USE_TORQUE := false
## Low-pass filter alpha for the raw gravity vector. Higher = more responsive
## but more jitter; lower = smoother but more lag. 0.35 ≈ 3-frame time
## constant (~50ms) — snappy without obvious lag.
## This is what lets us avoid drift logic without losing input to jitter.
const TILT_FILTER_ALPHA := 0.35

## iOS tilt-steer polarity. The correct steering sign is ABSOLUTE (tied to the
## physical landscape, same for iPhone and iPad): one landscape needs -delta.y,
## the 180°-flipped landscape needs +delta.y. We read the live landscape from
## gravity.x's sign (see rocket.gd) and this constant anchors which sign maps to
## which. +1 reproduces the device-verified "cable-on-right = -delta.y" hold. If
## BOTH landscapes steer inverted on a real device, flip this to -1.0 — that is
## the single source of truth for the whole mapping.
const IOS_TILT_POLARITY := 1.0

## Android tilt-steer polarity (see IOS_TILT_POLARITY). Android reports gravity in
## a frame transposed from iOS: roll/steer reads on delta.x and the dominant in-plane
## "down" axis is gravity.y, so gravity.y's sign is the live landscape discriminator.
## Device-verified on a moto g (2025): -1.0 is correct (gravity.y the discriminator,
## delta.x the steer). +1.0 inverts BOTH landscapes.
const ANDROID_TILT_POLARITY := -1.0

# --- Audio settings ---
# Music-only toggle for v1 (SFX toggle deferred — a second "SFX" bus + explicit
# per-node routing would sprawl across many scenes not owned by this WP; tracked
# for a follow-up). A dedicated "Music" bus is created at startup and every
# background-music player (streams under res://art/audio/*bgm*) is auto-routed
# onto it via node_added, so muting the bus silences BGM everywhere without
# editing each scene.
var music_enabled := true
const MUSIC_BUS_NAME := "Music"
var _music_bus_idx := -1

# --- Death forensics (transient, NOT persisted) ---
# Populated by rocket.gd at death time (WP-B3) so the death screen can give
# cause-specific advice. Stays empty on edge cases (e.g. self-destruct) so the
# death screen can suppress the advice row instead of showing a stale one.
var last_death: Dictionary = {}
# Set by a hazard (Martian/GammaRay/BlackHole) to its canonical name immediately
# before emitting sendDeath, so death() can name the killer (crash_body is null on
# the signal path). Consumed + cleared in death(); reset each level.
var pending_hazard_name := ""

## Spawn interval multiplier (higher = slower spawns = easier)
func get_spawn_interval_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 1.8
		Difficulty.HARD: return 1.0
		_: return 1.4

## Enemy speed multiplier
func get_enemy_speed_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 0.6
		Difficulty.HARD: return 1.0
		_: return 0.8

## Fuel drain multiplier (higher = drains faster = harder)
func get_fuel_drain_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 0.6
		Difficulty.HARD: return 1.0
		_: return 0.8

## Fuel tank size multiplier by difficulty.
## Applied to max_fuel so the rocket starts with a full tank — the difficulty
## advantage shows up as a bigger tank, not as "115% fuel" overfill in the HUD.
func get_starting_fuel_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 1.4
		Difficulty.HARD: return 1.0
		_: return 1.2

## Second-chance bounces allowed per level attempt. The bounce now also catches
## HAZARD hits (Martian/gamma/black hole), not just body crashes — the single
## highest-impact mercy for the hazard levels. Default (Normal) gets one; Easy two.
func get_bounce_allowance() -> int:
	match difficulty:
		Difficulty.EASY: return 2
		Difficulty.HARD: return 0
		_: return 1

# --- Ad removal ---
const AD_REMOVAL_COST := 10000  # Moonrocks to remove banners + interstitials
var ads_removed: bool = false
# Provider-neutral lifetime access is cached separately from ad removal. The
# cache makes a verified native purchase usable offline; it is never payment
# authority and must be reconciled from provider/App Platform truth.
var race_unlimited_cached: bool = false
# Limited mobile access is persisted independently from the paid lifetime
# capability. A free player receives one CPU race per UTC day; an explicitly
# completed rewarded ad grants one additional race credit. The server ledger
# can replace this local compatibility cache when App Platform activation is
# enabled without changing the product entitlement.
var race_free_utc_day: String = ""
var race_rewarded_credits: int = 0

func is_ads_removed() -> bool:
	return ads_removed

func has_cached_unlimited_races() -> bool:
	return race_unlimited_cached

func race_utc_day() -> String:
	return Time.get_date_string_from_system(true)

func has_daily_free_race(utc_day: String = "") -> bool:
	var day := utc_day if utc_day != "" else race_utc_day()
	return race_free_utc_day != day

func can_start_limited_race(utc_day: String = "") -> bool:
	return has_daily_free_race(utc_day) or race_rewarded_credits > 0

func consume_limited_race(utc_day: String = "") -> bool:
	var day := utc_day if utc_day != "" else race_utc_day()
	if has_daily_free_race(day):
		race_free_utc_day = day
		save_game()
		return true
	if race_rewarded_credits > 0:
		race_rewarded_credits -= 1
		save_game()
		return true
	return false

func grant_rewarded_race() -> bool:
	# Do not bank an unbounded inventory of ad grants. The confirmation flow
	# consumes this credit immediately; the cap also fails closed after a crash.
	if race_rewarded_credits >= 1:
		return false
	race_rewarded_credits = 1
	save_game()
	return true

func buy_ad_removal() -> bool:
	if ads_removed or wallet < AD_REMOVAL_COST:
		return false
	wallet -= AD_REMOVAL_COST
	ads_removed = true
	wallet_changed.emit(wallet)
	save_game()
	return true

# --- Level pack unlock ---
# Levels 1-4 are free. Levels 5+ require unlock via IAP or earning enough crypto.
const FREE_LEVELS := 4
const LEVEL_PACK_GRIND_COST := 2000  # Moonrocks earned (lifetime) to unlock for free
var levels_unlocked: bool = false  # true = all levels accessible
var total_crypto_earned: int = 0   # lifetime Moonrocks earned (never decreases)
var total_deaths: int = 0          # lifetime death count (for achievement skin)
var landings_since_install: int = 0  # successful landings ever — drives rate prompt
var rate_prompt_shown: bool = false  # one-time rate-this-game popup flag

func is_level_unlocked(level: int) -> bool:
	if level <= FREE_LEVELS:
		return true
	return levels_unlocked or total_crypto_earned >= LEVEL_PACK_GRIND_COST

func is_level_reachable(level: int) -> bool:
	## True if the player has progressed far enough AND the level is unlocked.
	return level <= highest_level_completed + 1 and is_level_unlocked(level)

func unlock_all_levels() -> void:
	levels_unlocked = true
	save_game()

# --- Ship skins ---
const SKIN_CATALOG := {
	"default": { "path": "res://art/ship/rocket.png", "price": 0, "label": "Default" },
	"retro": { "path": "res://art/ship/skins/retro.png", "price": 200, "label": "Retro" },
	"stealth": { "path": "res://art/ship/skins/stealth.png", "price": 300, "label": "Stealth" },
	"gold": { "path": "res://art/ship/skins/gold.png", "price": 500, "label": "Gold" },
	"alien": { "path": "res://art/ship/skins/alien.png", "price": 400, "label": "Alien" },
	"wownero": { "path": "res://art/ship/skins/wownero.png", "price": 350, "label": "Wownero" },
	"monero": { "path": "res://art/ship/skins/monero.png", "price": 350, "label": "Monero" },
	"bitcoin": { "path": "res://art/ship/skins/bitcoin.png", "price": 350, "label": "Bitcoin" },
	"litecoin": { "path": "res://art/ship/skins/litecoin.png", "price": 350, "label": "Litecoin" },
	"champion": { "path": "res://art/ship/skins/champion.png", "price": 0, "label": "Champion", "achievement": true },
	"skull": { "path": "res://art/ship/skins/skull.png", "price": 0, "label": "Skull", "achievement": true },
	"crystalbeetle": { "path": "res://art/ship/skins/crystalbeetle.png", "price": 0, "label": "Crystal Beetle", "achievement": true },
	"steamboat": { "path": "res://art/ship/skins/steamboat.png", "price": 0, "label": "Steamboat", "achievement": true },
}

# --- Achievement skins ---
func check_achievement_skins() -> void:
	## Call after level completion or death to check if achievement skins should unlock.
	# Champion: 3 stars on all story levels (1-11)
	var all_3star := true
	for lvl in range(1, 12):  # levels 1-11
		if get_best_stars(lvl) < 3:
			all_3star = false
			break
	if all_3star and "champion" not in owned_skins:
		owned_skins.append("champion")
		PlayGamesManager.on_skin_owned(owned_skins.size())
		GameCenterManager.on_skin_owned(owned_skins.size())
	# Skull: 50 total deaths
	if total_deaths >= 50 and "skull" not in owned_skins:
		owned_skins.append("skull")
		PlayGamesManager.on_skin_owned(owned_skins.size())
		GameCenterManager.on_skin_owned(owned_skins.size())
	# Crystal Beetle: complete all 11 story levels
	if highest_level_completed >= 11 and "crystalbeetle" not in owned_skins:
		owned_skins.append("crystalbeetle")
		PlayGamesManager.on_skin_owned(owned_skins.size())
		GameCenterManager.on_skin_owned(owned_skins.size())
	# Steamboat: reach wave 10 in Endless Mode
	if endless_best_wave >= 10 and "steamboat" not in owned_skins:
		owned_skins.append("steamboat")
		PlayGamesManager.on_skin_owned(owned_skins.size())
		GameCenterManager.on_skin_owned(owned_skins.size())

func increment_deaths() -> void:
	total_deaths += 1
	check_achievement_skins()
	PlayGamesManager.on_death(total_deaths)
	GameCenterManager.on_death(total_deaths)
	save_game()

var selected_skin: String = "default"
var owned_skins: Array = ["default"]

func get_skin_texture_path() -> String:
	var entry: Dictionary = SKIN_CATALOG.get(selected_skin, SKIN_CATALOG["default"])
	return entry["path"]

func can_buy_skin(skin_id: String) -> bool:
	if skin_id in owned_skins:
		return false
	var entry: Dictionary = SKIN_CATALOG.get(skin_id, {})
	return not entry.is_empty() and wallet >= entry["price"]

func buy_skin(skin_id: String) -> bool:
	if not can_buy_skin(skin_id):
		return false
	wallet -= SKIN_CATALOG[skin_id]["price"]
	owned_skins.append(skin_id)
	selected_skin = skin_id
	wallet_changed.emit(wallet)
	PlayGamesManager.on_skin_owned(owned_skins.size())
	GameCenterManager.on_skin_owned(owned_skins.size())
	save_game()
	return true

func select_skin(skin_id: String) -> void:
	if skin_id in owned_skins:
		selected_skin = skin_id
		save_game()

# --- Per-run tracking (reset each level start) ---
var level_crypto_collected: int = 0   # Moonrocks earned this run
var level_fuel_remaining: float = 0.0 # percentage at landing
var level_bounces_used: int = 0  # second-chance bounces used this attempt (see get_bounce_allowance)

# --- Waypoint checkpoint (transient, not persisted) ---
var checkpoint_position: Vector2 = Vector2.ZERO
var checkpoint_velocity: Vector2 = Vector2.ZERO
var checkpoint_fuel: float = 0.0
var checkpoint_planet_name: String = ""  # display name of waypoint
var has_checkpoint: bool = false
var restore_checkpoint: bool = false  # flag: rocket should restore from checkpoint on next _ready

# --- Best times & stars per level (persisted) ---
var best_times := {}  # { "1": 25.3, "2": 42.1, ... }
var best_stars := {}  # { "1": 3, "2": 2, ... }

# --- Player identity (persisted) ---
var device_uuid: String = ""
var nickname: String = ""

# --- Random nickname word lists ---
const NICK_PREFIXES := [
	"Satoshi", "Crypto", "Moon", "Stellar", "Cosmic", "Nebula",
	"Astro", "Lunar", "Solar", "Galactic", "Quantum", "Orbital",
	"Rocket", "Comet", "Nova", "Plasma", "Photon", "Ion",
	"Turbo", "Hyper", "Zero", "Neon", "Warp", "Void",
	"Echo", "Flux", "Omega", "Alpha", "Blitz", "Zen",
]
const NICK_SUFFIXES := [
	"Pilot", "Whale", "Ape", "Hodler", "Miner", "Voyager",
	"Ranger", "Knight", "Cadet", "Captain", "Scout", "Drifter",
	"Walker", "Rider", "Hunter", "Guru", "Monk", "Sage",
	"Fox", "Wolf", "Hawk", "Bear", "Bull", "Lynx",
	"Bot", "Node", "Byte", "Core", "Spark", "Blaze",
]

func generate_random_nickname() -> String:
	## Generate a random crypto/astro themed nickname like "MoonWhale" or "SatoshiPilot".
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var prefix: String = NICK_PREFIXES[rng.randi_range(0, NICK_PREFIXES.size() - 1)]
	var suffix: String = NICK_SUFFIXES[rng.randi_range(0, NICK_SUFFIXES.size() - 1)]
	return prefix + suffix

# --- Wallet (persisted) ---
var wallet: int = 0  # Moonrocks balance (all crypto converted to Moonrocks on pickup)

# --- Upgrades (persisted) ---
# Each upgrade is an int level (0 = base). Higher = better.
var upgrades := {
	"thrust": 0,       # +50 thrust force per level
	"fuel_capacity": 0, # +25 max fuel per level
	"fuel_efficiency": 0, # -2 drain/s per level
	"armor": 0,         # +50 crash speed threshold per level
	"landing_gear": 0,  # +20 landing speed threshold per level
	"shield": 0,        # absorb 1 hit per level (0 = no shield)
	"rotation": 0,      # +1000 torque per level for tighter control
	"reverse_thrust": 0, # +40 reverse thrust force per level
	"magnet": 0,        # auto-attract crypto within 50+30*level px
	"cannon": 0,        # forward cannon weapon (level 0 = none, 1-5 = faster fire rate)
	"missile": 0,       # homing missile launcher (level 0 = none, ammo = 2 * level per run)
	"laser": 0,         # continuous laser beam (level 0 = none, range increases per level)
	"emp": 0,           # EMP pulse (level 0 = none, charges = level per run)
}

# --- Upgrade costs (Moonrocks) — cost increases per level ---
const UPGRADE_BASE_COSTS := {
	"thrust": 50,
	"fuel_capacity": 40,
	"fuel_efficiency": 60,
	"armor": 80,
	"landing_gear": 45,
	"shield": 100,
	"rotation": 35,
	"reverse_thrust": 55,
	"magnet": 70,
	"cannon": 150,
	"missile": 200,
	"laser": 250,
	"emp": 300,
}
const UPGRADE_MAX_LEVEL := 5

# --- Upgrade descriptions for the shop ---
const UPGRADE_DESCRIPTIONS := {
	"thrust": "Engine Power — more thrust force",
	"fuel_capacity": "Fuel Tank — larger fuel capacity",
	"fuel_efficiency": "Fuel Efficiency — less fuel drain",
	"armor": "Armor Plating — survive harder impacts",
	"landing_gear": "Landing Gear — land at higher speed",
	"shield": "Shield Generator — absorb hits before death",
	"rotation": "Gyroscope — faster rotation control",
	"reverse_thrust": "Retro Rockets — stronger reverse thrust",
	"magnet": "Crypto Magnet — attract nearby pickups",
	"cannon": "Forward Cannon — shoot enemies (hold to fire)",
	"missile": "Missile Launcher — homing missiles (+2 ammo/lvl)",
	"laser": "Laser Beam — continuous beam (drains fuel)",
	"emp": "EMP Pulse — destroy all nearby enemies (+1 charge/lvl)",
}

# --- Derived stats (computed from upgrades) ---
func get_thrust_force() -> float:
	return 350.0 + upgrades["thrust"] * 50.0

func get_max_fuel() -> float:
	return (200.0 + upgrades["fuel_capacity"] * 40.0) * get_starting_fuel_mult()

func get_fuel_drain() -> float:
	return maxf(8.0 - upgrades["fuel_efficiency"] * 1.5, 2.0)

func get_crash_speed() -> float:
	var base: float = 100.0 + upgrades["armor"] * 50.0
	match difficulty:
		Difficulty.EASY: return base * 1.6
		Difficulty.HARD: return base * 1.0
		_: return base * 1.3

func get_landing_speed() -> float:
	var base: float = 40.0 + upgrades["landing_gear"] * 20.0
	match difficulty:
		Difficulty.EASY: return base * 1.8
		Difficulty.HARD: return base * 1.0
		_: return base * 1.4

func get_shield_hits() -> int:
	return upgrades["shield"]  # 0 = no shield, 1-5 hits absorbed

func get_torque() -> float:
	return 5000.0 + upgrades["rotation"] * 1000.0

func get_reverse_thrust_force() -> float:
	return 350.0 + upgrades["reverse_thrust"] * 40.0

func get_magnet_radius() -> float:
	if upgrades["magnet"] <= 0:
		return 0.0
	return 50.0 + upgrades["magnet"] * 30.0

func get_upgrade_cost(upgrade_name: String) -> int:
	var base: int = UPGRADE_BASE_COSTS.get(upgrade_name, 100)
	var level: int = upgrades.get(upgrade_name, 0)
	return base * (level + 1)

func can_buy_upgrade(upgrade_name: String) -> bool:
	var level: int = upgrades.get(upgrade_name, 0)
	return level < UPGRADE_MAX_LEVEL and wallet >= get_upgrade_cost(upgrade_name)

func buy_upgrade(upgrade_name: String) -> bool:
	if not can_buy_upgrade(upgrade_name):
		return false
	var cost := get_upgrade_cost(upgrade_name)
	wallet -= cost
	upgrades[upgrade_name] += 1
	wallet_changed.emit(wallet)
	if upgrades[upgrade_name] >= UPGRADE_MAX_LEVEL:
		PlayGamesManager.on_upgrade_maxed()
		GameCenterManager.on_upgrade_maxed()
	save_game()
	return true

func add_crypto(amount: int) -> void:
	wallet += amount
	level_crypto_collected += amount
	total_crypto_earned += amount
	wallet_changed.emit(wallet)
	PlayGamesManager.on_crypto_earned(total_crypto_earned)
	GameCenterManager.on_crypto_earned(total_crypto_earned)

# --- Level config (eliminates hardcoded match statements) ---
const LEVEL_SCENES := {
	1: "res://game/levels/1/Level1.tscn",
	2: "res://game/levels/2/Level2.tscn",
	3: "res://game/levels/3/Level3.tscn",
	4: "res://game/levels/4/Level4.tscn",
	5: "res://game/levels/5/Level5.tscn",
	6: "res://game/levels/6/Level6.tscn",
	7: "res://game/levels/7/Level7.tscn",
	8: "res://game/levels/8/Level8.tscn",
	9: "res://game/levels/9/Level9.tscn",
	10: "res://game/levels/10/Level10.tscn",
	11: "res://game/levels/11/Level11.tscn",
	12: "res://game/levels/12/EndlessMode.tscn",
}
const MAX_LEVEL := 12

const LEVEL_NAMES := {
	1: "Moon",
	2: "Mars",
	3: "Venus",
	4: "Io",
	5: "Jupiter",
	6: "Saturn",
	7: "Neptune",
	8: "Pluto",
	9: "Asteroid Belt",
	10: "Space Station",
	11: "Mothership",
	12: "Endless Mode",
}

func get_level_scene(level: int) -> String:
	if level == 12:
		endless_mode = true
		endless_wave = 1
	else:
		endless_mode = false
	return LEVEL_SCENES.get(level, LEVEL_SCENES[1])

func get_next_level_scene() -> String:
	if nowlevel >= MAX_LEVEL:
		return ""  # No more levels yet — expand LEVEL_SCENES to add more
	var next_level := nowlevel + 1
	# Verify the next level is reachable before returning it
	if not is_level_reachable(next_level):
		return ""  # Player hasn't completed this level yet
	return LEVEL_SCENES.get(next_level, "")

func has_next_level() -> bool:
	return nowlevel < MAX_LEVEL

# --- Star rating ---
# 3★ thresholds (seconds) — earn 3 stars if under this time, 2 stars if under 2x, else 1
const STAR_3_TIME := {
	1: 20.0,  # Moon
	2: 30.0,  # Mars
	3: 40.0,  # Venus
	4: 50.0,  # Io
	5: 60.0,  # Jupiter
	6: 75.0,  # Saturn
	7: 90.0,  # Neptune
	8: 100.0,  # Pluto
	9: 110.0,  # Asteroid Belt
	10: 120.0,  # Space Station
	11: 140.0,  # Mothership
	12: 60.0,  # Endless Mode (per wave)
}

func compute_stars(level: int, time_s: float, fuel_pct: float, _crypto: int) -> int:
	var threshold: float = STAR_3_TIME.get(level, 30.0)
	var stars := 1
	if time_s <= threshold:
		stars = 3
	elif time_s <= threshold * 2.0:
		stars = 2
	# Fuel bonus: 50%+ fuel remaining bumps up 1 star (cap at 3)
	if fuel_pct >= 50.0 and stars < 3:
		stars += 1
	return stars


## Unified run score — ONE coherent number combining speed, fuel, and Moonrocks.
## Speed vs the 3★ target time is the main lever (2000 at target, up to 6000 for a
## blazing run, fading toward 0 if slow); fuel remaining and Moonrocks both add in.
## The backend recomputes this server-side from the same inputs (anti-cheat) and
## the leaderboard ranks by it. Keep this formula in sync with the backend.
func compute_score(level: int, time_s: float, fuel_pct: float, moonrocks: int) -> int:
	var target: float = STAR_3_TIME.get(level, 30.0)
	var speed_pts := int(round(clampf(target / maxf(time_s, 1.0), 0.0, 3.0) * 2000.0))
	var fuel_pts := int(round(clampf(fuel_pct, 0.0, 100.0) * 25.0))
	var rock_pts := maxi(moonrocks, 0) * 50
	return 1000 + speed_pts + fuel_pts + rock_pts

func get_best_time(level: int) -> float:
	## Returns best time for a level, or -1.0 if no record.
	return float(best_times.get(str(level), -1.0))

func get_best_stars(level: int) -> int:
	return int(best_stars.get(str(level), 0))

func record_level_result(level: int, time_s: float, fuel_pct: float, crypto: int) -> int:
	## Record a level completion. Returns star count. Updates best time/stars if improved.
	var stars := compute_stars(level, time_s, fuel_pct, crypto)
	var key := str(level)
	var prev_time: float = float(best_times.get(key, 999999.0))
	if time_s < prev_time:
		best_times[key] = time_s
	var prev_stars: int = int(best_stars.get(key, 0))
	if stars > prev_stars:
		best_stars[key] = stars
	# Update progression tracker — only when the player actually completes a level
	highest_level_completed = maxi(highest_level_completed, level)
	# Lifetime successful-landings counter — drives the rate-prompt trigger on Victory.
	landings_since_install += 1
	check_achievement_skins()
	# Notify achievement services
	PlayGamesManager.on_level_completed(level, maxi(stars, int(best_stars.get(key, 0))))
	GameCenterManager.on_level_completed(level, maxi(stars, int(best_stars.get(key, 0))))
	return stars

var level_attempt: int = 1        # which attempt on the current level (death forensics)
var _last_attempt_level: int = -1


func reset_level_stats() -> void:
	## Call at the start of each level to reset per-run tracking.
	# Per-level attempt count: same level again = retry (+1), new level = attempt 1.
	if nowlevel == _last_attempt_level:
		level_attempt += 1
	else:
		level_attempt = 1
		_last_attempt_level = nowlevel
	level_crypto_collected = 0
	level_fuel_remaining = 0.0
	level_bounces_used = 0
	# Clear stale death forensics so a prior level's death can't surface on this one.
	last_death = {}
	pending_hazard_name = ""
	checkpoint_position = Vector2.ZERO
	checkpoint_velocity = Vector2.ZERO
	checkpoint_fuel = 0.0
	checkpoint_planet_name = ""
	has_checkpoint = false


func save_checkpoint(pos: Vector2, vel: Vector2, fuel_amt: float, planet_name: String) -> void:
	## Save a waypoint checkpoint. Called when rocket enters a waypoint's gravity well.
	checkpoint_position = pos
	checkpoint_velocity = vel
	checkpoint_fuel = fuel_amt
	checkpoint_planet_name = planet_name
	has_checkpoint = true

## True when this process is an automated run — a headless bot sim, a Movie Maker
## capture, or a godot_rl_agents training env (which adds --disable-render-loop to
## every env binary) — rather than a real player session.
##
## Single source of truth for "don't touch the live backend": Telemetry, Analytics,
## ScoreClient and CloudSave all gate on this. Adding a new network client means
## calling this, not copying the flag list a fifth time. User args are included so
## the check still holds if a harness passes flags after `--`.
##
## This is deliberately separate from SML_TEST_MODE, which tools/ci/verify.sh sets
## for the test suite: that one stubs transport while letting the clients still
## initialize, so tests can exercise buffering. This one is for bot runs, which no
## harness sets SML_TEST_MODE for.
## True the first time a purchase token is presented for a consumable grant;
## false forever after. Callers must credit the purchase ONLY when this returns
## true, so a replayed Play query cannot double-credit real money.
func claim_purchase_token(token: String) -> bool:
	if token == "":
		return true  # nothing to dedupe against; treat as a fresh grant
	if token in granted_purchase_tokens:
		return false
	granted_purchase_tokens.append(token)
	if granted_purchase_tokens.size() > MAX_GRANTED_TOKENS:
		granted_purchase_tokens = granted_purchase_tokens.slice(
			granted_purchase_tokens.size() - MAX_GRANTED_TOKENS)
	save_game()
	return true

func is_automated_run() -> bool:
	return is_automated_argv(OS.get_cmdline_args() + OS.get_cmdline_user_args())

## Pure argv predicate behind is_automated_run(), split out so the gate is
## testable: the real command line cannot be injected under gdUnit, and an
## untested gate here silently re-opens the live backend to bot runs.
const AUTOMATED_RUN_FLAGS := ["--sim", "--autopilot", "--capture", "--disable-render-loop"]

func is_automated_argv(argv: PackedStringArray) -> bool:
	for flag in AUTOMATED_RUN_FLAGS:
		if flag in argv:
			return true
	return false

func get_platform_string() -> String:
	## Returns platform identifier for leaderboard submissions.
	match OS.get_name():
		"Android": return "ANDROID"
		"iOS": return "IOS"
		"Web": return "WEB"
		"macOS": return "MACOS"
		"Linux": return "LINUX"
		"Windows": return "WINDOWS"
	return ""

# --- Save / Load ---
func _ready():
	# Mobile orientation: full-tilt wants portrait, every other scheme wants true
	# sensor-landscape (the project's "sensor_landscape" only emits Android
	# userLandscape, which honors the auto-rotate lock — this upgrades it). The
	# scheme isn't loaded yet here, so apply_orientation() is (re)called after
	# load_game() below; this call just sets a sane pre-load default.
	apply_orientation()

	# WEB-ONLY: point the global fallback font at the pixel UI font and attach
	# Symbols2 + Emoji as loaded Font resources so symbol/emoji glyphs
	# (★ ☆ 🪨 💰 🔒) render in-browser. The browser runtime has no system
	# fonts, so default-font labels otherwise show tofu boxes for these.
	# Mobile/desktop are untouched: they keep the engine-default (sans) font
	# and resolve these glyphs through the OS font as before. This fixes every
	# default-font label at once (menu, shop, leaderboard, HUD, victory) with
	# no per-label edits and no change to the native builds.
	if OS.get_name() == "Web":
		var web_font: Font = load("res://fonts/Computer Speak v0.3.ttf")
		web_font.fallbacks = [
			load("res://fonts/NotoSansSymbols2-Regular.ttf"),
			load("res://fonts/NotoEmoji-Regular.ttf"),
		]
		ThemeDB.fallback_font = web_font

	# Route background-music players onto a dedicated "Music" bus as they enter
	# the tree, so the Options music toggle works in every scene without editing
	# each one. Connected before the main scene loads so the menu BGM is caught.
	get_tree().node_added.connect(_on_scene_node_added)

	# One-shot migration from the old "Wownero Moon Launch" save dir (if any)
	# must run before load_game so the legacy file is in place to be read.
	_migrate_legacy_save()
	load_game()
	if not welcome_shown:  # first launch — default orientation to how the device is held
		_detect_launch_orientation()
	apply_orientation()  # now that scheme + orientation are known
	# Keep UI physically sized across rotation/resize/render-viewport swaps. Applied
	# now and on every window size change (portrait boosts content scale ~1.6x).
	get_tree().root.size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()
	# Capture/testing hook: force a difficulty for promo renders + balance runs,
	# overriding the loaded save (e.g. SML_DIFF=easy to render L2-L4 as clean wins).
	var _sml_diff := OS.get_environment("SML_DIFF").to_lower()
	if _sml_diff != "":
		match _sml_diff:
			"easy", "0": difficulty = Difficulty.EASY
			"hard", "2": difficulty = Difficulty.HARD
			"normal", "1": difficulty = Difficulty.NORMAL
	# Music bus + saved mute state (after load so music_enabled is applied).
	_setup_audio_buses()
	# Ensure device has a UUID (generated once, persisted forever)
	if device_uuid == "":
		device_uuid = _generate_uuid()
	# Generate a random nickname on first launch
	if nickname == "" or nickname == "Cosmonaut":
		nickname = generate_random_nickname()
	save_game()


func _migrate_legacy_save() -> void:
	## One-shot save migration after the rename to Such Moon Launch.
	## Godot's user:// is derived from config/name, so renaming the app moves the
	## save dir. If the new dir has no save yet but the old dir does, copy it over.
	## Safe to run on every launch — no-op once the new save exists.
	## On Android/iOS the legacy folder won't be visible (sandboxed per package);
	## those players use the existing Restore-from-Cloud button instead.
	var new_path := "user://savegame.json"
	if FileAccess.file_exists(new_path):
		return
	var user_dir := OS.get_user_data_dir()  # .../app_userdata/Such Moon Launch
	var legacy_dir := user_dir.get_base_dir().path_join("Wownero Moon Launch")
	var legacy_save := legacy_dir.path_join("savegame.json")
	if not FileAccess.file_exists(legacy_save):
		return
	var src := FileAccess.open(legacy_save, FileAccess.READ)
	if src == null:
		return
	var data := src.get_as_text()
	src.close()
	var dst := FileAccess.open(new_path, FileAccess.WRITE)
	if dst:
		dst.store_string(data)
		dst.close()

func _generate_uuid() -> String:
	## Generate a v4-style UUID from random bytes.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var parts: Array[String] = []
	for i in range(16):
		parts.append("%02x" % rng.randi_range(0, 255))
	# Set version (4) and variant bits
	parts[6] = "%02x" % ((int("0x" + parts[6]) & 0x0F) | 0x40)
	parts[8] = "%02x" % ((int("0x" + parts[8]) & 0x3F) | 0x80)
	return "%s%s%s%s-%s%s-%s%s-%s%s-%s%s%s%s%s%s" % parts

# --- Audio bus setup / music toggle ---
func _setup_audio_buses() -> void:
	## Create a dedicated "Music" bus (routing to Master) if missing, then apply
	## the saved music_enabled state. BGM players are moved onto this bus by
	## _on_scene_node_added() as they enter the tree.
	_music_bus_idx = AudioServer.get_bus_index(MUSIC_BUS_NAME)
	if _music_bus_idx < 0:
		AudioServer.add_bus()
		_music_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(_music_bus_idx, MUSIC_BUS_NAME)
		AudioServer.set_bus_send(_music_bus_idx, "Master")
	_apply_music_setting()

func _apply_music_setting() -> void:
	if _music_bus_idx < 0:
		_music_bus_idx = AudioServer.get_bus_index(MUSIC_BUS_NAME)
	if _music_bus_idx >= 0:
		AudioServer.set_bus_mute(_music_bus_idx, not music_enabled)

func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	_apply_music_setting()
	save_game()

func _on_scene_node_added(node: Node) -> void:
	## Auto-route background-music players onto the Music bus so the toggle works
	## in every scene without per-scene edits. Matches BGM by stream path (the
	## four BGM oggs are res://art/audio/*bgm*.ogg).
	if node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		var stream := player.stream
		if stream != null and "bgm" in stream.resource_path:
			player.bus = MUSIC_BUS_NAME


func get_save_data() -> Dictionary:
	## Returns the full save-state dictionary (used by local save and cloud save).
	return {
		"level": mini(nowlevel, MAX_LEVEL),
		"highest_completed": highest_level_completed,
		"completed": nowlevel >= MAX_LEVEL or all_completed,
		"wallet": wallet,
		"upgrades": upgrades.duplicate(),
		"best_times": best_times.duplicate(),
		"best_stars": best_stars.duplicate(),
		"device_uuid": device_uuid,
		"nickname": nickname,
		"tutorial_shown": tutorial_shown,
		"welcome_shown": welcome_shown,
		"opening_intro_version": opening_intro_version,
		"first_flight_briefing_shown": first_flight_briefing_shown,
		"seen_hints": seen_hints.duplicate(),
		"difficulty": difficulty,
		"control_scheme": control_scheme,
		"orientation_pref": orientation_pref,
		"desktop_control": desktop_control,
		"tilt_sensitivity": tilt_sensitivity,
		"music_enabled": music_enabled,
		"selected_skin": selected_skin,
		"owned_skins": owned_skins.duplicate(),
		"endless_best_wave": endless_best_wave,
		"levels_unlocked": levels_unlocked,
		"total_crypto_earned": total_crypto_earned,
		"total_deaths": total_deaths,
		"landings_since_install": landings_since_install,
		"rate_prompt_shown": rate_prompt_shown,
		"ads_removed": ads_removed,
		"race_unlimited_cached": race_unlimited_cached,
		"race_free_utc_day": race_free_utc_day,
		"race_rewarded_credits": race_rewarded_credits,
		"granted_purchase_tokens": granted_purchase_tokens.duplicate(),
	}

func save_game() -> void:
	var data := get_save_data()
	var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	if f:
		f.store_line(JSON.stringify(data))
		f.close()
	# Back up to cloud (fire-and-forget)
	if is_inside_tree() and has_node("/root/CloudSave"):
		CloudSave.upload_save()

func restore_from_cloud() -> void:
	## Download the cloud save and overwrite local state if the cloud copy is newer.
	if has_node("/root/CloudSave"):
		CloudSave.save_downloaded.connect(_on_cloud_save_downloaded, CONNECT_ONE_SHOT)
		CloudSave.download_save()

func _on_cloud_save_downloaded(success: bool, data: Dictionary) -> void:
	if not success or data.is_empty():
		return
	# Only overwrite if cloud has more progress (higher wallet or more levels completed).
	# `<=` on highest, not `<`: with `<` a TIE on highest_level_completed made the
	# whole guard false, so a stale cloud copy with a SMALLER wallet overwrote the
	# local one — and save_game() below then persisted the loss and re-uploaded it.
	var cloud_highest := int(data.get("highest_completed", 0))
	var cloud_wallet := int(data.get("wallet", 0))
	if cloud_highest <= highest_level_completed and cloud_wallet <= wallet:
		return  # Local save is ahead — keep it
	# Paid entitlements are permanent: once bought they are never revoked, so a
	# cloud copy predating the purchase must not clear them. _apply_save_data
	# assigns them straight from the dict (correct when loading local disk, wrong
	# when merging a remote copy), and Android consumables are consumed at grant
	# time, so nothing would ever re-grant them. Lifetime counters only ever rise.
	var had_ads_removed := ads_removed
	var had_race_unlimited := race_unlimited_cached
	var had_total_earned := total_crypto_earned
	_apply_save_data(data)
	ads_removed = ads_removed or had_ads_removed
	race_unlimited_cached = race_unlimited_cached or had_race_unlimited
	total_crypto_earned = maxi(total_crypto_earned, had_total_earned)
	save_game()

func _apply_save_data(data: Dictionary) -> void:
	## Apply a save-data dictionary to the current state (used by load_game and cloud restore).
	nowlevel = int(data.get("level", 1))
	highest_level_completed = int(data.get("highest_completed", 0))
	all_completed = bool(data.get("completed", false))
	wallet = int(data.get("wallet", 0))
	var saved_upgrades = data.get("upgrades", {})
	if saved_upgrades is Dictionary:
		for key in upgrades.keys():
			if saved_upgrades.has(key):
				upgrades[key] = int(saved_upgrades[key])
	var saved_times = data.get("best_times", {})
	if saved_times is Dictionary:
		best_times = saved_times
	var saved_stars = data.get("best_stars", {})
	if saved_stars is Dictionary:
		best_stars = saved_stars
	device_uuid = str(data.get("device_uuid", device_uuid))
	nickname = str(data.get("nickname", nickname))
	tutorial_shown = bool(data.get("tutorial_shown", false))
	# welcome_shown: legacy saves predate this flag — assume returning players have already seen it
	# (any save with progress > 0 or a custom nickname means they've been past the prompt)
	if data.has("welcome_shown"):
		welcome_shown = bool(data["welcome_shown"])
	else:
		welcome_shown = int(data.get("highest_completed", 0)) > 0 or str(data.get("nickname", "")) != ""
	# The opening is versioned so returning players see a substantially changed
	# story beat exactly once. Legacy players who already completed the tutorial
	# should not be interrupted by the separate first-flight preflight.
	opening_intro_version = int(data.get("opening_intro_version", 0))
	if data.has("first_flight_briefing_shown"):
		first_flight_briefing_shown = bool(data["first_flight_briefing_shown"])
	else:
		first_flight_briefing_shown = tutorial_shown or highest_level_completed > 0
	# seen_hints: default to empty array for legacy saves that predate one-time hints
	seen_hints.clear()
	var saved_hints = data.get("seen_hints", [])
	if saved_hints is Array:
		for h in saved_hints:
			seen_hints.append(str(h))
	difficulty = int(data.get("difficulty", Difficulty.NORMAL))
	control_scheme = int(data.get("control_scheme", ControlScheme.TILT))
	orientation_pref = int(data.get("orientation_pref", Orientation.LANDSCAPE))
	# New A1/A3 settings — default for legacy saves that predate them.
	desktop_control = int(data.get("desktop_control", DesktopControl.KEYBOARD))
	tilt_sensitivity = float(data.get("tilt_sensitivity", TILT_SENSITIVITY_DEFAULT))
	music_enabled = bool(data.get("music_enabled", true))
	_apply_music_setting()
	selected_skin = str(data.get("selected_skin", "default"))
	var saved_skins = data.get("owned_skins", ["default"])
	if saved_skins is Array:
		owned_skins = saved_skins
		if "default" not in owned_skins:
			owned_skins.insert(0, "default")
	endless_best_wave = int(data.get("endless_best_wave", 0))
	levels_unlocked = bool(data.get("levels_unlocked", false))
	total_crypto_earned = int(data.get("total_crypto_earned", 0))
	total_deaths = int(data.get("total_deaths", 0))
	landings_since_install = int(data.get("landings_since_install", 0))
	rate_prompt_shown = bool(data.get("rate_prompt_shown", false))
	ads_removed = bool(data.get("ads_removed", false))
	race_unlimited_cached = bool(data.get("race_unlimited_cached", false))
	race_free_utc_day = str(data.get("race_free_utc_day", ""))
	race_rewarded_credits = clampi(int(data.get("race_rewarded_credits", 0)), 0, 1)
	granted_purchase_tokens.clear()
	for t in data.get("granted_purchase_tokens", []):
		granted_purchase_tokens.append(str(t))

func load_game() -> void:
	if not FileAccess.file_exists("user://savegame.json"):
		return
	var f := FileAccess.open("user://savegame.json", FileAccess.READ)
	if not f:
		return
	var json := JSON.new()
	var result := json.parse(f.get_as_text())
	f.close()
	if result != OK:
		return
	var data = json.get_data()
	if not data is Dictionary:
		return
	_apply_save_data(data)

func reset_progress() -> void:
	## Reset all progress and start fresh.
	## Keeps device_uuid so the cloud save is overwritten with the clean state on next save —
	## no orphaned cloud row, and no new endpoint required. Cloud overwrite is permanent.
	nowlevel = 1
	highest_level_completed = 0
	all_completed = false
	tutorial_shown = false
	welcome_shown = false
	opening_intro_version = 0
	first_flight_briefing_shown = false
	seen_hints.clear()
	endless_mode = false
	endless_wave = 1
	endless_best_wave = 0

	difficulty = Difficulty.NORMAL
	control_scheme = ControlScheme.TILT
	desktop_control = DesktopControl.KEYBOARD
	tilt_sensitivity = TILT_SENSITIVITY_DEFAULT
	music_enabled = true
	_apply_music_setting()

	wallet = 0
	for key in upgrades.keys():
		upgrades[key] = 0

	best_times.clear()
	best_stars.clear()

	selected_skin = "default"
	owned_skins = ["default"]

	total_crypto_earned = 0
	total_deaths = 0
	landings_since_install = 0
	rate_prompt_shown = false
	levels_unlocked = false
	# Paid/permanent benefits are not progression. Preserve ad removal and the
	# reconciled lifetime cache; provider restore remains the ultimate authority.

	# Keep existing device_uuid (so cloud row gets overwritten, not orphaned)
	if device_uuid == "":
		device_uuid = _generate_uuid()

	nickname = generate_random_nickname()

	# Save (writes local file + uploads to cloud, replacing old cloud save)
	save_game()
