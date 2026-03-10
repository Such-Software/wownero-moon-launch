extends Node2D
## EMP Pulse — area-of-effect weapon that destroys all enemies in radius.
## Instantiate, call fire(pos, radius), and it handles the expanding ring visual + cleanup.

const EXPAND_TIME := 0.5   # seconds for ring to expand to full radius
const LINGER_TIME := 0.3   # seconds the ring stays at full size before fading

var _radius: float = 0.0
var _max_radius: float = 150.0
var _expanding: bool = false
var _phase: float = 0.0  # 0→1 expansion, then hold
var _done: bool = false

func fire(pos: Vector2, radius: float) -> void:
	global_position = pos
	_max_radius = radius
	_expanding = true
	_phase = 0.0
	_radius = 0.0
	z_index = 50
	# Destroy all enemies in range immediately
	_destroy_enemies_in_radius(pos, radius)

func _destroy_enemies_in_radius(center: Vector2, radius: float) -> void:
	## Find and destroy all CharacterBody2D nodes within radius.
	var parent := get_parent()
	if not parent:
		return
	for node in parent.get_children():
		if node is CharacterBody2D:
			var dist := center.distance_to(node.global_position)
			if dist <= radius:
				node.queue_free()

func _process(delta: float) -> void:
	if _done:
		return
	if not _expanding:
		return
	_phase += delta / EXPAND_TIME
	if _phase < 1.0:
		_radius = _max_radius * _phase
	elif _phase < 1.0 + LINGER_TIME / EXPAND_TIME:
		_radius = _max_radius
	else:
		_done = true
		# Fade out
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(queue_free)
	queue_redraw()

func _draw() -> void:
	if _radius <= 0.0:
		return
	var alpha := 1.0 - clampf((_phase - 1.0) * (EXPAND_TIME / LINGER_TIME), 0.0, 1.0)
	# Outer ring
	draw_arc(Vector2.ZERO, _radius, 0, TAU, 64, Color(0.3, 0.6, 1.0, 0.6 * alpha), 3.0)
	# Inner pulse ring
	var inner_r := _radius * 0.7
	draw_arc(Vector2.ZERO, inner_r, 0, TAU, 48, Color(0.5, 0.8, 1.0, 0.3 * alpha), 2.0)
	# Electric sparks at edge
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_phase * 1000000)
	for i in range(8):
		var angle := rng.randf() * TAU
		var r := _radius * rng.randf_range(0.85, 1.0)
		var spark_pos := Vector2(cos(angle), sin(angle)) * r
		draw_circle(spark_pos, 2.0, Color(0.7, 0.9, 1.0, 0.8 * alpha))
	# Center flash during expansion
	if _phase < 0.3:
		var flash_alpha := (0.3 - _phase) / 0.3
		draw_circle(Vector2.ZERO, 15.0, Color(1.0, 1.0, 1.0, 0.4 * flash_alpha))
