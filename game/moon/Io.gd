extends StaticBody2D

## Slow circular orbit around Earth (or origin if no Earth found).
var orbit_center: Vector2 = Vector2.ZERO
var orbit_radius: float = 0.0
var orbit_speed: float = 0.010  # between Moon and Venus speed
var orbit_angle: float = 0.0


func _ready() -> void:
	var earth = get_parent().get_node_or_null("Earth")
	if earth:
		orbit_center = earth.position
	else:
		orbit_center = Vector2.ZERO
	orbit_radius = position.distance_to(orbit_center)
	orbit_angle = (position - orbit_center).angle()


func _physics_process(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	position = orbit_center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
