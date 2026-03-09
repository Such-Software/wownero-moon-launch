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
	_tutorial_label = Label.new()
	_tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tutorial_label.add_theme_font_size_override("font_size", 22)
	_tutorial_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_tutorial_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_tutorial_label.add_theme_constant_override("shadow_offset_x", 2)
	_tutorial_label.add_theme_constant_override("shadow_offset_y", 2)
	_tutorial_label.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_tutorial_label.position = Vector2(-200, -80)
	_tutorial_label.size = Vector2(400, 60)
	$CanvasLayer.add_child(_tutorial_label)
	_next_tutorial_step()


func _next_tutorial_step() -> void:
	const PROMPTS := [
		"Press UP to thrust!",
		"LEFT / RIGHT to rotate",
		"Land gently on the Moon!",
	]
	if _tutorial_step >= PROMPTS.size():
		globalvar.tutorial_shown = true
		globalvar.save_game()
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
