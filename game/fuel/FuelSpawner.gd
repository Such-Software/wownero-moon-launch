extends Node2D
## Spawns FuelPickup canisters within a radius. Fuel is intentionally rare.
##
## Usage: add FuelSpawner as a child of any level Node2D.
## Set spawn_count (1-2 recommended) and spawn_radius in the editor.

const FuelPickupScene = preload("res://game/fuel/FuelPickup.tscn")

## How many fuel canisters to spawn
@export var spawn_count: int = 1
## Radius around this node to scatter pickups
@export var spawn_radius: float = 300.0
## Fuel restored per canister (fraction of max_fuel)
@export var fuel_percent: float = 0.25
## Minimum distance between canisters
@export var min_spacing: float = 80.0


func _ready() -> void:
	_spawn_pickups()


func _spawn_pickups() -> void:
	var placed: Array[Vector2] = []

	for _i in range(spawn_count):
		var pos := _find_position(placed)
		if pos == Vector2.INF:
			continue

		var pickup := FuelPickupScene.instantiate()
		pickup.position = pos
		pickup.fuel_percent = fuel_percent
		add_child(pickup)
		placed.append(pos)


func _find_position(existing: Array[Vector2]) -> Vector2:
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
