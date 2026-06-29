extends Control
## Race result — win/lose banner + Race Again / Menu. Built in code.

const BS = preload("res://game/gui/ButtonStyles.gd")


func _ready() -> void:
	var won: bool = globalvar.race_won

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var banner := Label.new()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 42)
	if won:
		banner.text = "🏆  YOU BEAT THE CPU!"
		banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		banner.text = "💀  THE CPU WON"
		banner.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	col.add_child(banner)

	var sub := Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	var lvl_name: String = globalvar.LEVEL_NAMES.get(globalvar.nowlevel, str(globalvar.nowlevel))
	sub.text = "%s — first to land wins." % lvl_name
	col.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	col.add_child(spacer)

	var again := Button.new()
	again.text = "🏁  Race Again"
	again.custom_minimum_size = Vector2(280, 58)
	again.add_theme_font_size_override("font_size", 22)
	BS.apply_space_style(again, Color.GREEN)
	again.pressed.connect(_on_again)
	col.add_child(again)

	var menu := Button.new()
	menu.text = "Menu"
	menu.custom_minimum_size = Vector2(280, 52)
	menu.add_theme_font_size_override("font_size", 20)
	BS.apply_space_style(menu, Color.RED)
	menu.pressed.connect(_on_menu)
	col.add_child(menu)


func _on_again() -> void:
	# race_mode stays true; relaunch the same level (its _ready re-spawns the rival).
	RaceController.teardown()
	get_tree().change_scene_to_file(globalvar.get_level_scene(globalvar.nowlevel))


func _on_menu() -> void:
	globalvar.race_mode = false
	RaceController.teardown()
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
