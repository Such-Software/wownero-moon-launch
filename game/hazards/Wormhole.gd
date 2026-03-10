extends Area2D
## Wormhole portal — teleports the rocket to a linked exit point.
## Place two Wormhole nodes in a level. Set `linked_wormhole` in the editor
## or via code to connect them. Visual: swirling animated portal ring.

## The partner wormhole this one teleports to
@export var linked_wormhole: NodePath = ""
## Cooldown after teleporting (prevents instant re-teleport)
@export var cooldown_time: float = 1.5
## Radius of the portal collision and visual
@export var portal_radius: float = 40.0
## Portal color (each end can be different)
@export var portal_color: Color = Color(0.4, 0.2, 1.0, 0.8)

var _cooldown: float = 0.0
var _spin: float = 0.0
var _pulse: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	collision_mask = 1
	# Create collision shape matching portal_radius
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = portal_radius
	shape.shape = circle
	add_child(shape)

func _process(delta: float) -> void:
	_spin += delta * 3.0
	_pulse += delta * 4.0
	if _cooldown > 0.0:
		_cooldown -= delta
	queue_redraw()

func _draw() -> void:
	var c := portal_color
	var pulse := 0.5 + 0.5 * sin(_pulse)
	# Outer swirl ring
	for i in range(6):
		var angle := _spin + TAU * float(i) / 6.0
		var r := portal_radius + sin(angle * 2.0 + _pulse) * 6.0
		draw_arc(Vector2.ZERO, r, angle, angle + 0.8, 12,
			Color(c.r, c.g, c.b, lerpf(0.3, 0.7, pulse)), 2.5)
	# Inner glow
	draw_circle(Vector2.ZERO, portal_radius * 0.6,
		Color(c.r, c.g, c.b, lerpf(0.08, 0.2, pulse)))
	# Bright center dot
	draw_circle(Vector2.ZERO, 5.0,
		Color(1.0, 1.0, 1.0, lerpf(0.3, 0.7, pulse)))
	# Dimmed if on cooldown
	if _cooldown > 0.0:
		draw_circle(Vector2.ZERO, portal_radius, Color(0, 0, 0, 0.3))

func _on_body_entered(body: Node2D) -> void:
	if _cooldown > 0.0:
		return
	if not body.is_in_group("rocket"):
		return
	var target_node = get_node_or_null(linked_wormhole)
	if not target_node or not is_instance_valid(target_node):
		return
	# Teleport rocket to linked wormhole position
	body.global_position = target_node.global_position
	# Set cooldown on both ends
	_cooldown = cooldown_time
	if target_node.has_method("set_cooldown"):
		target_node.set_cooldown(cooldown_time)
	# Haptic pulse
	Input.vibrate_handheld(80)

func set_cooldown(t: float) -> void:
	_cooldown = t
