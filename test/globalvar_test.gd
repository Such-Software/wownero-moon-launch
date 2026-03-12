class_name GlobalvarTest
extends GdUnitTestSuite
## Unit tests for globalvar.gd — pure logic functions, no scene tree needed.

# We test against the autoloaded globalvar singleton directly.
# Each test resets state via before_test() to ensure isolation.


func before_test() -> void:
	## Reset globalvar state before every test to ensure isolation.
	globalvar.wallet = 0
	globalvar.nowlevel = 1
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	globalvar.highest_level_completed = 0
	globalvar.all_completed = false
	globalvar.levels_unlocked = false
	globalvar.total_crypto_earned = 0
	globalvar.total_deaths = 0
	globalvar.selected_skin = "default"
	globalvar.owned_skins = ["default"]
	globalvar.endless_best_wave = 0
	globalvar.endless_mode = false
	globalvar.endless_wave = 1
	globalvar.tutorial_shown = false
	globalvar.best_times = {}
	globalvar.best_stars = {}
	globalvar.level_crypto_collected = 0
	globalvar.level_fuel_remaining = 0.0
	globalvar.has_checkpoint = false
	for key in globalvar.upgrades.keys():
		globalvar.upgrades[key] = 0


# ==========================================================================
#  DIFFICULTY MULTIPLIERS
# ==========================================================================

func test_spawn_interval_mult_easy() -> void:
	globalvar.difficulty = globalvar.Difficulty.EASY
	assert_float(globalvar.get_spawn_interval_mult()).is_equal(1.4)

func test_spawn_interval_mult_normal() -> void:
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	assert_float(globalvar.get_spawn_interval_mult()).is_equal(1.0)

func test_spawn_interval_mult_hard() -> void:
	globalvar.difficulty = globalvar.Difficulty.HARD
	assert_float(globalvar.get_spawn_interval_mult()).is_equal(0.7)

func test_enemy_speed_mult_easy() -> void:
	globalvar.difficulty = globalvar.Difficulty.EASY
	assert_float(globalvar.get_enemy_speed_mult()).is_equal(0.8)

func test_enemy_speed_mult_normal() -> void:
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	assert_float(globalvar.get_enemy_speed_mult()).is_equal(1.0)

func test_enemy_speed_mult_hard() -> void:
	globalvar.difficulty = globalvar.Difficulty.HARD
	assert_float(globalvar.get_enemy_speed_mult()).is_equal(1.2)

func test_fuel_drain_mult_easy() -> void:
	globalvar.difficulty = globalvar.Difficulty.EASY
	assert_float(globalvar.get_fuel_drain_mult()).is_equal(0.8)

func test_fuel_drain_mult_normal() -> void:
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	assert_float(globalvar.get_fuel_drain_mult()).is_equal(1.0)

func test_fuel_drain_mult_hard() -> void:
	globalvar.difficulty = globalvar.Difficulty.HARD
	assert_float(globalvar.get_fuel_drain_mult()).is_equal(1.3)

func test_starting_fuel_mult_easy() -> void:
	globalvar.difficulty = globalvar.Difficulty.EASY
	assert_float(globalvar.get_starting_fuel_mult()).is_equal(1.2)

func test_starting_fuel_mult_normal() -> void:
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	assert_float(globalvar.get_starting_fuel_mult()).is_equal(1.0)

func test_starting_fuel_mult_hard() -> void:
	globalvar.difficulty = globalvar.Difficulty.HARD
	assert_float(globalvar.get_starting_fuel_mult()).is_equal(0.9)


# ==========================================================================
#  LEVEL UNLOCK GATE
# ==========================================================================

func test_levels_1_to_4_always_unlocked() -> void:
	globalvar.levels_unlocked = false
	globalvar.total_crypto_earned = 0
	for level in range(1, 5):
		assert_bool(globalvar.is_level_unlocked(level)).is_true()

func test_level_5_locked_by_default() -> void:
	globalvar.levels_unlocked = false
	globalvar.total_crypto_earned = 0
	assert_bool(globalvar.is_level_unlocked(5)).is_false()

func test_level_5_unlocked_via_flag() -> void:
	globalvar.levels_unlocked = true
	assert_bool(globalvar.is_level_unlocked(5)).is_true()

