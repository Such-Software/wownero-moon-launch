extends Node2D
## Martian Mothership — boss enemy that patrols and spawns Martians.
## Landing pad on top is the only safe surface (in "targets" group).

@export var patrol_amplitude: float = 180.0
@export var patrol_period: float = 8.0
@export var spawn_interval_base: float = 5.0

var _start_pos: Vector2
var _elapsed: float = 0.0
var _spawn_timer: float = 0.0
var _ray_timer: float = 0.0
const RAY_INTERVAL := 6.0

var _martian_scene = preload("res://game/martian/Martian.tscn")
var _gammaray_scene = preload("res://game/gammaray/GammeRay.tscn")


func _ready() -> void:
	_start_pos = global_position
	_spawn_timer = spawn_interval_base * 0.4  # Short delay before first spawn


func _process(delta: float) -> void:
	_elapsed += delta
	# Sine wave patrol — vertical oscillation
	global_position.y = _start_pos.y + sin(_elapsed * TAU / patrol_period) * patrol_amplitude
	# Slow horizontal drift
	global_position.x = _start_pos.x + sin(_elapsed * TAU / (patrol_period * 2.5)) * (patrol_amplitude * 0.3)

	# Spawn Martians periodically
	_spawn_timer += delta
	var interval := spawn_interval_base * globalvar.get_spawn_interval_mult()
	if _spawn_timer >= interval:
		_spawn_martian()
		_spawn_timer = 0.0

	# Fire gamma rays periodically
	_ray_timer += delta
	if _ray_timer >= RAY_INTERVAL * globalvar.get_spawn_interval_mult():
		_fire_gamma_ray()
		_ray_timer = 0.0


func _spawn_martian() -> void:
	var m := _martian_scene.instantiate()
	get_parent().add_child(m)
	var side := 1.0 if randf() < 0.5 else -1.0
	m.global_position = global_position + Vector2(side * 130.0, randf_range(-50, 50))
	m.speed = randi_range(52, 68)


func _fire_gamma_ray() -> void:
	var ray := _gammaray_scene.instantiate()
	get_parent().add_child(ray)
	ray.global_position = global_position + Vector2(randf_range(-80, 80), randf_range(-40, 40))
	var rocket := get_node_or_null("../Rocket")
	if rocket and is_instance_valid(rocket):
		ray.look_at(rocket.global_position)
	else:
		ray.rotation = randf() * TAU
