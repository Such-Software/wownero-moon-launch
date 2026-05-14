extends Node
## PlayGamesManager — Google Play Games Services integration (Android only).
## Autoloaded singleton. All game code calls through this.
##
## Uses the GodotPlayGameServices plugin v3.2.0 by Jacob Ibáñez Sánchez.
## On non-Android platforms, every method safely no-ops.
##
## Achievement IDs from Google Play Console (Project 412379035812).
## Leaderboards use our own backend (api.such.software), not PGS.

## Achievement ID mapping — real IDs from Google Play Console.
const ACHIEVEMENT_IDS := {
	# Milestone achievements (unlocked on level completion)
	"first_landing":       "CgkIpPHSnYAMEAIQBQ",  # Complete Level 1 (Moon)
	"mars_explorer":       "CgkIpPHSnYAMEAIQCQ",  # Complete Level 2 (Mars)
	"inner_planets":       "CgkIpPHSnYAMEAIQAw",  # Complete Level 4 (Io)
	"gas_giants":          "CgkIpPHSnYAMEAIQBg",  # Complete Level 7 (Neptune)
	"deep_space":          "CgkIpPHSnYAMEAIQAA",  # Complete Level 9 (Asteroid Belt)
	"mothership_docked":   "CgkIpPHSnYAMEAIQDA",  # Complete Level 11 (all story)
	# Mastery achievements
	"champion":            "CgkIpPHSnYAMEAIQCg",  # 3 stars on all levels 1-11
	"speed_demon":         "CgkIpPHSnYAMEAIQBA",  # Beat any level 3-star time
	# Endurance / grind achievements
	"endless_wave_10":     "CgkIpPHSnYAMEAIQBw",  # Reach wave 10 in Endless
	"grim_reaper":         "CgkIpPHSnYAMEAIQAg",  # Die 50 times (incremental)
	"moonrock_hoarder":    "CgkIpPHSnYAMEAIQAQ",  # Earn 5000 lifetime Moonrocks (incremental)
	# Collection achievements
	"skin_collector":      "CgkIpPHSnYAMEAIQCw",  # Own 5 skins (incremental)
	"fully_upgraded":      "CgkIpPHSnYAMEAIQCA",  # Max out any 1 upgrade
}

var _plugin = null  # GodotPlayGameServices singleton (Android only)
var _signed_in: bool = false
var _last_reported_steps: Dictionary = {}  # Track last reported for incremental achievements


func _ready() -> void:
	if OS.get_name() != "Android":
		return
	if not Engine.has_singleton("GodotPlayGameServices"):
		push_warning("PlayGamesManager: GodotPlayGameServices plugin not found — PGS disabled")
		return
	_plugin = Engine.get_singleton("GodotPlayGameServices")
	_plugin.initialize()
	_plugin.userAuthenticated.connect(_on_user_authenticated)
	_plugin.isAuthenticated()


func _on_user_authenticated(is_authenticated: bool) -> void:
	if is_authenticated:
		_signed_in = true
		print("PlayGamesManager: user authenticated successfully")
	else:
		# Don't auto-pop the Play Games account picker — it would obscure
		# the welcome popup on first launch (and feels intrusive in general).
		# The user can trigger sign-in explicitly via the Achievements button
		# on the main menu (try_sign_in()).
		_signed_in = false
		print("PlayGamesManager: not authenticated — waiting for user to tap Achievements")


func try_sign_in() -> void:
	## Manually trigger sign-in (called from menu achievements button).
	if _plugin and not _signed_in:
		_plugin.signIn()
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			tree.create_timer(3.0).timeout.connect(func():
				if _plugin and not _signed_in:
					_plugin.isAuthenticated()
			)


# ── Public API — called from game code ────────────────────────────────

func is_available() -> bool:
	return _plugin != null and _signed_in


func unlock(achievement_key: String) -> void:
	## Unlock a one-time achievement by its key name (e.g. "first_landing").
	if not is_available():
		return
	var id: String = ACHIEVEMENT_IDS.get(achievement_key, "")
	if id.is_empty():
		return
	_plugin.unlockAchievement(id)


func increment(achievement_key: String, steps: int) -> void:
	## Increment an incremental achievement (e.g. "grim_reaper").
	if not is_available():
		return
	var id: String = ACHIEVEMENT_IDS.get(achievement_key, "")
	if id.is_empty():
		return
	_plugin.incrementAchievement(id, steps)


func set_steps(achievement_key: String, steps: int) -> void:
	## Set absolute step count for an incremental achievement.
	## Converted to increment delta since plugin v3.2.0 lacks setAchievementSteps.
	if not is_available():
		return
	var id: String = ACHIEVEMENT_IDS.get(achievement_key, "")
	if id.is_empty():
		return
	var last: int = _last_reported_steps.get(id, 0)
	var delta := steps - last
	if delta > 0:
		_plugin.incrementAchievement(id, delta)
		_last_reported_steps[id] = steps


func show_achievements() -> void:
	## Open the Google Play Games achievements UI overlay.
	if not is_available():
		return
	_plugin.showAchievements()


# ── Achievement check helpers — called from globalvar ──────────────────

func on_level_completed(level: int, stars: int) -> void:
	## Call after a level victory. Unlocks milestone + mastery achievements.
	# Milestone unlocks
	match level:
		1: unlock("first_landing")
		2: unlock("mars_explorer")
		4: unlock("inner_planets")
		7: unlock("gas_giants")
		9: unlock("deep_space")
		11: unlock("mothership_docked")

	# Speed demon — any 3-star finish
	if stars >= 3:
		unlock("speed_demon")

	# Champion — all levels 1-11 at 3 stars (checked by caller already)
	var all_3star := true
	for lvl in range(1, 12):
		if globalvar.get_best_stars(lvl) < 3:
			all_3star = false
			break
	if all_3star:
		unlock("champion")

	# Mothership also unlocks when highest_level_completed >= 11
	if globalvar.highest_level_completed >= 11:
		unlock("mothership_docked")


func on_death(total_deaths: int) -> void:
	## Call after a death. Drives incremental grim_reaper achievement.
	set_steps("grim_reaper", total_deaths)


func on_endless_wave(wave: int) -> void:
	## Call when a new endless wave is reached.
	if wave >= 10:
		unlock("endless_wave_10")


func on_crypto_earned(lifetime_total: int) -> void:
	## Call when crypto is earned. Drives incremental moonrock_hoarder.
	set_steps("moonrock_hoarder", lifetime_total)


func on_skin_owned(count: int) -> void:
	## Call when a skin is bought/unlocked. Drives incremental skin_collector.
	set_steps("skin_collector", count)


func on_upgrade_maxed() -> void:
	## Call when any upgrade reaches max level.
	unlock("fully_upgraded")