func test_level_5_unlocked_via_grind() -> void:
	globalvar.levels_unlocked = false
	globalvar.total_crypto_earned = 2000
	assert_bool(globalvar.is_level_unlocked(5)).is_true()

func test_level_5_locked_just_under_grind() -> void:
	globalvar.levels_unlocked = false
	globalvar.total_crypto_earned = 1999
	assert_bool(globalvar.is_level_unlocked(5)).is_false()

func test_level_11_locked_without_unlock() -> void:
	globalvar.levels_unlocked = false
	globalvar.total_crypto_earned = 0
	assert_bool(globalvar.is_level_unlocked(11)).is_false()

func test_level_11_unlocked_via_flag() -> void:
	globalvar.levels_unlocked = true
	assert_bool(globalvar.is_level_unlocked(11)).is_true()


# ==========================================================================
#  LEVEL REACHABILITY (unlock + progression)
# ==========================================================================

func test_level_1_always_reachable() -> void:
	globalvar.highest_level_completed = 0
	globalvar.levels_unlocked = false
	globalvar.total_crypto_earned = 0
	assert_bool(globalvar.is_level_reachable(1)).is_true()

func test_level_2_reachable_after_beating_1() -> void:
	globalvar.highest_level_completed = 1
	assert_bool(globalvar.is_level_reachable(2)).is_true()

func test_level_2_not_reachable_before_beating_1() -> void:
	globalvar.highest_level_completed = 0
	assert_bool(globalvar.is_level_reachable(2)).is_false()

func test_level_5_not_reachable_without_unlock_even_if_progressed() -> void:
	globalvar.highest_level_completed = 4
	globalvar.levels_unlocked = false
	globalvar.total_crypto_earned = 0
	assert_bool(globalvar.is_level_reachable(5)).is_false()

func test_level_5_reachable_with_unlock_and_progression() -> void:
	globalvar.highest_level_completed = 4
	globalvar.levels_unlocked = true
	assert_bool(globalvar.is_level_reachable(5)).is_true()

func test_level_5_not_reachable_with_unlock_but_no_progression() -> void:
	globalvar.highest_level_completed = 2
	globalvar.levels_unlocked = true
	assert_bool(globalvar.is_level_reachable(5)).is_false()

func test_all_levels_reachable_when_fully_progressed_and_unlocked() -> void:
	globalvar.highest_level_completed = 11
	globalvar.levels_unlocked = true
	for level in range(1, 13):
		assert_bool(globalvar.is_level_reachable(level)).is_true()


# ==========================================================================
#  UPGRADE STATS
# ==========================================================================

func test_thrust_force_base() -> void:
	assert_float(globalvar.get_thrust_force()).is_equal(350.0)

func test_thrust_force_level_3() -> void:
	globalvar.upgrades["thrust"] = 3
	assert_float(globalvar.get_thrust_force()).is_equal(500.0)

func test_thrust_force_max_level() -> void:
	globalvar.upgrades["thrust"] = 5
	assert_float(globalvar.get_thrust_force()).is_equal(600.0)

func test_max_fuel_base() -> void:
	assert_float(globalvar.get_max_fuel()).is_equal(200.0)

func test_max_fuel_level_5() -> void:
	globalvar.upgrades["fuel_capacity"] = 5
	assert_float(globalvar.get_max_fuel()).is_equal(400.0)

func test_fuel_drain_base() -> void:
	assert_float(globalvar.get_fuel_drain()).is_equal(8.0)

func test_fuel_drain_level_3() -> void:
	globalvar.upgrades["fuel_efficiency"] = 3
	assert_float(globalvar.get_fuel_drain()).is_equal(3.5)

func test_fuel_drain_floor() -> void:
	# At level 5: 8.0 - 5*1.5 = 0.5, but floor is 2.0
	globalvar.upgrades["fuel_efficiency"] = 5
	assert_float(globalvar.get_fuel_drain()).is_equal(2.0)

func test_crash_speed_base_normal() -> void:
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	assert_float(globalvar.get_crash_speed()).is_equal(100.0)

func test_crash_speed_base_easy() -> void:
	globalvar.difficulty = globalvar.Difficulty.EASY
	assert_float(globalvar.get_crash_speed()).is_equal(130.0)

