extends Area2D
## Solar Wind zone — applies a constant directional force to the rocket.
## Place as a large Area2D in a level. Configure wind_direction and strength.
## Visual: animated streaking lines showing wind direction.

## Wind direction (normalized). Default blows rightward.
@export var wind_direction: Vector2 = Vector2(1, 0)
## Force magnitude applied to rocket each physics frame
@export var wind_strength: float = 120.0
## Visual zone size (for drawing the streaks)
@export var zone_size: Vector2 = Vector2(400, 300)

var _bodies_inside: Array = []
var _elapsed: float = 0.0
# Pre-computed streak positions (randomized once)
var _streaks: Array = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 0
	collision_mask = 1
	# Create rectangular collision shape
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = zone_size
	shape.shape = rect
	add_child(shape)
	# Generate random streak positions
	for i in range(12):
		_streaks.append(Vector2(
			randf_range(-zone_size.x * 0.5, zone_size.x * 0.5),
			randf_range(-zone_size.y * 0.5, zone_size.y * 0.5)
		))

func _physics_process(delta: float) -> void:
	var force := wind_direction.normalized() * wind_strength * delta
	for body in _bodies_inside:
		if is_instance_valid(body) and body is RigidBody2D:
			body.apply_central_impulse(force)

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

func _draw() -> void:
	# Semi-transparent zone boundary
	var half := zone_size * 0.5
	draw_rect(Rect2(-half, zone_size), Color(0.3, 0.5, 1.0, 0.04))
	# Animated wind streaks
	var dir := wind_direction.normalized()
	var streak_len := 25.0
	for i in range(_streaks.size()):
		var base: Vector2 = _streaks[i]
		# Animate along wind direction (loop within zone)
		var offset := fmod(_elapsed * 80.0 + float(i) * 40.0, zone_size.x + streak_len)
		var pos := base + dir * (offset - zone_size.x * 0.5)
		# Wrap within zone bounds
		if pos.x > half.x + streak_len or pos.x < -half.x - streak_len:
			continue
		if pos.y > half.y or pos.y < -half.y:
			continue
		var alpha := 0.15 + 0.1 * sin(_elapsed * 3.0 + float(i))
		draw_line(pos, pos + dir * streak_len,
			Color(0.5, 0.7, 1.0, alpha), 1.5)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("rocket") and body not in _bodies_inside:
		_bodies_inside.append(body)

func _on_body_exited(body: Node2D) -> void:
	_bodies_inside.erase(body)
