extends Control
## Generic weapon button for mobile — tap to fire.
## Configure via properties: action_name, icon_text, base_color.

const BTN_RADIUS := 28.0

var action_name: String = "missile"
var icon_text: String = "M"
var base_color: Color = Color(1.0, 0.3, 0.1, 0.15)
var ring_color: Color = Color(1.0, 0.4, 0.2, 0.35)
var ammo_count: int = -1  # -1 = unlimited (used for display only)

var _touch_index: int = -1
var _pressed: bool = false
var _center: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(BTN_RADIUS * 2 + 8, BTN_RADIUS * 2 + 8)
	size = custom_minimum_size
	_center = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var bg := Color(base_color.r, base_color.g, base_color.b, 0.3 if _pressed else 0.12)
	draw_circle(_center, BTN_RADIUS, bg)
	draw_arc(_center, BTN_RADIUS, 0, TAU, 36, ring_color, 2.0)
	# Icon letter
	var col := Color(base_color.r, base_color.g, base_color.b, 0.9 if _pressed else 0.5)
	# Draw icon text centered (approximate)
	draw_string(ThemeDB.fallback_font, _center + Vector2(-6, 6), icon_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, col)
	# Ammo count
	if ammo_count >= 0:
		var ammo_col := Color(1.0, 1.0, 1.0, 0.7)
		draw_string(ThemeDB.fallback_font, _center + Vector2(10, -12), str(ammo_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ammo_col)


func _process(_delta: float) -> void:
	# Update ammo display from rocket state
	if ammo_count >= 0:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0:
			_do_press(event.index)
		elif not event.pressed and event.index == _touch_index:
			_do_release()
	elif event is InputEventMouseButton:
		if event.pressed and _touch_index < 0:
			_do_press(0)
		elif not event.pressed and _touch_index == 0:
			_do_release()


func _do_press(index: int) -> void:
	_touch_index = index
	_pressed = true
	Input.action_press(action_name)
	queue_redraw()


func _do_release() -> void:
	_touch_index = -1
	_pressed = false
	Input.action_release(action_name)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _pressed:
		Input.action_release(action_name)
