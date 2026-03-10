extends StaticBody2D

## Slow circular orbit around Earth (or origin if no Earth found).
var orbit_center: Vector2 = Vector2.ZERO
var orbit_radius: float = 0.0
var orbit_speed: float = 0.008  # slowest orbit — Venus is far out
var orbit_angle: float = 0.0
var _gravity_radius: float = 0.0
var _body_radius: float = 0.0
const ATMO_COLOR := Color(1.0, 0.85, 0.3)  # thick yellow-orange atmosphere


func _ready() -> void:
	var earth = get_parent().get_node_or_null("Earth")
	if earth:
		orbit_center = earth.position
	else:
		orbit_center = Vector2.ZERO
	orbit_radius = position.distance_to(orbit_center)
	orbit_angle = (position - orbit_center).angle()
	_gravity_radius = _find_gravity_radius()
	_body_radius = _find_body_radius()


func _physics_process(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	position = orbit_center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
	queue_redraw()


func _draw() -> void:
	if _body_radius > 0.0:
		for i in range(4):
			var r := _body_radius + 2.0 + float(i) * 3.5
			var a := lerpf(0.12, 0.02, float(i) / 3.0)
			draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(ATMO_COLOR.r, ATMO_COLOR.g, ATMO_COLOR.b, a), 2.0)
	if _gravity_radius > 0.0:
		draw_arc(Vector2.ZERO, _gravity_radius, 0, TAU, 64, Color(0.3, 0.5, 1.0, 0.12), 1.5)


func _find_gravity_radius() -> float:
	for child in get_children():
		if child is Area2D:
			for shape_node in child.get_children():
				if shape_node is CollisionShape2D and shape_node.shape is CircleShape2D:
					return shape_node.shape.radius
	return 0.0


func _find_body_radius() -> float:
	for child in get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			return child.shape.radius
	return 0.0