func test_crash_speed_base_hard() -> void:
	globalvar.difficulty = globalvar.Difficulty.HARD
	assert_float(globalvar.get_crash_speed()).is_equal(85.0)

func test_crash_speed_upgraded_normal() -> void:
	globalvar.upgrades["armor"] = 3
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	assert_float(globalvar.get_crash_speed()).is_equal(250.0)

func test_landing_speed_base_normal() -> void:
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	assert_float(globalvar.get_landing_speed()).is_equal(40.0)

func test_landing_speed_base_easy() -> void:
	globalvar.difficulty = globalvar.Difficulty.EASY
	assert_float(globalvar.get_landing_speed()).is_equal(56.0)

func test_landing_speed_base_hard() -> void:
	globalvar.difficulty = globalvar.Difficulty.HARD
	assert_float(globalvar.get_landing_speed()).is_equal(32.0)

func test_landing_speed_upgraded() -> void:
	globalvar.upgrades["landing_gear"] = 3
	globalvar.difficulty = globalvar.Difficulty.NORMAL
	assert_float(globalvar.get_landing_speed()).is_equal(100.0)

func test_shield_hits_base() -> void:
	assert_int(globalvar.get_shield_hits()).is_equal(0)

func test_shield_hits_level_3() -> void:
	globalvar.upgrades["shield"] = 3
	assert_int(globalvar.get_shield_hits()).is_equal(3)

func test_torque_base() -> void:
	assert_float(globalvar.get_torque()).is_equal(5000.0)

func test_torque_level_5() -> void:
	globalvar.upgrades["rotation"] = 5
	assert_float(globalvar.get_torque()).is_equal(10000.0)

func test_reverse_thrust_base() -> void:
	assert_float(globalvar.get_reverse_thrust_force()).is_equal(350.0)

func test_reverse_thrust_level_3() -> void:
	globalvar.upgrades["reverse_thrust"] = 3
	assert_float(globalvar.get_reverse_thrust_force()).is_equal(470.0)

func test_magnet_radius_disabled() -> void:
	assert_float(globalvar.get_magnet_radius()).is_equal(0.0)

func test_magnet_radius_level_1() -> void:
	globalvar.upgrades["magnet"] = 1
	assert_float(globalvar.get_magnet_radius()).is_equal(80.0)

func test_magnet_radius_level_5() -> void:
	globalvar.upgrades["magnet"] = 5
	assert_float(globalvar.get_magnet_radius()).is_equal(200.0)


# ==========================================================================
#  UPGRADE COSTS & PURCHASE
# ==========================================================================

func test_upgrade_cost_level_0() -> void:
	assert_int(globalvar.get_upgrade_cost("thrust")).is_equal(50)

func test_upgrade_cost_level_1() -> void:
	globalvar.upgrades["thrust"] = 1
	assert_int(globalvar.get_upgrade_cost("thrust")).is_equal(100)

func test_upgrade_cost_level_4() -> void:
	globalvar.upgrades["thrust"] = 4
	assert_int(globalvar.get_upgrade_cost("thrust")).is_equal(250)

func test_can_buy_upgrade_with_enough_wallet() -> void:
	globalvar.wallet = 50
	assert_bool(globalvar.can_buy_upgrade("thrust")).is_true()

func test_can_buy_upgrade_insufficient_wallet() -> void:
	globalvar.wallet = 49
	assert_bool(globalvar.can_buy_upgrade("thrust")).is_false()

func test_can_buy_upgrade_at_max_level() -> void:
	globalvar.upgrades["thrust"] = 5
	globalvar.wallet = 999999
	assert_bool(globalvar.can_buy_upgrade("thrust")).is_false()

func test_buy_upgrade_success() -> void:
	globalvar.wallet = 100
	var result := globalvar.buy_upgrade("thrust")
	assert_bool(result).is_true()
	assert_int(globalvar.wallet).is_equal(50)
	assert_int(globalvar.upgrades["thrust"]).is_equal(1)

func test_buy_upgrade_failure_broke() -> void:
	globalvar.wallet = 10
	var result := globalvar.buy_upgrade("thrust")
	assert_bool(result).is_false()
	assert_int(globalvar.wallet).is_equal(10)
	assert_int(globalvar.upgrades["thrust"]).is_equal(0)

