extends Node
## PlayGamesManager — Google Play Games Services integration (Android only).
## Autoloaded singleton. All game code calls through this.
##
## Uses the PGSGP (StudioAdriatic) plugin for Godot 4.x.
## On non-Android platforms, every method safely no-ops.
##
## Achievement IDs are placeholders — replace with real IDs from Google Play Console.
## Leaderboards use our own backend (api.such.software), not PGS.

## Achievement ID mapping — replace these with real IDs from Play Console.
## Create these achievements at: Play Console > Play Games Services > Achievements
const ACHIEVEMENT_IDS := {
	# Milestone achievements (unlocked on level completion)
	"first_landing":       "REPLACE_WITH_PLAY_CONSOLE_ID",  # Complete Level 1 (Moon)
	"mars_explorer":       "REPLACE_WITH_PLAY_CONSOLE_ID",  # Complete Level 2 (Mars)
	"inner_planets":       "REPLACE_WITH_PLAY_CONSOLE_ID",  # Complete Level 4 (Io)
	"gas_giants":          "REPLACE_WITH_PLAY_CONSOLE_ID",  # Complete Level 7 (Neptune)
	"deep_space":          "REPLACE_WITH_PLAY_CONSOLE_ID",  # Complete Level 9 (Asteroid Belt)
	"mothership_docked":   "REPLACE_WITH_PLAY_CONSOLE_ID",  # Complete Level 11 (all story)
	# Mastery achievements
	"champion":            "REPLACE_WITH_PLAY_CONSOLE_ID",  # 3 stars on all levels 1-11
	"speed_demon":         "REPLACE_WITH_PLAY_CONSOLE_ID",  # Beat any level 3-star time
	# Endurance / grind achievements
	"endless_wave_10":     "REPLACE_WITH_PLAY_CONSOLE_ID",  # Reach wave 10 in Endless
	"grim_reaper":         "REPLACE_WITH_PLAY_CONSOLE_ID",  # Die 50 times (incremental)
	"moonrock_hoarder":    "REPLACE_WITH_PLAY_CONSOLE_ID",  # Earn 5000 lifetime Moonrocks (incremental)
	# Collection achievements
	"skin_collector":      "REPLACE_WITH_PLAY_CONSOLE_ID",  # Own 5 skins (incremental)
	"fully_upgraded":      "REPLACE_WITH_PLAY_CONSOLE_ID",  # Max out any 1 upgrade
}

var _plugin = null  # GodotPlayGamesServices singleton (Android only)
var _signed_in: bool = false


func _ready() -> void:
	if OS.get_name() != "Android":
		return
	if not Engine.has_singleton("GodotPlayGamesServices"):
		push_warning("PlayGamesManager: PGSGP plugin not found — PGS disabled")
		return
	_plugin = Engine.get_singleton("GodotPlayGamesServices")
	_plugin.init(false, false, false, "")
	_plugin.connect("_on_sign_in_success", _on_sign_in_success)
	_plugin.connect("_on_sign_in_failed", _on_sign_in_failed)
	_plugin.signIn()


func _on_sign_in_success(_user_profile: String) -> void:
	_signed_in = true


func _on_sign_in_failed(_error_code: int) -> void:
	push_warning("PlayGamesManager: sign-in failed (code %d)" % _error_code)
	_signed_in = false


# ── Public API — called from game code ────────────────────────────────

func is_available() -> bool:
	return _plugin != null and _signed_in


func unlock(achievement_key: String) -> void:
	## Unlock a one-time achievement by its key name (e.g. "first_landing").
	if not is_available():
		return
	var id: String = ACHIEVEMENT_IDS.get(achievement_key, "")
	if id.is_empty() or id == "REPLACE_WITH_PLAY_CONSOLE_ID":
		return
	_plugin.unlockAchievement(id)


func increment(achievement_key: String, steps: int) -> void:
	## Increment an incremental achievement (e.g. "grim_reaper").
	if not is_available():
		return
	var id: String = ACHIEVEMENT_IDS.get(achievement_key, "")
	if id.is_empty() or id == "REPLACE_WITH_PLAY_CONSOLE_ID":
		return
	_plugin.incrementAchievement(id, steps)


func set_steps(achievement_key: String, steps: int) -> void:
	## Set absolute step count for an incremental achievement.
	if not is_available():
		return
	var id: String = ACHIEVEMENT_IDS.get(achievement_key, "")
	if id.is_empty() or id == "REPLACE_WITH_PLAY_CONSOLE_ID":
		return
	_plugin.setAchievementSteps(id, steps)


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
