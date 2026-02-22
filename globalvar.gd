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

# --- Per-run tracking (reset each level start) ---
var level_crypto_collected: int = 0   # WOW earned this run
var level_fuel_remaining: float = 0.0 # percentage at landing

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
var wallet: int = 0  # WOW balance (all crypto converted to WOW on pickup)

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
}

# --- Upgrade costs (WOW) — cost increases per level ---
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
}

# --- Derived stats (computed from upgrades) ---
func get_thrust_force() -> float:
	return 350.0 + upgrades["thrust"] * 50.0

func get_max_fuel() -> float:
	return 200.0 + upgrades["fuel_capacity"] * 40.0

func get_fuel_drain() -> float:
	return maxf(8.0 - upgrades["fuel_efficiency"] * 1.5, 2.0)

func get_crash_speed() -> float:
	return 100.0 + upgrades["armor"] * 50.0

func get_landing_speed() -> float:
	return 40.0 + upgrades["landing_gear"] * 20.0

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
	save_game()
	return true

func add_crypto(amount: int) -> void:
	wallet += amount
	level_crypto_collected += amount
	wallet_changed.emit(wallet)

# --- Level config (eliminates hardcoded match statements) ---
const LEVEL_SCENES := {
	1: "res://game/levels/1/Level1.tscn",
	2: "res://game/levels/2/Level2.tscn",
	3: "res://game/levels/3/Level3.tscn",
	4: "res://game/levels/4/Level4.tscn",
}
const MAX_LEVEL := 4  # Raise this as new levels are added

const LEVEL_NAMES := {
	1: "Moon",
	2: "Mars",
	3: "Venus",
	4: "Io",
}

func get_level_scene(level: int) -> String:
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
	return stars

func reset_level_stats() -> void:
	## Call at the start of each level to reset per-run tracking.
	level_crypto_collected = 0
	level_fuel_remaining = 0.0

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

func save_game() -> void:
	highest_level_completed = maxi(highest_level_completed, nowlevel)
	var data := {
		"level": mini(nowlevel + 1, MAX_LEVEL),
		"highest_completed": highest_level_completed,
		"completed": nowlevel >= MAX_LEVEL or all_completed,
		"wallet": wallet,
		"upgrades": upgrades.duplicate(),
		"best_times": best_times.duplicate(),
		"best_stars": best_stars.duplicate(),
		"device_uuid": device_uuid,
		"nickname": nickname,
	}
	var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	if f:
		f.store_line(JSON.stringify(data))
		f.close()

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
	device_uuid = str(data.get("device_uuid", ""))
	nickname = str(data.get("nickname", ""))
