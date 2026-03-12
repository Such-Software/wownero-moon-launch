class_name PlayGamesManagerTest
extends GdUnitTestSuite
## Unit tests for PlayGamesManager.gd
## On non-Android platforms, all PGS calls safely no-op.


# ==========================================================================
#  AVAILABILITY
# ==========================================================================

func test_is_available_returns_false_on_non_android() -> void:
	## PGS is only available on Android with the plugin + sign-in.
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_plugin_is_null_on_non_android() -> void:
	assert_that(PlayGamesManager._plugin).is_null()


func test_signed_in_is_false_on_non_android() -> void:
	assert_bool(PlayGamesManager._signed_in).is_false()


# ==========================================================================
#  NO-OP SAFETY — all public methods must not crash when unavailable
# ==========================================================================

func test_unlock_noop_when_unavailable() -> void:
	## unlock() must not crash when plugin is null.
	PlayGamesManager.unlock("first_landing")
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_increment_noop_when_unavailable() -> void:
	PlayGamesManager.increment("grim_reaper", 1)
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_set_steps_noop_when_unavailable() -> void:
	PlayGamesManager.set_steps("moonrock_hoarder", 100)
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_show_achievements_noop_when_unavailable() -> void:
	PlayGamesManager.show_achievements()
	assert_bool(PlayGamesManager.is_available()).is_false()





# ==========================================================================
#  GAME HOOK SAFETY — all hooks must not crash when unavailable
# ==========================================================================

func test_on_level_completed_noop_when_unavailable() -> void:
	PlayGamesManager.on_level_completed(1, 3)
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_on_death_noop_when_unavailable() -> void:
	PlayGamesManager.on_death(50)
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_on_endless_wave_noop_when_unavailable() -> void:
	PlayGamesManager.on_endless_wave(10)
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_on_crypto_earned_noop_when_unavailable() -> void:
	PlayGamesManager.on_crypto_earned(5000)
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_on_skin_owned_noop_when_unavailable() -> void:
	PlayGamesManager.on_skin_owned(5)
	assert_bool(PlayGamesManager.is_available()).is_false()


func test_on_upgrade_maxed_noop_when_unavailable() -> void:
	PlayGamesManager.on_upgrade_maxed()
	assert_bool(PlayGamesManager.is_available()).is_false()


# ==========================================================================
#  ACHIEVEMENT ID CATALOG
# ==========================================================================

func test_achievement_ids_has_expected_keys() -> void:
	var expected_keys := [
		"first_landing", "mars_explorer", "inner_planets", "gas_giants",
		"deep_space", "mothership_docked", "champion", "speed_demon",
		"endless_wave_10", "grim_reaper", "moonrock_hoarder",
		"skin_collector", "fully_upgraded",
	]
	for key in expected_keys:
		assert_bool(PlayGamesManager.ACHIEVEMENT_IDS.has(key)).is_true()


func test_achievement_ids_count() -> void:
	assert_int(PlayGamesManager.ACHIEVEMENT_IDS.size()).is_equal(13)



