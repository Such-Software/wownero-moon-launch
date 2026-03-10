extends Area2D
## Nebula zone — drains fuel while the rocket is inside.
## Visual: soft colored fog with drifting particles.
## Place as a large Area2D in a level.

## Fuel drain rate (units per second) while inside
@export var fuel_drain_rate: float = 5.0
## Slow factor applied to rocket velocity (1.0 = no slow, 0.5 = half speed)
@export var speed_damping: float = 0.98
## Visual zone size
@export var zone_size: Vector2 = Vector2(500, 400)
## Nebula color
@export var nebula_color: Color = Color(0.6, 0.2, 0.8, 0.5)

var _bodies_inside: Array = []
var _elapsed: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = zone_size
	shape.shape = rect
	add_child(shape)

func _physics_process(delta: float) -> void:
	for body in _bodies_inside:
		if not is_instance_valid(body):
			continue
		if body.is_in_group("rocket"):
			# Drain fuel from the rocket
			body.fuel = maxf(body.fuel - fuel_drain_rate * delta, 0.0)
			# Apply gentle speed damping
			if body is RigidBody2D and speed_damping < 1.0:
				body.linear_velocity *= speed_damping

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

func _draw() -> void:
	var half := zone_size * 0.5
	var c := nebula_color
	# Multiple soft blobs to simulate nebula gas
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + _elapsed * 0.15
		var offset := Vector2(cos(angle), sin(angle)) * zone_size.x * 0.25
		var blob_r := zone_size.x * randf_range(0.15, 0.3)
		var pulse := 0.5 + 0.5 * sin(_elapsed * 1.5 + float(i) * 1.2)
		draw_circle(offset, blob_r,
			Color(c.r, c.g, c.b, lerpf(0.03, 0.08, pulse)))
	# Zone boundary hint
	draw_rect(Rect2(-half, zone_size), Color(c.r, c.g, c.b, 0.06))
	# Subtle edge glow
	draw_rect(Rect2(-half, zone_size), Color(c.r, c.g, c.b, 0.15), false, 1.0)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("rocket") and body not in _bodies_inside:
		_bodies_inside.append(body)

func _on_body_exited(body: Node2D) -> void:
	_bodies_inside.erase(body)
