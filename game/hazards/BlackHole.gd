extends StaticBody2D
## Black Hole — extreme gravity pull + instant death at the event horizon.
## Visual: dark center with accretion disk rings and gravitational lensing effect.
## Place in a level. The gravity Area2D pulls the rocket in; the kill Area2D destroys it.

## Gravity strength (applied as force toward center)
@export var gravity_strength: float = 800.0
## Radius of the gravity pull field
@export var gravity_radius: float = 300.0
## Radius of the instant-kill event horizon
@export var kill_radius: float = 30.0
## Accretion disk color
@export var disk_color: Color = Color(1.0, 0.6, 0.1, 0.7)

var _elapsed: float = 0.0
var _gravity_area: Area2D = null
var _kill_area: Area2D = null

func _ready() -> void:
	# Gravity pull area
	_gravity_area = Area2D.new()
	_gravity_area.collision_layer = 0
	_gravity_area.collision_mask = 1
	var grav_shape := CollisionShape2D.new()
	var grav_circle := CircleShape2D.new()
	grav_circle.radius = gravity_radius
	grav_shape.shape = grav_circle
	_gravity_area.add_child(grav_shape)
	add_child(_gravity_area)
	# Kill zone (event horizon)
	_kill_area = Area2D.new()
	_kill_area.collision_layer = 0
	_kill_area.collision_mask = 1
	var kill_shape := CollisionShape2D.new()
	var kill_circle := CircleShape2D.new()
	kill_circle.radius = kill_radius
	kill_shape.shape = kill_circle
	_kill_area.add_child(kill_shape)
	add_child(_kill_area)
	_kill_area.body_entered.connect(_on_kill_entered)
	# Static body collision (so FootArea detects it but it's deadly)
	var body_shape := CollisionShape2D.new()
	var body_circle := CircleShape2D.new()
	body_circle.radius = kill_radius
	body_shape.shape = body_circle
	add_child(body_shape)
	collision_layer = 2

func _physics_process(delta: float) -> void:
	# Apply gravity pull to all bodies in the gravity area
	var bodies := _gravity_area.get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody2D and body.is_in_group("rocket"):
			var dir: Vector2 = (global_position - body.global_position)
			var dist := dir.length()
			if dist < 5.0:
				continue
			# Gravity falls off with distance squared (but capped)
			var strength := gravity_strength / maxf(dist * 0.5, 1.0)
			body.apply_central_impulse(dir.normalized() * strength * delta)

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

func _draw() -> void:
	# Event horizon — solid black circle
	draw_circle(Vector2.ZERO, kill_radius, Color.BLACK)
	# Accretion disk rings
	var c := disk_color
	for i in range(4):
		var r := kill_radius + 10.0 + float(i) * 15.0
		var spin := _elapsed * (2.0 - float(i) * 0.3)
		var alpha := lerpf(0.5, 0.15, float(i) / 4.0)
		var pulse := 0.7 + 0.3 * sin(_elapsed * 3.0 + float(i))
		draw_arc(Vector2.ZERO, r, spin, spin + TAU * 0.7, 32,
			Color(c.r, c.g, c.b, alpha * pulse), 2.0 + float(i) * 0.5)
	# Gravity field hint (faint outer rings)
	for i in range(3):
		var r := gravity_radius * (0.4 + float(i) * 0.2)
		var alpha := 0.04 + 0.02 * sin(_elapsed * 1.5 + float(i))
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(0.5, 0.5, 1.0, alpha), 1.0)
	# Bright core glow
	var core_pulse := 0.5 + 0.5 * sin(_elapsed * 5.0)
	draw_circle(Vector2.ZERO, kill_radius * 0.5,
		Color(0.8, 0.4, 0.0, lerpf(0.2, 0.5, core_pulse)))

func _on_kill_entered(body: Node2D) -> void:
	if body.is_in_group("rocket"):
		# Instant death — trigger via globalvar signal
		globalvar.sendDeath.emit()
		Input.vibrate_handheld(300)
