extends Control

const BS = preload("res://game/gui/ButtonStyles.gd")

var _level_select_visible := false
var _level_select_container: VBoxContainer = null

func _ready():
	$RocketSprite/AnimationPlayer.play("move")
	globalvar.load_game()
	# Style menu buttons
	BS.apply_space_style($VButtonArray/PlayButton, Color.GREEN)
	BS.apply_space_style($VButtonArray/HelpButton, Color.CYAN)
	BS.apply_space_style($VButtonArray/QuitButton, Color.RED)
	_build_level_select()


func _build_level_select() -> void:
	# Hidden level select panel — toggled with D key
	# Wrap in a PanelContainer for a clean dark backdrop
	var panel := PanelContainer.new()
	panel.name = "LevelSelectPanel"
	panel.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.04, 0.12, 0.95)
	panel_style.border_color = Color(1.0, 0.7, 0.1, 0.5)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	# Anchor to top-right so it never clips off screen
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -290
	panel.offset_right = -10
	panel.offset_top = 10
	panel.grow_vertical = Control.GROW_DIRECTION_END

	_level_select_container = VBoxContainer.new()
	_level_select_container.name = "LevelSelect"
	_level_select_container.add_theme_constant_override("separation", 4)
	panel.add_child(_level_select_container)

	# Header label
	var header := Label.new()
	header.text = "DEBUG: Level Select"
	header.add_theme_color_override("font_color", Color.YELLOW)
	header.add_theme_font_size_override("font_size", 14)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_select_container.add_child(header)

	# Level buttons — generated from globalvar.LEVEL_SCENES
	for level_num in globalvar.LEVEL_SCENES.keys():
		var btn := Button.new()
		var level_name: String = globalvar.LEVEL_NAMES.get(level_num, str(level_num))
		btn.text = "Level " + str(level_num) + " — " + level_name
		btn.custom_minimum_size = Vector2(250, 32)
		btn.flat = true
		BS.apply_space_style(btn, Color.ORANGE)
		var scene_path: String = globalvar.LEVEL_SCENES[level_num]
		btn.pressed.connect(func(): get_tree().change_scene_to_file(scene_path))
		_level_select_container.add_child(btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close  [D]"
	close_btn.custom_minimum_size = Vector2(250, 32)
	close_btn.flat = true
	BS.apply_space_style(close_btn, Color.RED)
	close_btn.pressed.connect(_toggle_level_select)
	_level_select_container.add_child(close_btn)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_D:
		_toggle_level_select()
		get_viewport().set_input_as_handled()


func _toggle_level_select() -> void:
	_level_select_visible = !_level_select_visible
	var panel: PanelContainer = get_node("LevelSelectPanel")
	panel.visible = _level_select_visible

func _on_QuitButton_pressed():
	get_tree().quit()

func _on_PlayButton_pressed():
	var scene := globalvar.get_level_scene(globalvar.nowlevel)
	get_tree().change_scene_to_file(scene)

func _on_HelpButton_pressed():
	get_tree().change_scene_to_file("res://game/gui/help/Help.tscn")
