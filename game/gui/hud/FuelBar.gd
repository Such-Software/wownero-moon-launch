extends Control
## HUD fuel bar — finds Rocket via "rocket" group, draws fuel gauge each frame.
## Standalone widget: create with Control.new(), set_script(), add_child().

var _rocket: Node = null
var bar_width: float = 120.0
var bar_height: float = 14.0
var padding: float = 2.0
var _flash_timer: float = 0.0
const LOW_FUEL_THRESHOLD := 0.2


func _ready() -> void:
	# Wait one frame so the scene tree is fully built, then find Rocket
	await get_tree().process_frame
	_rocket = get_tree().get_first_node_in_group("rocket")


func _process(_delta: float) -> void:
	_flash_timer += _delta
	queue_redraw()


func _draw() -> void:
	if not _rocket or not is_instance_valid(_rocket):
		return

	var fuel: float = _rocket.fuel
	var max_fuel: float = _rocket.max_fuel
	if max_fuel <= 0:
		return

	var ratio := clampf(fuel / max_fuel, 0.0, 1.0)
	var is_low := ratio < LOW_FUEL_THRESHOLD and ratio > 0.0

	# Flash effect when low fuel — toggle visibility at 4Hz
	var flash_visible := true
	if is_low:
		flash_visible = fmod(_flash_timer, 0.5) < 0.35

	# Background
	var bg_rect := Rect2(Vector2.ZERO, Vector2(bar_width, bar_height))
	var bg_color := Color(0.1, 0.1, 0.2, 0.8)
	if is_low:
		bg_color = Color(0.3, 0.05, 0.05, 0.9)
	draw_rect(bg_rect, bg_color)

	# Fuel fill — green > yellow > red
	var fill_color: Color
	if ratio > 0.5:
		fill_color = Color.GREEN.lerp(Color.YELLOW, 1.0 - (ratio - 0.5) * 2.0)
	else:
		fill_color = Color.YELLOW.lerp(Color.RED, 1.0 - ratio * 2.0)

	if is_low and not flash_visible:
		fill_color = Color.RED

	var fill_rect := Rect2(
		Vector2(padding, padding),
		Vector2((bar_width - padding * 2.0) * ratio, bar_height - padding * 2.0)
	)
	draw_rect(fill_rect, fill_color)

	# Border — flashes bright red when low
	var border_color := Color(0.5, 0.6, 1.0, 0.6)
	if is_low:
		border_color = Color(1.0, 0.2, 0.1, 1.0) if flash_visible else Color(0.6, 0.1, 0.05, 0.8)
	draw_rect(bg_rect, border_color, false, 1.5)

	# "LOW FUEL" text when critically low
	if is_low and flash_visible:
		draw_string(ThemeDB.fallback_font, Vector2(bar_width + 6, bar_height - 2), "LOW FUEL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.3, 0.2, 1.0))

	# Label
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(bar_width + 6, bar_height - 2), "FUEL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.7, 1.0, 0.9))
