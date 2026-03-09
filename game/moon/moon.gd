extends StaticBody2D

## Slow circular orbit around Earth (or origin if no Earth found).
var orbit_center: Vector2 = Vector2.ZERO
var orbit_radius: float = 0.0
var orbit_speed: float = 0.015  # radians per second (~7 min per revolution)
var orbit_angle: float = 0.0
var _gravity_radius: float = 0.0


func _ready() -> void:
	var earth = get_parent().get_node_or_null("Earth")
	if earth:
		orbit_center = earth.position
	else:
		orbit_center = Vector2.ZERO
	orbit_radius = position.distance_to(orbit_center)
	orbit_angle = (position - orbit_center).angle()
	_gravity_radius = _find_gravity_radius()


func _physics_process(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	position = orbit_center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
	queue_redraw()


func _draw() -> void:
	if _gravity_radius > 0.0:
		draw_arc(Vector2.ZERO, _gravity_radius, 0, TAU, 64, Color(0.3, 0.5, 1.0, 0.12), 1.5)


func _find_gravity_radius() -> float:
	for child in get_children():
		if child is Area2D:
			for shape_node in child.get_children():
				if shape_node is CollisionShape2D and shape_node.shape is CircleShape2D:
					return shape_node.shape.radius
	return 0.0

