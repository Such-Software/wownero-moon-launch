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
	_level_select_container = VBoxContainer.new()
	_level_select_container.name = "LevelSelect"
	_level_select_container.visible = false
	_level_select_container.set_anchors_preset(Control.PRESET_CENTER)
	_level_select_container.position = Vector2(380, 100)
	_level_select_container.add_theme_constant_override("separation", 12)
	add_child(_level_select_container)

	# Header label
	var header := Label.new()
	header.text = "DEBUG: Level Select"
	header.add_theme_color_override("font_color", Color.YELLOW)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_select_container.add_child(header)

	# Level buttons
	var levels := [
		["Level 1 — Moon", "res://game/levels/1/Level1.tscn"],
		["Level 2 — Mars", "res://game/levels/2/Level2.tscn"],
		["Level 3 — Venus", "res://game/levels/3/Level3.tscn"],
		["Level 4 — Io", "res://game/levels/4/Level4.tscn"],
	]
	for entry in levels:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(260, 40)
		btn.flat = true
		BS.apply_space_style(btn, Color.ORANGE)
		var scene_path: String = entry[1]
		btn.pressed.connect(func(): get_tree().change_scene_to_file(scene_path))
		_level_select_container.add_child(btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close  [D]"
	close_btn.custom_minimum_size = Vector2(260, 40)
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
	_level_select_container.visible = _level_select_visible

func _on_QuitButton_pressed():
	get_tree().quit()

func _on_PlayButton_pressed():
	print("Play pressed! Level: ", globalvar.nowlevel)
	match(globalvar.nowlevel):
		1:
			get_tree().change_scene_to_file("res://game/levels/1/Level1.tscn")
		2:
			get_tree().change_scene_to_file("res://game/levels/2/Level2.tscn")
		3:
			get_tree().change_scene_to_file("res://game/levels/3/Level3.tscn")
		4:
			get_tree().change_scene_to_file("res://game/levels/4/Level4.tscn")
		_:
			get_tree().change_scene_to_file("res://game/levels/1/Level1.tscn")

func _on_HelpButton_pressed():
	get_tree().change_scene_to_file("res://game/gui/help/Help.tscn")
