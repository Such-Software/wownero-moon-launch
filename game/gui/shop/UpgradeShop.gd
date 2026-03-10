extends Control
## Upgrade shop screen — shown between levels (from Victory screen).
## Reads upgrade levels and wallet from globalvar. Fully self-contained.

const BS = preload("res://game/gui/ButtonStyles.gd")

var _upgrade_buttons := {}  # upgrade_name -> Button
var _upgrade_pips := {}     # upgrade_name -> HBoxContainer of pip rects
var _wallet_label: Label = null
var _title_label: Label = null
var _ad_button: Button = null

# Icons for each upgrade
const UPGRADE_ICONS := {
	"thrust": "▲",
	"fuel_capacity": "⛽",
	"fuel_efficiency": "⚡",
	"armor": "🛡",
	"landing_gear": "⬇",
	"shield": "🟢",
	"rotation": "🔄",
	"reverse_thrust": "▼",
	"magnet": "🧲",
	"cannon": "🔫",
}

# Accent colors for each upgrade
const UPGRADE_COLORS := {
	"thrust": Color(1.0, 0.5, 0.2),        # orange
	"fuel_capacity": Color(0.2, 0.8, 0.4),   # green
	"fuel_efficiency": Color(0.3, 0.7, 1.0),  # blue
	"armor": Color(0.8, 0.3, 0.9),           # purple
	"landing_gear": Color(1.0, 0.85, 0.2),   # gold
	"shield": Color(0.2, 1.0, 0.6),          # teal
	"rotation": Color(0.6, 0.6, 1.0),        # lavender
	"reverse_thrust": Color(1.0, 0.35, 0.35), # red
	"magnet": Color(0.9, 0.5, 1.0),          # pink
	"cannon": Color(1.0, 0.6, 0.15),          # fiery orange
}


func _ready() -> void:
	# Full-screen dark background with subtle gradient
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.08, 1.0)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Starfield accent line at top
	var accent_line := ColorRect.new()
	accent_line.color = Color(0.15, 0.3, 0.6, 0.6)
	accent_line.position = Vector2(0, 0)
	accent_line.size = Vector2(1024, 3)
	add_child(accent_line)

	# Title with glow effect
	_title_label = Label.new()
	_title_label.text = "⚙  UPGRADE SHOP  ⚙"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.set_anchors_preset(PRESET_TOP_WIDE)
	_title_label.offset_top = 12
	_title_label.offset_bottom = 50
	add_child(_title_label)

	# Wallet display — styled like a crypto balance
	var wallet_panel := PanelContainer.new()
	var wallet_style := StyleBoxFlat.new()
	wallet_style.bg_color = Color(0.08, 0.06, 0.02, 0.9)
	wallet_style.border_color = Color(1.0, 0.75, 0.1, 0.5)
	wallet_style.set_border_width_all(1)
	wallet_style.set_corner_radius_all(6)
	wallet_style.content_margin_left = 20
	wallet_style.content_margin_right = 20
	wallet_style.content_margin_top = 4
	wallet_style.content_margin_bottom = 4
	wallet_panel.add_theme_stylebox_override("panel", wallet_style)
	wallet_panel.position = Vector2(362, 50)
	wallet_panel.size = Vector2(300, 30)
	add_child(wallet_panel)

	_wallet_label = Label.new()
	_wallet_label.add_theme_font_size_override("font_size", 16)
	_wallet_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wallet_panel.add_child(_wallet_label)
	_update_wallet_label()

	# Rewarded ad button (only if ads supported and not ad-free)
	if AdManager.is_ad_supported() and not AdManager.is_ad_free():
		_ad_button = Button.new()
		_ad_button.text = "🎬  Watch Ad for %d WOW" % AdManager.REWARDED_AD_WOW
		_ad_button.custom_minimum_size = Vector2(280, 34)
		BS.apply_space_style(_ad_button, Color(1.0, 0.85, 0.1))
		_ad_button.pressed.connect(_on_watch_ad)
		_ad_button.position = Vector2(372, 50)
		add_child(_ad_button)
		# Shift wallet panel left to make room
		wallet_panel.position = Vector2(80, 50)

	# Show banner ad on shop screen
	AdManager.show_banner()

	# Scrollable upgrade list
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(80, 90)
	scroll.size = Vector2(864, 420)
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# Upgrade cards
	for upgrade_name in globalvar.upgrades.keys():
		var card := _create_upgrade_card(upgrade_name)
		vbox.add_child(card)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	# Continue button
	var continue_btn := Button.new()
	if globalvar.has_next_level():
		var next_name: String = globalvar.LEVEL_NAMES.get(globalvar.nowlevel + 1, "")
		continue_btn.text = "▶  Continue to Level " + str(globalvar.nowlevel + 1) + " — " + next_name
	else:
		continue_btn.text = "★  All Levels Cleared!  Return to Menu  ★"
	continue_btn.custom_minimum_size = Vector2(864, 50)
	BS.apply_space_style(continue_btn, Color(0.2, 1.0, 0.3))
	continue_btn.pressed.connect(_on_continue)
	vbox.add_child(continue_btn)

	# Back to menu button
	var menu_btn := Button.new()
	menu_btn.text = "Back to Menu"
	menu_btn.custom_minimum_size = Vector2(864, 42)
	BS.apply_space_style(menu_btn, Color(0.8, 0.2, 0.2))
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn"))
	vbox.add_child(menu_btn)


