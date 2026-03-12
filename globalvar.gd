extends Node
## Global game state singleton. Manages level progress, wallet, upgrades, save/load.
## Autoloaded — access from anywhere via `globalvar.xxx`.

# --- Signals ---
signal sendDeath
signal wallet_changed(new_total: int)

# --- Level state ---
var nowlevel: int = 1
var finaltime: float = 0.0
var all_completed: bool = false
var highest_level_completed: int = 0  # Tracks progress for level select
var tutorial_shown: bool = false  # Level 1 tutorial prompts (first-time only)

# --- Endless mode ---
var endless_mode: bool = false
var endless_wave: int = 1
var endless_best_wave: int = 0

# --- Difficulty ---
enum Difficulty { EASY, NORMAL, HARD }
var difficulty: int = Difficulty.NORMAL

const DIFFICULTY_NAMES := { 0: "Easy", 1: "Normal", 2: "Hard" }

## Spawn interval multiplier (higher = slower spawns = easier)
func get_spawn_interval_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 1.4
		Difficulty.HARD: return 0.7
		_: return 1.0

## Enemy speed multiplier
func get_enemy_speed_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 0.8
		Difficulty.HARD: return 1.2
		_: return 1.0

## Fuel drain multiplier (higher = drains faster = harder)
func get_fuel_drain_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 0.8
		Difficulty.HARD: return 1.3
		_: return 1.0

## Starting fuel bonus/penalty
func get_starting_fuel_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 1.2
		Difficulty.HARD: return 0.9
		_: return 1.0

# --- Level pack unlock ---
# Levels 1-4 are free. Levels 5+ require unlock via IAP or earning enough crypto.
const FREE_LEVELS := 4
const LEVEL_PACK_GRIND_COST := 2000  # Moonrocks earned (lifetime) to unlock for free
var levels_unlocked: bool = false  # true = all levels accessible
var total_crypto_earned: int = 0   # lifetime Moonrocks earned (never decreases)
var total_deaths: int = 0          # lifetime death count (for achievement skin)

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
	# Skull: 50 total deaths
	if total_deaths >= 50 and "skull" not in owned_skins:
		owned_skins.append("skull")
		PlayGamesManager.on_skin_owned(owned_skins.size())
	# Crystal Beetle: complete all 11 story levels
	if highest_level_completed >= 11 and "crystalbeetle" not in owned_skins:
		owned_skins.append("crystalbeetle")
		PlayGamesManager.on_skin_owned(owned_skins.size())
	# Steamboat: reach wave 10 in Endless Mode
	if endless_best_wave >= 10 and "steamboat" not in owned_skins:
		owned_skins.append("steamboat")
		PlayGamesManager.on_skin_owned(owned_skins.size())

func increment_deaths() -> void:
	total_deaths += 1
	check_achievement_skins()
	PlayGamesManager.on_death(total_deaths)
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
	save_game()
	return true

func select_skin(skin_id: String) -> void:
	if skin_id in owned_skins:
		selected_skin = skin_id
		save_game()

# --- Per-run tracking (reset each level start) ---
var level_crypto_collected: int = 0   # Moonrocks earned this run
var level_fuel_remaining: float = 0.0 # percentage at landing

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
	return 200.0 + upgrades["fuel_capacity"] * 40.0

func get_fuel_drain() -> float:
	return maxf(8.0 - upgrades["fuel_efficiency"] * 1.5, 2.0)

func get_crash_speed() -> float:
	var base: float = 100.0 + upgrades["armor"] * 50.0
	match difficulty:
		Difficulty.EASY: return base * 1.3
		Difficulty.HARD: return base * 0.85
		_: return base

func get_landing_speed() -> float:
	var base: float = 40.0 + upgrades["landing_gear"] * 20.0
	match difficulty:
		Difficulty.EASY: return base * 1.4
		Difficulty.HARD: return base * 0.8
		_: return base

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
	save_game()
	return true

func add_crypto(amount: int) -> void:
	wallet += amount
	level_crypto_collected += amount
	total_crypto_earned += amount
	wallet_changed.emit(wallet)
	PlayGamesManager.on_crypto_earned(total_crypto_earned)

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
	return LEVEL_SCENES.get(nowlevel + 1, "")

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
	check_achievement_skins()
	# Notify Play Games Services
	PlayGamesManager.on_level_completed(level, maxi(stars, int(best_stars.get(key, 0))))
	return stars

func reset_level_stats() -> void:
	## Call at the start of each level to reset per-run tracking.
	level_crypto_collected = 0
	level_fuel_remaining = 0.0
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
	load_game()
	# Ensure device has a UUID (generated once, persisted forever)
	if device_uuid == "":
		device_uuid = _generate_uuid()
	# Generate a random nickname on first launch
	if nickname == "" or nickname == "Cosmonaut":
		nickname = generate_random_nickname()
	save_game()

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

func get_save_data() -> Dictionary:
	## Returns the full save-state dictionary (used by local save and cloud save).
	highest_level_completed = maxi(highest_level_completed, nowlevel)
	return {
		"level": mini(nowlevel + 1, MAX_LEVEL),
		"highest_completed": highest_level_completed,
		"completed": nowlevel >= MAX_LEVEL or all_completed,
		"wallet": wallet,
		"upgrades": upgrades.duplicate(),
		"best_times": best_times.duplicate(),
		"best_stars": best_stars.duplicate(),
		"device_uuid": device_uuid,
		"nickname": nickname,
		"tutorial_shown": tutorial_shown,
		"difficulty": difficulty,
		"selected_skin": selected_skin,
		"owned_skins": owned_skins.duplicate(),
		"endless_best_wave": endless_best_wave,
		"levels_unlocked": levels_unlocked,
		"total_crypto_earned": total_crypto_earned,
		"total_deaths": total_deaths,
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
	# Only overwrite if cloud has more progress (higher wallet or more levels completed)
	var cloud_highest := int(data.get("highest_completed", 0))
	var cloud_wallet := int(data.get("wallet", 0))
	if cloud_highest < highest_level_completed and cloud_wallet <= wallet:
		return  # Local save is ahead — keep it
	_apply_save_data(data)
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
	difficulty = int(data.get("difficulty", Difficulty.NORMAL))
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
