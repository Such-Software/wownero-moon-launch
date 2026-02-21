extends Control

## Code-drawn virtual joystick for mobile rotation control.
## Emits ui_left / ui_right input actions based on horizontal drag.

const BASE_RADIUS := 60.0
const KNOB_RADIUS := 24.0
const DEADZONE := 0.3
const BASE_COLOR := Color(1, 1, 1, 0.15)
const RING_COLOR := Color(1, 1, 1, 0.35)
const KNOB_COLOR := Color(1, 1, 1, 0.45)
const KNOB_ACTIVE_COLOR := Color(0.4, 0.8, 1.0, 0.55)

var _touch_index: int = -1
var _knob_offset: Vector2 = Vector2.ZERO
var _center: Vector2 = Vector2.ZERO


func _ready() -> void:
	# The control needs a minimum size to capture input
	custom_minimum_size = Vector2(BASE_RADIUS * 2 + 20, BASE_RADIUS * 2 + 20)
	size = custom_minimum_size
	_center = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	# Base circle (filled, semi-transparent)
	draw_circle(_center, BASE_RADIUS, BASE_COLOR)
	# Ring outline
	draw_arc(_center, BASE_RADIUS, 0, TAU, 64, RING_COLOR, 2.0)
	# Knob
	var knob_color := KNOB_ACTIVE_COLOR if _touch_index >= 0 else KNOB_COLOR
	draw_circle(_center + _knob_offset, KNOB_RADIUS, knob_color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0:
			_touch_index = event.index
			_update_knob(event.position)
		elif not event.pressed and event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update_knob(event.position)
	# Also handle mouse for desktop testing (emulate_touch_from_mouse)
	elif event is InputEventMouseButton:
		if event.pressed and _touch_index < 0:
			_touch_index = 0
			_update_knob(event.position)
		elif not event.pressed and _touch_index == 0:
			_release()
	elif event is InputEventMouseMotion:
		if _touch_index == 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update_knob(event.position)


func _update_knob(touch_pos: Vector2) -> void:
	var diff := touch_pos - _center
	if diff.length() > BASE_RADIUS:
		diff = diff.normalized() * BASE_RADIUS
	_knob_offset = diff
	queue_redraw()

	# Determine horizontal direction, normalized to [-1, 1]
	var h := _knob_offset.x / BASE_RADIUS
	_apply_direction(h)


func _apply_direction(h: float) -> void:
	if h < -DEADZONE:
		Input.action_press("ui_left")
		Input.action_release("ui_right")
	elif h > DEADZONE:
		Input.action_press("ui_right")
		Input.action_release("ui_left")
	else:
		Input.action_release("ui_left")
		Input.action_release("ui_right")


func _release() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	queue_redraw()
	Input.action_release("ui_left")
	Input.action_release("ui_right")