func test_buy_upgrade_failure_max_level() -> void:
	globalvar.upgrades["thrust"] = 5
	globalvar.wallet = 999999
	var result := globalvar.buy_upgrade("thrust")
	assert_bool(result).is_false()
	assert_int(globalvar.upgrades["thrust"]).is_equal(5)

func test_buy_upgrade_sequential_costs() -> void:
	# Buy thrust from level 0 to 3, verify wallet deductions
	globalvar.wallet = 1000
	globalvar.buy_upgrade("thrust")  # cost 50, wallet=950, level=1
	assert_int(globalvar.wallet).is_equal(950)
	globalvar.buy_upgrade("thrust")  # cost 100, wallet=850, level=2
	assert_int(globalvar.wallet).is_equal(850)
	globalvar.buy_upgrade("thrust")  # cost 150, wallet=700, level=3
	assert_int(globalvar.wallet).is_equal(700)
	assert_int(globalvar.upgrades["thrust"]).is_equal(3)


# ==========================================================================
#  CRYPTO ACCOUNTING
# ==========================================================================

func test_add_crypto_increases_wallet() -> void:
	globalvar.add_crypto(100)
	assert_int(globalvar.wallet).is_equal(100)

func test_add_crypto_increases_level_crypto() -> void:
	globalvar.add_crypto(50)
	assert_int(globalvar.level_crypto_collected).is_equal(50)

func test_add_crypto_increases_total() -> void:
	globalvar.add_crypto(75)
	assert_int(globalvar.total_crypto_earned).is_equal(75)

func test_add_crypto_accumulates() -> void:
	globalvar.add_crypto(30)
	globalvar.add_crypto(70)
	assert_int(globalvar.wallet).is_equal(100)
	assert_int(globalvar.total_crypto_earned).is_equal(100)

func test_total_crypto_never_decreases_after_purchase() -> void:
	globalvar.add_crypto(500)
	globalvar.buy_upgrade("thrust")  # costs 50
	assert_int(globalvar.wallet).is_equal(450)
	assert_int(globalvar.total_crypto_earned).is_equal(500)  # unchanged


# ==========================================================================
#  SKIN PURCHASE & SELECTION
# ==========================================================================

func test_can_buy_skin_default_already_owned() -> void:
	assert_bool(globalvar.can_buy_skin("default")).is_false()

func test_can_buy_skin_enough_wallet() -> void:
	globalvar.wallet = 200
	assert_bool(globalvar.can_buy_skin("retro")).is_true()

func test_can_buy_skin_insufficient_wallet() -> void:
	globalvar.wallet = 199
	assert_bool(globalvar.can_buy_skin("retro")).is_false()

func test_can_buy_skin_nonexistent() -> void:
	globalvar.wallet = 999999
	assert_bool(globalvar.can_buy_skin("DOESNOTEXIST")).is_false()

func test_buy_skin_success() -> void:
	globalvar.wallet = 200
	var result := globalvar.buy_skin("retro")
	assert_bool(result).is_true()
	assert_int(globalvar.wallet).is_equal(0)
	assert_bool("retro" in globalvar.owned_skins).is_true()
	assert_str(globalvar.selected_skin).is_equal("retro")

func test_buy_skin_already_owned() -> void:
	globalvar.owned_skins.append("retro")
	globalvar.wallet = 200
	var result := globalvar.buy_skin("retro")
	assert_bool(result).is_false()
	assert_int(globalvar.wallet).is_equal(200)  # not deducted

func test_select_skin_owned() -> void:
	globalvar.owned_skins.append("retro")
	globalvar.select_skin("retro")
	assert_str(globalvar.selected_skin).is_equal("retro")

func test_select_skin_not_owned() -> void:
	globalvar.select_skin("retro")
	assert_str(globalvar.selected_skin).is_equal("default")  # unchanged

func test_get_skin_texture_path() -> void:
	assert_str(globalvar.get_skin_texture_path()).is_equal("res://art/ship/rocket.png")

func test_get_skin_texture_path_after_select() -> void:
	globalvar.owned_skins.append("gold")
	globalvar.selected_skin = "gold"
	assert_str(globalvar.get_skin_texture_path()).is_equal("res://art/ship/skins/gold.png")


# ==========================================================================
#  STAR RATING
# ==========================================================================

