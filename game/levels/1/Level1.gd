extends Node2D

var _tutorial_label: Label = null
var _tutorial_step := 0
var _tutorial_timer := 0.0
const TUTORIAL_FADE := 3.0  # seconds before each prompt fades

func _ready():
	globalvar.nowlevel = 1
	var space = get_world_2d().get_space()
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, 0)
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)
	if not globalvar.tutorial_shown:
		_show_tutorial()


func _show_tutorial() -> void:
	# Persist the flag the moment the tutorial is *shown* — even if the player lands
	# in <9s and never sees all 3 prompts, we don't want to nag them again next run.
	globalvar.tutorial_shown = true
	globalvar.save_game()

	_tutorial_label = Label.new()
	_tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tutorial_label.add_theme_font_size_override("font_size", 24)
	_tutorial_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_tutorial_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_tutorial_label.add_theme_constant_override("shadow_offset_x", 2)
	_tutorial_label.add_theme_constant_override("shadow_offset_y", 2)
	# Anchor to top-center (under the time label) so the rocket and HUD don't cover it.
	_tutorial_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tutorial_label.offset_top = 80
	_tutorial_label.offset_bottom = 120
	$CanvasLayer.add_child(_tutorial_label)
	_next_tutorial_step()


func _next_tutorial_step() -> void:
	const PROMPTS := [
		"Press UP to thrust!",
		"LEFT / RIGHT to rotate",
		"Land gently on the Moon!",
	]
	if _tutorial_step >= PROMPTS.size():
		if _tutorial_label:
			_tutorial_label.queue_free()
			_tutorial_label = null
		return
	_tutorial_label.text = PROMPTS[_tutorial_step]
	_tutorial_label.modulate = Color(1, 1, 1, 1)
	_tutorial_timer = TUTORIAL_FADE
	_tutorial_step += 1


func _process(delta):
	if _tutorial_label and _tutorial_timer > 0.0:
		_tutorial_timer -= delta
		if _tutorial_timer <= 1.0:
			_tutorial_label.modulate.a = maxf(_tutorial_timer, 0.0)
		if _tutorial_timer <= 0.0:
			_next_tutorial_step()
