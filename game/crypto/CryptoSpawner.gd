extends Node2D
## Reusable crypto spawner. Place in a level, configure, and it scatters pickups
## within a radius around its position. Supports mixed crypto types.
##
## Usage: add CryptoSpawner as a child of any level Node2D.
## Set spawn_count, spawn_radius, and type weights in the editor.

const CryptoPickupScene = preload("res://game/crypto/CryptoPickup.tscn")

## How many pickups to spawn
@export var spawn_count: int = 5
## Radius around this node to scatter pickups
@export var spawn_radius: float = 400.0
## Minimum distance between pickups
@export var min_spacing: float = 40.0

## Probability weights for each crypto type (don't need to sum to 1)
@export var wow_weight: float = 10.0
@export var doge_weight: float = 3.0
@export var xmr_weight: float = 1.0
@export var btc_weight: float = 0.3


func _ready() -> void:
	_spawn_pickups()


func _spawn_pickups() -> void:
	var placed_positions: Array[Vector2] = []
	var types := _build_type_table()

	for i in range(spawn_count):
		var pos := _find_position(placed_positions)
		if pos == Vector2.INF:
			continue  # couldn't find a valid spot, skip

		var pickup := CryptoPickupScene.instantiate()
		pickup.position = pos
		pickup.crypto_type = _pick_type(types)
		pickup.amount = _amount_for_type(pickup.crypto_type)
		add_child(pickup)
		placed_positions.append(pos)


func _find_position(existing: Array[Vector2]) -> Vector2:
	# Try up to 20 times to find a non-overlapping position
	for _attempt in range(20):
		var angle := randf() * TAU
		var dist := randf() * spawn_radius
		var candidate := Vector2(cos(angle), sin(angle)) * dist
		var too_close := false
		for p in existing:
			if candidate.distance_to(p) < min_spacing:
				too_close = true
				break
		if not too_close:
			return candidate
	return Vector2.INF


func _build_type_table() -> Array:
	# Weighted random selection table: [[type, cumulative_weight], ...]
	var table := []
	var total := 0.0
	for entry in [["WOW", wow_weight], ["DOGE", doge_weight], ["XMR", xmr_weight], ["BTC", btc_weight]]:
		total += entry[1]
		table.append([entry[0], total])
	return table


func _pick_type(table: Array) -> String:
	var total: float = table[-1][1]
	var roll := randf() * total
	for entry in table:
		if roll <= entry[1]:
			return entry[0]
	return "WOW"


func _amount_for_type(crypto_type: String) -> int:
	# Base amount per pickup (multiplied by TYPE_MULTIPLIERS in CryptoPickup)
	match crypto_type:
		"WOW": return randi_range(1, 3)
		"DOGE": return 1
		"XMR": return 1
		"BTC": return 1
		_: return 1