func test_stars_fast_time_level_1() -> void:
	assert_int(globalvar.compute_stars(1, 15.0, 10.0, 0)).is_equal(3)

func test_stars_medium_time_level_1() -> void:
	assert_int(globalvar.compute_stars(1, 25.0, 10.0, 0)).is_equal(2)

func test_stars_slow_time_level_1() -> void:
	assert_int(globalvar.compute_stars(1, 50.0, 10.0, 0)).is_equal(1)

func test_stars_fuel_bonus_bumps_1_to_2() -> void:
	assert_int(globalvar.compute_stars(1, 50.0, 55.0, 0)).is_equal(2)

func test_stars_fuel_bonus_bumps_2_to_3() -> void:
	assert_int(globalvar.compute_stars(1, 25.0, 55.0, 0)).is_equal(3)

func test_stars_fuel_bonus_capped_at_3() -> void:
	# Already 3 stars, fuel bonus shouldn't make it 4
	assert_int(globalvar.compute_stars(1, 15.0, 90.0, 0)).is_equal(3)

func test_stars_at_exact_threshold() -> void:
	# Exactly at 3-star threshold (20.0 for level 1)
	assert_int(globalvar.compute_stars(1, 20.0, 10.0, 0)).is_equal(3)

func test_stars_at_exact_2star_threshold() -> void:
	# Exactly at 2x threshold (40.0 for level 1)
	assert_int(globalvar.compute_stars(1, 40.0, 10.0, 0)).is_equal(2)

func test_stars_just_over_2star_threshold() -> void:
	assert_int(globalvar.compute_stars(1, 40.1, 10.0, 0)).is_equal(1)

func test_record_level_result_new_best() -> void:
	var stars := globalvar.record_level_result(1, 18.0, 20.0, 50)
	assert_int(stars).is_equal(3)
	assert_float(globalvar.get_best_time(1)).is_equal(18.0)
	assert_int(globalvar.get_best_stars(1)).is_equal(3)

func test_record_level_result_no_overwrite_worse() -> void:
	globalvar.record_level_result(1, 18.0, 20.0, 50)
	globalvar.record_level_result(1, 30.0, 20.0, 50)  # slower time
	assert_float(globalvar.get_best_time(1)).is_equal(18.0)  # kept old best

func test_record_level_result_overwrite_better_time() -> void:
	globalvar.record_level_result(1, 18.0, 20.0, 50)
	globalvar.record_level_result(1, 10.0, 20.0, 50)  # faster
	assert_float(globalvar.get_best_time(1)).is_equal(10.0)

func test_record_level_result_keeps_better_stars() -> void:
	globalvar.record_level_result(1, 15.0, 20.0, 50)  # 3 stars
	globalvar.record_level_result(1, 50.0, 10.0, 50)  # 1 star
	assert_int(globalvar.get_best_stars(1)).is_equal(3)  # kept 3

func test_get_best_time_no_record() -> void:
	assert_float(globalvar.get_best_time(99)).is_equal(-1.0)

func test_get_best_stars_no_record() -> void:
	assert_int(globalvar.get_best_stars(99)).is_equal(0)


# ==========================================================================
#  ACHIEVEMENT SKINS
# ==========================================================================

func test_champion_skin_not_unlocked_without_3stars() -> void:
	globalvar.check_achievement_skins()
	assert_bool("champion" in globalvar.owned_skins).is_false()

func test_champion_skin_unlocked_with_all_3stars() -> void:
	for level in range(1, 12):
		globalvar.best_stars[str(level)] = 3
	globalvar.check_achievement_skins()
	assert_bool("champion" in globalvar.owned_skins).is_true()

func test_champion_skin_not_duplicated() -> void:
	for level in range(1, 12):
		globalvar.best_stars[str(level)] = 3
	globalvar.check_achievement_skins()
	globalvar.check_achievement_skins()  # call again
	var count := globalvar.owned_skins.count("champion")
	assert_int(count).is_equal(1)

func test_skull_skin_not_unlocked_under_50_deaths() -> void:
	globalvar.total_deaths = 49
	globalvar.check_achievement_skins()
	assert_bool("skull" in globalvar.owned_skins).is_false()

func test_skull_skin_unlocked_at_50_deaths() -> void:
	globalvar.total_deaths = 50
	globalvar.check_achievement_skins()
	assert_bool("skull" in globalvar.owned_skins).is_true()