func _on_watch_ad() -> void:
	if _ad_button:
		_ad_button.disabled = true
		_ad_button.text = "Loading..."
	AdManager.show_rewarded(_on_rewarded_result)


func _on_rewarded_result(success: bool) -> void:
	if success:
		globalvar.add_crypto(AdManager.REWARDED_AD_WOW)
		_update_wallet_label()
		# Refresh all buy buttons (player may now afford upgrades)
		for uname in _upgrade_buttons.keys():
			_style_buy_button(uname)
		if _ad_button:
			_ad_button.text = "+%d WOW!" % AdManager.REWARDED_AD_WOW
			# Re-enable after a brief cooldown
			var timer := get_tree().create_timer(3.0)
			timer.timeout.connect(func():
				if is_instance_valid(_ad_button):
					_ad_button.disabled = false
					_ad_button.text = "🎬  Watch Ad for %d WOW" % AdManager.REWARDED_AD_WOW
			)
	else:
		if _ad_button:
			_ad_button.text = "Ad unavailable"
			_ad_button.disabled = true


func _create_upgrade_card(upgrade_name: String) -> PanelContainer:
	var level: int = globalvar.upgrades[upgrade_name]
	var max_level: int = globalvar.UPGRADE_MAX_LEVEL
	var desc: String = globalvar.UPGRADE_DESCRIPTIONS.get(upgrade_name, upgrade_name)
	var accent: Color = UPGRADE_COLORS.get(upgrade_name, Color.CYAN)
	var icon_text: String = UPGRADE_ICONS.get(upgrade_name, "●")
	var is_maxed := level >= max_level

	# Card panel
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.05, 0.15, 0.85)
	card_style.border_color = accent * 0.4 if not is_maxed else Color(0.25, 0.25, 0.25, 0.5)
	card_style.set_border_width_all(1)
	card_style.border_width_left = 3
	card_style.set_corner_radius_all(6)
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	if not is_maxed:
		card_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.1)
		card_style.shadow_size = 4
	card.add_theme_stylebox_override("panel", card_style)
	card.custom_minimum_size = Vector2(840, 56)

	# HBox layout inside card
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	# Icon
	var icon_label := Label.new()
	icon_label.text = icon_text
	icon_label.add_theme_font_size_override("font_size", 22)
	icon_label.add_theme_color_override("font_color", accent if not is_maxed else Color(0.4, 0.4, 0.4))
	icon_label.custom_minimum_size = Vector2(30, 0)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon_label)

	# Description + level
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = desc
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color.WHITE if not is_maxed else Color(0.5, 0.5, 0.5))
	info_vbox.add_child(name_label)

	# Pip bar
	var pip_hbox := HBoxContainer.new()
	pip_hbox.add_theme_constant_override("separation", 4)
	info_vbox.add_child(pip_hbox)
	_upgrade_pips[upgrade_name] = pip_hbox
	_rebuild_pips(upgrade_name)

	# Buy button (right side)
	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(140, 38)
	_upgrade_buttons[upgrade_name] = buy_btn
	_style_buy_button(upgrade_name)
	var uname: String = upgrade_name
	buy_btn.pressed.connect(func(): _on_upgrade_pressed(uname))
	hbox.add_child(buy_btn)

	return card


func _rebuild_pips(upgrade_name: String) -> void:
	var pip_hbox: HBoxContainer = _upgrade_pips[upgrade_name]
	var level: int = globalvar.upgrades[upgrade_name]
	var max_level: int = globalvar.UPGRADE_MAX_LEVEL
	var accent: Color = UPGRADE_COLORS.get(upgrade_name, Color.CYAN)

	# Clear old pips
	for child in pip_hbox.get_children():
		child.queue_free()

	for i in range(max_level):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(24, 6)
		if i < level:
			pip.color = accent
		else:
			pip.color = Color(0.15, 0.15, 0.25, 0.8)
		pip_hbox.add_child(pip)


func _style_buy_button(upgrade_name: String) -> void:
	var btn: Button = _upgrade_buttons[upgrade_name]
	var level: int = globalvar.upgrades[upgrade_name]
	var max_level: int = globalvar.UPGRADE_MAX_LEVEL
	var accent: Color = UPGRADE_COLORS.get(upgrade_name, Color.CYAN)

	if level >= max_level:
		btn.text = "✓ MAXED"
		btn.disabled = true
		BS.apply_space_style(btn, Color(0.3, 0.3, 0.3))
	else:
		var cost := globalvar.get_upgrade_cost(upgrade_name)
		btn.text = str(cost) + " WOW"
		if globalvar.can_buy_upgrade(upgrade_name):
			btn.disabled = false
			BS.apply_space_style(btn, accent)
		else:
			btn.disabled = true
			BS.apply_space_style(btn, Color(0.25, 0.25, 0.35))


func _update_wallet_label() -> void:
	_wallet_label.text = "💰  " + str(globalvar.wallet) + " WOW"


func _on_upgrade_pressed(upgrade_name: String) -> void:
	if globalvar.buy_upgrade(upgrade_name):
		_update_wallet_label()
		_rebuild_pips(upgrade_name)
		for uname in _upgrade_buttons.keys():
			_style_buy_button(uname)


func _on_continue() -> void:
	var next_scene := globalvar.get_next_level_scene()
	if next_scene.is_empty():
		get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
	else:
		get_tree().change_scene_to_file(next_scene)
