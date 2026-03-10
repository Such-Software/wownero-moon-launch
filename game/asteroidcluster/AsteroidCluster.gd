extends StaticBody2D

## Asteroid cluster — a clump of rocks that slowly drifts and rotates.
## The cluster moves as a unit; individual rocks are visual decorations.
var drift_speed: Vector2 = Vector2(3.0, -1.5)  # slow drift
var rotation_speed: float = 0.02  # barely rotating
var _gravity_radius: float = 0.0

var _rock_sprites: Array[Sprite2D] = []


func _ready() -> void:
	_gravity_radius = _find_gravity_radius()
	_spawn_cluster_rocks()


func _physics_process(delta: float) -> void:
	position += drift_speed * delta
	rotation += rotation_speed * delta
	# Slowly counter-rotate each rock for visual variety
	for rock in _rock_sprites:
		rock.rotation += randf_range(-0.005, 0.005)
	queue_redraw()


func _draw() -> void:
	if _gravity_radius > 0.0:
		draw_arc(Vector2.ZERO, _gravity_radius, 0, TAU, 64, Color(0.3, 0.5, 1.0, 0.12), 1.5)


func _spawn_cluster_rocks() -> void:
	var tex1 = load("res://art/planets/asteroid.png")
	var tex2 = load("res://art/planets/asteroid2.png")
	var rock_count = randi_range(7, 10)
	for i in rock_count:
		var rock = Sprite2D.new()
		rock.texture = tex1 if randf() < 0.5 else tex2
		# Scatter around center, random rotation and scale
		rock.position = Vector2(randf_range(-60, 60), randf_range(-60, 60))
		rock.rotation = randf_range(0, TAU)
		var s = randf_range(0.03, 0.07)
		rock.scale = Vector2(s, s)
		rock.modulate = Color(randf_range(0.6, 1.0), randf_range(0.55, 0.85), randf_range(0.4, 0.7), 1.0)
		rock.z_index = -1
		add_child(rock)
		_rock_sprites.append(rock)


func _find_gravity_radius() -> float:
	for child in get_children():
		if child is Area2D:
			for shape_node in child.get_children():
				if shape_node is CollisionShape2D and shape_node.shape is CircleShape2D:
					return shape_node.shape.radius
	return 0.0
