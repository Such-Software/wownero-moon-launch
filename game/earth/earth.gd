extends StaticBody2D

var _gravity_radius: float = 0.0
var _body_radius: float = 0.0
const ATMO_COLOR := Color(0.3, 0.6, 1.0)  # blue atmosphere

const EARTH_TEXTURES := [
	"res://art/planets/earth_real_1.png",
	"res://art/planets/earth_real_2.png",
	"res://art/planets/earth_real_3.png",
]


func _ready() -> void:
	# Randomize earth appearance
	var tex := load(EARTH_TEXTURES[randi() % EARTH_TEXTURES.size()])
	if tex and has_node("Sprite2D"):
		$Sprite2D.texture = tex
	for child in get_children():
		if child is Area2D:
			for shape_node in child.get_children():
				if shape_node is CollisionShape2D and shape_node.shape is CircleShape2D:
					_gravity_radius = shape_node.shape.radius
					break
		elif child is CollisionShape2D and child.shape is CircleShape2D:
			_body_radius = child.shape.radius


func _draw() -> void:
	if _body_radius > 0.0:
		# Atmosphere glow — layered translucent rings
		for i in range(4):
			var r := _body_radius + 3.0 + float(i) * 4.0
			var a := lerpf(0.12, 0.02, float(i) / 3.0)
			draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(ATMO_COLOR.r, ATMO_COLOR.g, ATMO_COLOR.b, a), 2.0)
	if _gravity_radius > 0.0:
		draw_arc(Vector2.ZERO, _gravity_radius, 0, TAU, 64, Color(0.3, 0.5, 1.0, 0.08), 1.5)
