extends Area2D
## Bullet projectile — fired from the rocket's cannon.
## Flies forward, destroys Martians and Asteroids on contact, auto-despawns.

const SPEED := 400.0
const LIFETIME := 2.5

var _direction: Vector2 = Vector2.UP
var _age: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # collide with enemies/hazards
	# Collision shape — small circle
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func setup(pos: Vector2, dir: Vector2) -> void:
	## Call after instantiating: set position and direction.
	global_position = pos
	_direction = dir.normalized()
	rotation = _direction.angle() + PI / 2.0

func _process(delta: float) -> void:
	position += _direction * SPEED * delta
	_age += delta
	if _age >= LIFETIME:
		queue_free()
	queue_redraw()

func _draw() -> void:
	# Bright bullet glow
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.8, 0.2, 0.9))
	draw_circle(Vector2.ZERO, 2.0, Color(1.0, 1.0, 0.8, 1.0))
	# Trailing glow
	var trail_dir := -_direction * 8.0
	draw_circle(trail_dir.rotated(-rotation + PI / 2.0), 2.5, Color(1.0, 0.5, 0.1, 0.4))

func _on_body_entered(body: Node2D) -> void:
	_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_hit(area)

func _hit(node: Node) -> void:
	# Destroy martians (CharacterBody2D with Martian script)
	if node is CharacterBody2D:
		node.queue_free()
		queue_free()
		return
	# Also destroy if parent is a CharacterBody2D (hit child collision shape)
	if node.get_parent() is CharacterBody2D:
		node.get_parent().queue_free()
		queue_free()
		return