func test_skull_skin_not_duplicated() -> void:
	globalvar.total_deaths = 50
	globalvar.check_achievement_skins()
	globalvar.check_achievement_skins()
	var count := globalvar.owned_skins.count("skull")
	assert_int(count).is_equal(1)

func test_increment_deaths() -> void:
	globalvar.total_deaths = 0
	globalvar.increment_deaths()
	assert_int(globalvar.total_deaths).is_equal(1)


# ==========================================================================
#  NICKNAME GENERATION
# ==========================================================================

func test_generate_nickname_format() -> void:
	var nick := globalvar.generate_random_nickname()
	assert_str(nick).is_not_empty()
	# Should be at least 5 chars (shortest prefix "Zen" + shortest suffix "Fox" = 6)
	assert_bool(nick.length() >= 5).is_true()

func test_generate_nickname_uses_valid_parts() -> void:
	# Run 20 times and verify each contains a valid prefix and suffix
	for _i in 20:
		var nick := globalvar.generate_random_nickname()
		var found_prefix := false
		for p in globalvar.NICK_PREFIXES:
			if nick.begins_with(p):
				found_prefix = true
				var remainder := nick.substr(p.length())
				assert_bool(remainder in globalvar.NICK_SUFFIXES).is_true()
				break
		assert_bool(found_prefix).is_true()


# ==========================================================================
#  LEVEL ROUTING
# ==========================================================================

func test_get_level_scene_level_1() -> void:
	var scene := globalvar.get_level_scene(1)
	assert_str(scene).is_equal("res://game/levels/1/Level1.tscn")
	assert_bool(globalvar.endless_mode).is_false()

func test_get_level_scene_level_12_sets_endless() -> void:
	var scene := globalvar.get_level_scene(12)
	assert_str(scene).is_equal("res://game/levels/12/EndlessMode.tscn")
	assert_bool(globalvar.endless_mode).is_true()
	assert_int(globalvar.endless_wave).is_equal(1)

func test_get_level_scene_invalid_fallback() -> void:
	var scene := globalvar.get_level_scene(999)
	assert_str(scene).is_equal("res://game/levels/1/Level1.tscn")

func test_has_next_level_true() -> void:
	globalvar.nowlevel = 5
	assert_bool(globalvar.has_next_level()).is_true()

func test_has_next_level_false_at_max() -> void:
	globalvar.nowlevel = 12
	assert_bool(globalvar.has_next_level()).is_false()


# ==========================================================================
#  PER-RUN RESET
# ==========================================================================

func test_reset_level_stats() -> void:
	globalvar.level_crypto_collected = 500
	globalvar.level_fuel_remaining = 75.0
	globalvar.has_checkpoint = true
	globalvar.checkpoint_fuel = 100.0
	globalvar.checkpoint_planet_name = "Mars"
	globalvar.reset_level_stats()
	assert_int(globalvar.level_crypto_collected).is_equal(0)
	assert_float(globalvar.level_fuel_remaining).is_equal(0.0)
	assert_bool(globalvar.has_checkpoint).is_false()
	assert_float(globalvar.checkpoint_fuel).is_equal(0.0)
	assert_str(globalvar.checkpoint_planet_name).is_equal("")


# ==========================================================================
#  CHECKPOINT
# ==========================================================================

func test_save_checkpoint() -> void:
	globalvar.save_checkpoint(Vector2(100, 200), Vector2(10, -5), 80.0, "Venus")
	assert_bool(globalvar.has_checkpoint).is_true()
	assert_float(globalvar.checkpoint_fuel).is_equal(80.0)
	assert_str(globalvar.checkpoint_planet_name).is_equal("Venus")


# ==========================================================================
#  SAVE / LOAD ROUNDTRIP
# ==========================================================================

func test_get_save_data_contains_all_keys() -> void:
	var data := globalvar.get_save_data()
	var required_keys := [
		"level", "highest_completed", "completed", "wallet", "upgrades",
		"best_times", "best_stars", "device_uuid", "nickname", "tutorial_shown",
		"difficulty", "selected_skin", "owned_skins", "endless_best_wave",
		"levels_unlocked", "total_crypto_earned", "total_deaths",
	]
	for key in required_keys:
		assert_bool(data.has(key)).is_true()

