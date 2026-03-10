extends Control

## Code-drawn fire button for mobile — only shown when cannon upgrade is purchased.
## Draws a semi-transparent red circle with a crosshair icon.
## Hold-to-fire: continuously fires while held (cannon cooldown in rocket.gd).

const BTN_RADIUS := 36.0
const BASE_COLOR := Color(1.0, 0.2, 0.1, 0.12)
const RING_COLOR := Color(1.0, 0.3, 0.15, 0.35)
const ICON_COLOR := Color(1.0, 0.4, 0.2, 0.5)
const ACTIVE_BASE := Color(1.0, 0.4, 0.1, 0.3)
const ACTIVE_ICON := Color(1.0, 0.7, 0.3, 0.9)

var _touch_index: int = -1
var _pressed: bool = false
var _center: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(BTN_RADIUS * 2 + 12, BTN_RADIUS * 2 + 12)
	size = custom_minimum_size
	_center = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	# Base circle
	var bg := ACTIVE_BASE if _pressed else BASE_COLOR
	draw_circle(_center, BTN_RADIUS, bg)
	# Ring
	draw_arc(_center, BTN_RADIUS, 0, TAU, 48, RING_COLOR, 2.0)
	# Crosshair icon
	var col := ACTIVE_ICON if _pressed else ICON_COLOR
	var s := 14.0  # crosshair arm length
	# Horizontal line
	draw_line(_center + Vector2(-s, 0), _center + Vector2(s, 0), col, 2.0)
	# Vertical line
	draw_line(_center + Vector2(0, -s), _center + Vector2(0, s), col, 2.0)
	# Center dot
	draw_circle(_center, 3.0, col)
	# Corner tick marks
	var r := 10.0
	for angle_deg in [45, 135, 225, 315]:
		var a := deg_to_rad(float(angle_deg))
		var p1 := _center + Vector2(cos(a), sin(a)) * (r - 3)
		var p2 := _center + Vector2(cos(a), sin(a)) * (r + 3)
		draw_line(p1, p2, col, 1.5)


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
	Input.action_press("fire")
	queue_redraw()


func _do_release() -> void:
	_touch_index = -1
	_pressed = false
	Input.action_release("fire")
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _pressed:
		Input.action_release("fire")
