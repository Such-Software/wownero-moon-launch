extends Control

## Code-drawn thrust/reverse button for mobile.
## Draws a semi-transparent circle with an arrow indicator.
## Set `action_name` to "thrust" or "revthrust" and `arrow_up` accordingly.

@export var action_name: String = "thrust"
@export var arrow_up: bool = true  ## true = thrust (arrow up), false = reverse (arrow down)

const BTN_RADIUS := 40.0
const BASE_COLOR := Color(1, 1, 1, 0.12)
const RING_COLOR := Color(1, 1, 1, 0.3)
const ARROW_COLOR := Color(1, 1, 1, 0.5)
const ACTIVE_BASE := Color(0.4, 0.8, 1.0, 0.25)
const ACTIVE_ARROW := Color(0.4, 0.8, 1.0, 0.7)

var _touch_index: int = -1
var _pressed: bool = false
var _center: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(BTN_RADIUS * 2 + 16, BTN_RADIUS * 2 + 16)
	size = custom_minimum_size
	_center = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	# Base circle
	var bg := ACTIVE_BASE if _pressed else BASE_COLOR
	draw_circle(_center, BTN_RADIUS, bg)
	# Ring
	draw_arc(_center, BTN_RADIUS, 0, TAU, 48, RING_COLOR, 2.0)
	# Arrow triangle
	var arrow_col := ACTIVE_ARROW if _pressed else ARROW_COLOR
	var arrow_size := 18.0
	var points: PackedVector2Array
	if arrow_up:
		points = PackedVector2Array([
			_center + Vector2(0, -arrow_size),
			_center + Vector2(-arrow_size * 0.7, arrow_size * 0.5),
			_center + Vector2(arrow_size * 0.7, arrow_size * 0.5),
		])
	else:
		points = PackedVector2Array([
			_center + Vector2(0, arrow_size),
			_center + Vector2(-arrow_size * 0.7, -arrow_size * 0.5),
			_center + Vector2(arrow_size * 0.7, -arrow_size * 0.5),
		])
	draw_colored_polygon(points, arrow_col)


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
	# Release if the node is removed from tree while pressed
	if what == NOTIFICATION_EXIT_TREE and _pressed:
		Input.action_release(action_name)
