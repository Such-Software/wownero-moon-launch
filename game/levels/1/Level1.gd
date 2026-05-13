extends Node2D

# Tutorial pacing (seconds)
const TUTORIAL_HOLD := 4.0   # full-opacity hold time per message
const TUTORIAL_FADE := 1.0   # fade-out duration
const TUTORIAL_GAP := 0.6    # blank time between messages

enum TutState { HOLD, FADE, GAP, DONE }

var _tutorial_label: Label = null
var _tutorial_step := 0
var _tutorial_timer := 0.0
var _tutorial_state: int = TutState.DONE
var _tutorial_messages: Array[String] = []


func _ready():
	globalvar.nowlevel = 1
	var space = get_world_2d().get_space()
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, 0)
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)
	if not globalvar.tutorial_shown:
		_show_tutorial()


func _show_tutorial() -> void:
	# Persist the flag the moment the tutorial is *shown* — fast clears still count.
	globalvar.tutorial_shown = true
	globalvar.save_game()

	_tutorial_messages = _build_tutorial_messages()

	_tutorial_label = Label.new()
	_tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tutorial_label.add_theme_font_size_override("font_size", 24)
	_tutorial_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_tutorial_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_tutorial_label.add_theme_constant_override("shadow_offset_x", 2)
	_tutorial_label.add_theme_constant_override("shadow_offset_y", 2)
	_tutorial_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tutorial_label.offset_top = 80
	_tutorial_label.offset_bottom = 120
	$CanvasLayer.add_child(_tutorial_label)
	_next_tutorial_step()


func _build_tutorial_messages() -> Array[String]:
	## Platform-aware prompts. Mobile uses on-screen control names; desktop uses keys.
	var is_mobile: bool = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	if is_mobile:
		var rotate_hint := "Tilt phone LEFT / RIGHT to turn"
		if globalvar.control_scheme == globalvar.ControlScheme.JOYSTICK:
			rotate_hint = "Use the joystick to rotate"
		return [
			"Welcome, Pilot!",
			"Hold THRUST to fly up",
			rotate_hint,
			"Tap REVERSE to slow your descent",
			"Switch controls anytime in Options",
			"Land slowly and upright on the Moon!",
		]
	return [
		"Welcome, Pilot!",
		"Press UP to thrust",
		"LEFT / RIGHT to rotate",
		"Press DOWN for reverse thrust",
		"Watch your FUEL (top-left)",
		"Land slowly and upright on the Moon!",
	]


func _next_tutorial_step() -> void:
	if _tutorial_step >= _tutorial_messages.size():
		_tutorial_state = TutState.DONE
		if _tutorial_label:
			_tutorial_label.queue_free()
			_tutorial_label = null
		return
	_tutorial_label.text = _tutorial_messages[_tutorial_step]
	_tutorial_label.modulate = Color(1, 1, 1, 1)
	_tutorial_state = TutState.HOLD
	_tutorial_timer = TUTORIAL_HOLD
	_tutorial_step += 1


func _process(delta):
	if not _tutorial_label or _tutorial_state == TutState.DONE:
		return
	_tutorial_timer -= delta
	if _tutorial_timer > 0.0:
		if _tutorial_state == TutState.FADE:
			_tutorial_label.modulate.a = clampf(_tutorial_timer / TUTORIAL_FADE, 0.0, 1.0)
		return
	# Timer expired — advance state machine
	match _tutorial_state:
		TutState.HOLD:
			_tutorial_state = TutState.FADE
			_tutorial_timer = TUTORIAL_FADE
		TutState.FADE:
			_tutorial_label.modulate.a = 0.0
			_tutorial_state = TutState.GAP
			_tutorial_timer = TUTORIAL_GAP
		TutState.GAP:
			_next_tutorial_step()
