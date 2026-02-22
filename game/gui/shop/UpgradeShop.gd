extends Control
## Upgrade shop screen — shown between levels (from Victory screen).
## Reads upgrade levels and wallet from globalvar. Fully self-contained.

const BS = preload("res://game/gui/ButtonStyles.gd")

var _upgrade_buttons := {}  # upgrade_name -> Button
var _wallet_label: Label = null
var _title_label: Label = null


func _ready() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.12, 1.0)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Title
	_title_label = Label.new()
	_title_label.text = "UPGRADE SHOP"
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(312, 20)
	_title_label.size = Vector2(400, 40)
	add_child(_title_label)

	# Wallet display
	_wallet_label = Label.new()
	_wallet_label.add_theme_font_size_override("font_size", 18)
	_wallet_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wallet_label.position = Vector2(312, 62)
	_wallet_label.size = Vector2(400, 30)
	add_child(_wallet_label)
	_update_wallet_label()

	# Upgrade buttons in a VBox
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(200, 110)
	vbox.size = Vector2(624, 400)
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	for upgrade_name in globalvar.upgrades.keys():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(624, 48)
		btn.flat = true
		_upgrade_buttons[upgrade_name] = btn
		_update_button(upgrade_name)
		var uname: String = upgrade_name  # capture for lambda
		btn.pressed.connect(func(): _on_upgrade_pressed(uname))
		vbox.add_child(btn)

	# Continue button
	var continue_btn := Button.new()
	if globalvar.has_next_level():
		continue_btn.text = "Continue to Level " + str(globalvar.nowlevel + 1)
	else:
		continue_btn.text = "All levels cleared! Back to Menu"
	continue_btn.custom_minimum_size = Vector2(624, 52)
	continue_btn.flat = true
	BS.apply_space_style(continue_btn, Color.GREEN)
	continue_btn.pressed.connect(_on_continue)
	vbox.add_child(continue_btn)

	# Back to menu button
	var menu_btn := Button.new()
	menu_btn.text = "Back to Menu"
	menu_btn.custom_minimum_size = Vector2(624, 48)
	menu_btn.flat = true
	BS.apply_space_style(menu_btn, Color.RED)
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn"))
	vbox.add_child(menu_btn)


func _update_wallet_label() -> void:
	_wallet_label.text = "Wallet: " + str(globalvar.wallet) + " WOW"


func _update_button(upgrade_name: String) -> void:
	var btn: Button = _upgrade_buttons[upgrade_name]
	var level: int = globalvar.upgrades[upgrade_name]
	var desc: String = globalvar.UPGRADE_DESCRIPTIONS.get(upgrade_name, upgrade_name)
	var max_level: int = globalvar.UPGRADE_MAX_LEVEL

	if level >= max_level:
		btn.text = desc + "  [MAX]"
		BS.apply_space_style(btn, Color(0.4, 0.4, 0.4))
		btn.disabled = true
	else:
		var cost := globalvar.get_upgrade_cost(upgrade_name)
		var level_pips := ""
		for i in range(max_level):
			level_pips += "[*]" if i < level else "[ ]"
		btn.text = desc + "  " + level_pips + "  — " + str(cost) + " WOW"
		if globalvar.can_buy_upgrade(upgrade_name):
			BS.apply_space_style(btn, Color.CYAN)
			btn.disabled = false
		else:
			BS.apply_space_style(btn, Color(0.3, 0.3, 0.5))
			btn.disabled = true


func _on_upgrade_pressed(upgrade_name: String) -> void:
	if globalvar.buy_upgrade(upgrade_name):
		_update_wallet_label()
		# Refresh all buttons (buying one may affect affordability of others)
		for uname in _upgrade_buttons.keys():
			_update_button(uname)


func _on_continue() -> void:
	var next_scene := globalvar.get_next_level_scene()
	if next_scene.is_empty():
		# All levels complete — go back to menu
		get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
	else:
		get_tree().change_scene_to_file(next_scene)
