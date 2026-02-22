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
}

# --- Upgrade costs (WOW) — cost increases per level ---
const UPGRADE_BASE_COSTS := {
	"thrust": 50,
	"fuel_capacity": 40,
	"fuel_efficiency": 60,
	"armor": 80,
	"landing_gear": 45,
}
const UPGRADE_MAX_LEVEL := 5

# --- Upgrade descriptions for the shop ---
const UPGRADE_DESCRIPTIONS := {
	"thrust": "Engine Power — more thrust force",
	"fuel_capacity": "Fuel Tank — larger fuel capacity",
	"fuel_efficiency": "Fuel Efficiency — less fuel drain",
	"armor": "Armor Plating — survive harder impacts",
	"landing_gear": "Landing Gear — land at higher speed",
}

# --- Derived stats (computed from upgrades) ---
func get_thrust_force() -> float:
	return 350.0 + upgrades["thrust"] * 50.0

func get_max_fuel() -> float:
	return 100.0 + upgrades["fuel_capacity"] * 25.0

func get_fuel_drain() -> float:
	return maxf(12.0 - upgrades["fuel_efficiency"] * 2.0, 4.0)

func get_crash_speed() -> float:
	return 100.0 + upgrades["armor"] * 50.0

func get_landing_speed() -> float:
	return 40.0 + upgrades["landing_gear"] * 20.0

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

# --- Save / Load ---
func _ready():
	load_game()

func save_game() -> void:
	highest_level_completed = maxi(highest_level_completed, nowlevel)
	var data := {
		"level": mini(nowlevel + 1, MAX_LEVEL),
		"highest_completed": highest_level_completed,
		"completed": nowlevel >= MAX_LEVEL or all_completed,
		"wallet": wallet,
		"upgrades": upgrades.duplicate(),
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
