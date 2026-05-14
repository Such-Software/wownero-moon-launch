extends Node
## GameCenterManager — Apple Game Center integration (iOS only).
## Autoloaded singleton. Mirrors PlayGamesManager API for cross-platform use.
##
## Uses Godot's built-in GameCenter singleton (iOS export entitlement required).
## On non-iOS platforms, every method safely no-ops.
##
## Achievement IDs must match those configured in App Store Connect.
## Use reverse-domain format: com.suchsoftware.suchmoonlaunch.achievement_key

## Achievement ID mapping — set these to match App Store Connect IDs.
## Convention: bundle_id + "." + achievement_key
const ACHIEVEMENT_IDS := {
	# Milestone achievements (unlocked on level completion)
	"first_landing":       "com.suchsoftware.suchmoonlaunch.first_landing",
	"mars_explorer":       "com.suchsoftware.suchmoonlaunch.mars_explorer",
	"inner_planets":       "com.suchsoftware.suchmoonlaunch.inner_planets",
	"gas_giants":          "com.suchsoftware.suchmoonlaunch.gas_giants",
	"deep_space":          "com.suchsoftware.suchmoonlaunch.deep_space",
	"mothership_docked":   "com.suchsoftware.suchmoonlaunch.mothership_docked",
	# Mastery achievements
	"champion":            "com.suchsoftware.suchmoonlaunch.champion",
	"speed_demon":         "com.suchsoftware.suchmoonlaunch.speed_demon",
	# Endurance / grind achievements
	"endless_wave_10":     "com.suchsoftware.suchmoonlaunch.endless_wave_10",
	"grim_reaper":         "com.suchsoftware.suchmoonlaunch.grim_reaper",
	"moonrock_hoarder":    "com.suchsoftware.suchmoonlaunch.moonrock_hoarder",
	# Collection achievements
	"skin_collector":      "com.suchsoftware.suchmoonlaunch.skin_collector",
	"fully_upgraded":      "com.suchsoftware.suchmoonlaunch.fully_upgraded",
}

## Step targets for incremental achievements (Game Center uses percentComplete 0-100).
const ACHIEVEMENT_STEPS := {
	"grim_reaper": 50,
	"moonrock_hoarder": 5000,
	"skin_collector": 5,
}

var _authenticated: bool = false


func _ready() -> void:
	if OS.get_name() != "iOS":
		return
	if not Engine.has_singleton("GameCenter"):
		push_warning("GameCenterManager: GameCenter singleton not found")
		return
	var gc = Engine.get_singleton("GameCenter")
	gc.authenticate()
	gc.connect("WapitatAuthenticated", _on_authenticated)
	gc.connect("authentication_result", _on_auth_result)


func _on_authenticated() -> void:
	_authenticated = true


func _on_auth_result(result: Dictionary) -> void:
	if result.get("type", "") == "authentication" and result.get("result", "") == "ok":
		_authenticated = true
	else:
		push_warning("GameCenterManager: auth failed — %s" % str(result))
		_authenticated = false


# ── Public API — same interface as PlayGamesManager ───────────────────

func is_available() -> bool:
	return _authenticated and Engine.has_singleton("GameCenter")


func unlock(achievement_key: String) -> void:
	## Unlock a one-time achievement (sets percentComplete to 100).
	if not is_available():
		return
	var id: String = ACHIEVEMENT_IDS.get(achievement_key, "")
	if id.is_empty():
		return
	var gc = Engine.get_singleton("GameCenter")
	gc.post_achievement({"name": id, "progress": 100.0, "show_completion_banner": true})


func increment(achievement_key: String, steps: int) -> void:
	## Increment an incremental achievement. Game Center uses percent, so we convert.
	if not is_available():
		return
	var id: String = ACHIEVEMENT_IDS.get(achievement_key, "")
	if id.is_empty():
		return
	var target: int = ACHIEVEMENT_STEPS.get(achievement_key, 1)
	var percent: float = clampf(float(steps) / float(target) * 100.0, 0.0, 100.0)
	var gc = Engine.get_singleton("GameCenter")
	gc.post_achievement({"name": id, "progress": percent, "show_completion_banner": true})


func set_steps(achievement_key: String, steps: int) -> void:
	## Set absolute step count — converts to percent for Game Center.
	increment(achievement_key, steps)


func show_achievements() -> void:
	## Open the Game Center achievements overlay.
	if not is_available():
		return
	var gc = Engine.get_singleton("GameCenter")
	gc.show_game_center({"view": "achievements"})


# ── Achievement check helpers — identical to PlayGamesManager ─────────

func on_level_completed(level: int, stars: int) -> void:
	match level:
		1: unlock("first_landing")
		2: unlock("mars_explorer")
		4: unlock("inner_planets")
		7: unlock("gas_giants")
		9: unlock("deep_space")
		11: unlock("mothership_docked")

	if stars >= 3:
		unlock("speed_demon")

	var all_3star := true
	for lvl in range(1, 12):
		if globalvar.get_best_stars(lvl) < 3:
			all_3star = false
			break
	if all_3star:
		unlock("champion")

	if globalvar.highest_level_completed >= 11:
		unlock("mothership_docked")


func on_death(total_deaths: int) -> void:
	set_steps("grim_reaper", total_deaths)


func on_endless_wave(wave: int) -> void:
	if wave >= 10:
		unlock("endless_wave_10")


func on_crypto_earned(lifetime_total: int) -> void:
	set_steps("moonrock_hoarder", lifetime_total)


func on_skin_owned(count: int) -> void:
	set_steps("skin_collector", count)


func on_upgrade_maxed() -> void:
	unlock("fully_upgraded")
