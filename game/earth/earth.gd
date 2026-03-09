extends StaticBody2D

var _gravity_radius: float = 0.0


func _ready() -> void:
	for child in get_children():
		if child is Area2D:
			for shape_node in child.get_children():
				if shape_node is CollisionShape2D and shape_node.shape is CircleShape2D:
					_gravity_radius = shape_node.shape.radius
					break


func _draw() -> void:
	if _gravity_radius > 0.0:
		draw_arc(Vector2.ZERO, _gravity_radius, 0, TAU, 64, Color(0.3, 0.5, 1.0, 0.08), 1.5)
