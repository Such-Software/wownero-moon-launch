extends Node2D
## Laser beam weapon — continuous beam that drains fuel.
## Added as a child of the rocket. Draws a ray forward, damages enemies it touches.

const BASE_RANGE := 200.0       # pixels at level 1
const RANGE_PER_LEVEL := 40.0   # extra range per upgrade level
const FUEL_DRAIN := 18.0        # fuel/sec while firing
const DAMAGE_INTERVAL := 0.15   # seconds between damage ticks
const BEAM_WIDTH := 3.0

var _active: bool = false
var _range: float = 200.0
var _damage_timer: float = 0.0
var _hit_point: Vector2 = Vector2.ZERO  # local-space end of beam
var _flicker: float = 0.0

func setup(level: int) -> void:
	_range = BASE_RANGE + level * RANGE_PER_LEVEL

func _process(delta: float) -> void:
	if not _active:
		return
	_flicker += delta * 30.0
	_damage_timer -= delta
	# Cast ray forward from parent rocket
	var rocket := get_parent()
	if not rocket:
		return
	var forward := -Vector2.from_angle(rocket.rotation - PI / 2.0)
	var origin: Vector2 = rocket.global_position + forward * 20.0
	var end: Vector2 = origin + forward * _range
	# Raycast using physics
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(origin, end, 2)  # mask=2 (enemies)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [rocket.get_rid()]
	var result := space.intersect_ray(query)
	if result:
		_hit_point = to_local(result.position)
		# Damage the hit enemy
		if _damage_timer <= 0.0:
			_damage_timer = DAMAGE_INTERVAL
			var collider = result.collider
			if collider is CharacterBody2D:
				collider.queue_free()
			elif collider.get_parent() is CharacterBody2D:
				collider.get_parent().queue_free()
	else:
		_hit_point = to_local(end)
	queue_redraw()

func set_active(active: bool) -> void:
	_active = active
	if not active:
		_damage_timer = 0.0
		queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var start_local := to_local(get_parent().global_position)
	# Core beam (cyan/blue)
	var w := BEAM_WIDTH + sin(_flicker) * 0.5
	draw_line(start_local, _hit_point, Color(0.2, 0.8, 1.0, 0.9), w)
	# Outer glow
	draw_line(start_local, _hit_point, Color(0.1, 0.5, 1.0, 0.25), w + 4.0)
	# Impact point glow
	draw_circle(_hit_point, 5.0 + sin(_flicker * 1.3) * 1.5, Color(0.4, 0.9, 1.0, 0.6))
	draw_circle(_hit_point, 2.5, Color(1.0, 1.0, 1.0, 0.9))
	# Origin glow
	draw_circle(start_local, 3.0, Color(0.3, 0.7, 1.0, 0.5))
