extends Control
## HUD fuel bar — finds Rocket via "rocket" group, draws fuel gauge each frame.
## Standalone widget: create with Control.new(), set_script(), add_child().

var _rocket: Node = null
var bar_width: float = 120.0
var bar_height: float = 14.0
var padding: float = 2.0


func _ready() -> void:
	# Wait one frame so the scene tree is fully built, then find Rocket
	await get_tree().process_frame
	_rocket = get_tree().get_first_node_in_group("rocket")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not _rocket or not is_instance_valid(_rocket):
		return

	var fuel: float = _rocket.fuel
	var max_fuel: float = _rocket.max_fuel
	if max_fuel <= 0:
		return

	var ratio := clampf(fuel / max_fuel, 0.0, 1.0)

	# Background
	var bg_rect := Rect2(Vector2.ZERO, Vector2(bar_width, bar_height))
	draw_rect(bg_rect, Color(0.1, 0.1, 0.2, 0.8))

	# Fuel fill — green > yellow > red
	var fill_color: Color
	if ratio > 0.5:
		fill_color = Color.GREEN.lerp(Color.YELLOW, 1.0 - (ratio - 0.5) * 2.0)
	else:
		fill_color = Color.YELLOW.lerp(Color.RED, 1.0 - ratio * 2.0)

	var fill_rect := Rect2(
		Vector2(padding, padding),
		Vector2((bar_width - padding * 2.0) * ratio, bar_height - padding * 2.0)
	)
	draw_rect(fill_rect, fill_color)

	# Border
	draw_rect(bg_rect, Color(0.5, 0.6, 1.0, 0.6), false, 1.5)

	# Label
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(bar_width + 6, bar_height - 2), "FUEL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.7, 1.0, 0.9))
