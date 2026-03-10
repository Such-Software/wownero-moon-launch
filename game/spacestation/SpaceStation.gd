extends StaticBody2D

## Space station rotates slowly in place.
var rotation_speed: float = 0.15  # radians per second
var _gravity_radius: float = 0.0


func _ready() -> void:
	_gravity_radius = _find_gravity_radius()


func _physics_process(delta: float) -> void:
	rotation += rotation_speed * delta
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