func test_save_data_roundtrip() -> void:
	# Set up interesting state
	globalvar.wallet = 1234
	globalvar.nowlevel = 5
	globalvar.highest_level_completed = 4
	globalvar.difficulty = globalvar.Difficulty.HARD
	globalvar.upgrades["thrust"] = 3
	globalvar.upgrades["shield"] = 2
	globalvar.owned_skins = ["default", "retro"]
	globalvar.selected_skin = "retro"
	globalvar.total_crypto_earned = 800
	globalvar.total_deaths = 25
	globalvar.best_times["1"] = 18.5
	globalvar.best_stars["1"] = 3
	globalvar.levels_unlocked = true
	globalvar.endless_best_wave = 7

	var data := globalvar.get_save_data()

	# Reset everything
	before_test()

	# Restore from save data
	globalvar._apply_save_data(data)

	# Note: get_save_data() stores level as mini(nowlevel+1, MAX_LEVEL),
	# so saved level=6 when nowlevel=5. _apply_save_data sets nowlevel=6.
	# Also: get_save_data() sets highest_level_completed = max(highest, nowlevel),
	# so with nowlevel=5 it bumps highest_level_completed from 4 to 5.
	assert_int(globalvar.wallet).is_equal(1234)
	assert_int(globalvar.highest_level_completed).is_equal(5)
	assert_int(globalvar.difficulty).is_equal(globalvar.Difficulty.HARD)
	assert_int(globalvar.upgrades["thrust"]).is_equal(3)
	assert_int(globalvar.upgrades["shield"]).is_equal(2)
	assert_bool("retro" in globalvar.owned_skins).is_true()
	assert_str(globalvar.selected_skin).is_equal("retro")
	assert_int(globalvar.total_crypto_earned).is_equal(800)
	assert_int(globalvar.total_deaths).is_equal(25)
	assert_bool(globalvar.levels_unlocked).is_true()
	assert_int(globalvar.endless_best_wave).is_equal(7)

func test_apply_save_data_missing_keys_use_defaults() -> void:
	# Simulate an old save with minimal data
	globalvar._apply_save_data({"level": 3, "wallet": 100})
	assert_int(globalvar.wallet).is_equal(100)
	assert_int(globalvar.total_deaths).is_equal(0)  # default
	assert_bool(globalvar.levels_unlocked).is_false()  # default
	assert_int(globalvar.total_crypto_earned).is_equal(0)  # default
	assert_str(globalvar.selected_skin).is_equal("default")

func test_apply_save_data_default_skin_always_present() -> void:
	globalvar._apply_save_data({"owned_skins": ["retro"]})
	assert_bool("default" in globalvar.owned_skins).is_true()

func test_apply_save_data_new_upgrades_stay_zero() -> void:
	# Old save has only some upgrades
	globalvar._apply_save_data({
		"upgrades": {"thrust": 3, "fuel_capacity": 2}
	})
	assert_int(globalvar.upgrades["thrust"]).is_equal(3)
	assert_int(globalvar.upgrades["fuel_capacity"]).is_equal(2)
	assert_int(globalvar.upgrades["cannon"]).is_equal(0)  # not in save
	assert_int(globalvar.upgrades["emp"]).is_equal(0)     # not in save


# ==========================================================================
#  PLATFORM STRING
# ==========================================================================

func test_get_platform_string_not_empty() -> void:
	var plat := globalvar.get_platform_string()
	assert_str(plat).is_not_empty()


# ==========================================================================
#  UUID GENERATION
# ==========================================================================

func test_uuid_format() -> void:
	var uuid := globalvar._generate_uuid()
	# UUID v4 format: 8-4-4-4-12 hex chars
	var parts := uuid.split("-")
	assert_int(parts.size()).is_equal(5)
	assert_int(parts[0].length()).is_equal(8)
	assert_int(parts[1].length()).is_equal(4)
	assert_int(parts[2].length()).is_equal(4)
	assert_int(parts[3].length()).is_equal(4)
	assert_int(parts[4].length()).is_equal(12)

func test_uuid_uniqueness() -> void:
	var uuid1 := globalvar._generate_uuid()
	var uuid2 := globalvar._generate_uuid()
	assert_str(uuid1).is_not_equal(uuid2)
