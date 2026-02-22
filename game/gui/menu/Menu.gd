extends Control

const BS = preload("res://game/gui/ButtonStyles.gd")

var _level_select_visible := false
var _level_select_container: VBoxContainer = null
var _nick_label: Label = null
var _nick_edit: LineEdit = null
var _editing_nick := false

func _ready():
	$RocketSprite/AnimationPlayer.play("move")
	globalvar.load_game()
	# Style menu buttons
	BS.apply_space_style($VButtonArray/PlayButton, Color.GREEN)
	BS.apply_space_style($VButtonArray/HelpButton, Color.CYAN)
	BS.apply_space_style($VButtonArray/QuitButton, Color.RED)
	_build_nickname_bar()
	_build_level_select()


func _build_nickname_bar() -> void:
	## Nickname bar at bottom-left: "Pilot: NickName  [🎲] [✏️]"
	var bar := HBoxContainer.new()
	bar.name = "NicknameBar"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.position = Vector2(12, -44)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)

	var pilot_label := Label.new()
	pilot_label.text = "Pilot:"
	pilot_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	pilot_label.add_theme_font_size_override("font_size", 14)
	bar.add_child(pilot_label)

	_nick_label = Label.new()
	_nick_label.name = "NickLabel"
	_nick_label.text = globalvar.nickname
	_nick_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_nick_label.add_theme_font_size_override("font_size", 14)
	bar.add_child(_nick_label)

	# Dice button — reroll random name
	var dice_btn := Button.new()
	dice_btn.text = "Reroll"
	dice_btn.custom_minimum_size = Vector2(65, 26)
	BS.apply_space_style(dice_btn, Color(1.0, 0.7, 0.1))
	dice_btn.add_theme_font_size_override("font_size", 12)
	dice_btn.pressed.connect(_on_reroll_nickname)
	bar.add_child(dice_btn)

	# Edit button — toggle inline text edit
	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.custom_minimum_size = Vector2(50, 26)
	BS.apply_space_style(edit_btn, Color(0.5, 0.8, 1.0))
	edit_btn.add_theme_font_size_override("font_size", 12)
	edit_btn.pressed.connect(_on_edit_nickname)
	bar.add_child(edit_btn)

	# Hidden LineEdit for custom entry
	_nick_edit = LineEdit.new()
	_nick_edit.name = "NickEdit"
	_nick_edit.visible = false
	_nick_edit.custom_minimum_size = Vector2(160, 26)
	_nick_edit.max_length = 20
	_nick_edit.placeholder_text = "Enter nickname..."
	_nick_edit.text = globalvar.nickname
	_nick_edit.add_theme_font_size_override("font_size", 14)
	_nick_edit.add_theme_color_override("font_color", Color.WHITE)
	_nick_edit.add_theme_color_override("caret_color", Color.CYAN)
	var edit_style := StyleBoxFlat.new()
	edit_style.bg_color = Color(0.06, 0.06, 0.14, 0.95)
	edit_style.border_color = Color.CYAN
	edit_style.set_border_width_all(1)
	edit_style.set_corner_radius_all(4)
	edit_style.content_margin_left = 6
	edit_style.content_margin_right = 6
	_nick_edit.add_theme_stylebox_override("normal", edit_style)
	_nick_edit.text_submitted.connect(_on_nickname_submitted)
	bar.add_child(_nick_edit)


func _on_reroll_nickname() -> void:
	globalvar.nickname = globalvar.generate_random_nickname()
	globalvar.save_game()
	_nick_label.text = globalvar.nickname
	_nick_edit.text = globalvar.nickname


func _on_edit_nickname() -> void:
	_editing_nick = !_editing_nick
	if _editing_nick:
		_nick_label.visible = false
		_nick_edit.visible = true
		_nick_edit.text = globalvar.nickname
		_nick_edit.grab_focus()
		_nick_edit.caret_column = _nick_edit.text.length()
	else:
		_apply_nickname(_nick_edit.text)


func _on_nickname_submitted(new_text: String) -> void:
	_apply_nickname(new_text)


func _apply_nickname(raw: String) -> void:
	var cleaned := raw.strip_edges().left(20)
	if cleaned == "":
		cleaned = globalvar.generate_random_nickname()
	globalvar.nickname = cleaned
	globalvar.save_game()
	_editing_nick = false
	_nick_label.text = globalvar.nickname
	_nick_label.visible = true
	_nick_edit.visible = false


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
