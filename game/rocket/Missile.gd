extends Area2D
## Homing missile — locks onto nearest enemy and tracks them.
## Slower than bullets but guaranteed hit if target stays alive.

const SPEED := 250.0
const TURN_SPEED := 3.5  # radians/sec — how fast it steers toward target
const LIFETIME := 4.0
const LOCK_RANGE := 500.0  # acquires targets within this range

var _direction: Vector2 = Vector2.UP
var _age: float = 0.0
var _target: Node2D = null
var _trail_points: Array[Vector2] = []
const MAX_TRAIL := 12

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func setup(pos: Vector2, dir: Vector2, target: Node2D = null) -> void:
	global_position = pos
	_direction = dir.normalized()
	rotation = _direction.angle() + PI / 2.0
	_target = target

func _process(delta: float) -> void:
	# Homing: steer toward target
	if is_instance_valid(_target):
		var desired := (_target.global_position - global_position).normalized()
		var angle_diff := _direction.angle_to(desired)
		var max_turn := TURN_SPEED * delta
		angle_diff = clampf(angle_diff, -max_turn, max_turn)
		_direction = _direction.rotated(angle_diff).normalized()
	position += _direction * SPEED * delta
	rotation = _direction.angle() + PI / 2.0
	# Trail
	_trail_points.push_front(global_position)
	if _trail_points.size() > MAX_TRAIL:
		_trail_points.resize(MAX_TRAIL)
	_age += delta
	if _age >= LIFETIME:
		_explode()
	queue_redraw()

func _draw() -> void:
	# Missile body — elongated triangle
	var pts := PackedVector2Array([
		Vector2(0, -8), Vector2(-4, 6), Vector2(4, 6)
	])
	draw_colored_polygon(pts, Color(1.0, 0.3, 0.1, 0.95))
	# Nose glow
	draw_circle(Vector2(0, -6), 2.5, Color(1.0, 0.9, 0.4, 1.0))
	# Exhaust flame
	var flame_len := randf_range(6.0, 10.0)
	draw_line(Vector2(-2, 6), Vector2(0, 6 + flame_len), Color(1.0, 0.5, 0.0, 0.7), 2.0)
	draw_line(Vector2(2, 6), Vector2(0, 6 + flame_len * 0.8), Color(1.0, 0.8, 0.2, 0.5), 1.5)
	# Smoke trail (draw in local space relative to current pos)
	for i in range(1, _trail_points.size()):
		var alpha := 1.0 - float(i) / float(MAX_TRAIL)
		var trail_local := to_local(_trail_points[i])
		var r := 2.0 * alpha
		draw_circle(trail_local, r, Color(0.7, 0.7, 0.7, alpha * 0.3))

func _on_body_entered(body: Node2D) -> void:
	_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_hit(area)

func _hit(node: Node) -> void:
	if node is CharacterBody2D:
		node.queue_free()
		_explode()
		return
	if node.get_parent() is CharacterBody2D:
		node.get_parent().queue_free()
		_explode()
		return

func _explode() -> void:
	# Small explosion burst
	var burst := GPUParticles2D.new()
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 10
	burst.lifetime = 0.4
	burst.explosiveness = 1.0
	burst.local_coords = false
	burst.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 3.0
	mat.particle_flag_disable_z = true
	mat.direction = Vector3.ZERO
	mat.spread = 180.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 70.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 30.0
	mat.damping_max = 50.0
	mat.scale_min = 1.0
	mat.scale_max = 2.5
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.6, 0.1, 1.0),
		Color(1.0, 0.3, 0.0, 0.6),
		Color(0.3, 0.1, 0.0, 0.0),
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	burst.process_material = mat
	get_parent().add_child(burst)
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(burst):
			burst.queue_free()
	)
	queue_free()
