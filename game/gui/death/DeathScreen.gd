extends CanvasLayer
## DeathScreen — overlay shown after death with retry options.
## Replaces the old "3s death timer → jump to menu" flow.
##
## Options shown:
##   - "Retry Level" (always free)
##   - "Watch Ad for 50 WOW" (only if ads supported and not ad-free)
##   - "Quit to Menu"
##
## Instantiated by Rocket.gd after death animation completes.

const BS = preload("res://game/gui/ButtonStyles.gd")

## Show an interstitial every N retries (not every time — that's annoying)
const INTERSTITIAL_EVERY := 3
static var _retry_count: int = 0

var _panel: PanelContainer
var _ad_button: Button


func _ready() -> void:
	layer = 10
	_build_ui()


func _build_ui() -> void:
	# Semi-transparent dark overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Center panel
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(340, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.04, 0.12, 0.95)
	panel_style.border_color = Color(1.0, 0.3, 0.3, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 20
	panel_style.content_margin_bottom = 20
	panel_style.shadow_color = Color(1.0, 0.2, 0.2, 0.3)
	panel_style.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "MISSION FAILED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# Level name
	var level_name: String = globalvar.LEVEL_NAMES.get(globalvar.nowlevel, str(globalvar.nowlevel))
	var subtitle := Label.new()
	subtitle.text = "Level %d — %s" % [globalvar.nowlevel, level_name]
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
	subtitle.add_theme_font_size_override("font_size", 14)
	vbox.add_child(subtitle)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)

	# Retry button (always available, always free)
	var retry_btn := Button.new()
	retry_btn.text = "Retry Level"
	retry_btn.custom_minimum_size = Vector2(280, 44)
	BS.apply_space_style(retry_btn, Color(0.2, 0.8, 1.0))
	retry_btn.pressed.connect(_on_retry)
	vbox.add_child(retry_btn)

	# Waypoint retry button (only if checkpoint exists)
	var waypoint_btn: Button = null
	if globalvar.has_checkpoint:
		waypoint_btn = Button.new()
		waypoint_btn.text = "Retry from %s" % globalvar.checkpoint_planet_name
		waypoint_btn.custom_minimum_size = Vector2(280, 44)
		BS.apply_space_style(waypoint_btn, Color(0.3, 1.0, 0.5))
		waypoint_btn.pressed.connect(_on_retry_waypoint)
		vbox.add_child(waypoint_btn)

	# Rewarded ad button (only if ads are available)
	if AdManager.is_ad_supported() and not AdManager.is_ad_free():
		_ad_button = Button.new()
		_ad_button.text = "Watch Ad for %d WOW" % AdManager.REWARDED_AD_WOW
		_ad_button.custom_minimum_size = Vector2(280, 44)
		BS.apply_space_style(_ad_button, Color(1.0, 0.85, 0.1))
		_ad_button.pressed.connect(_on_watch_ad)
		vbox.add_child(_ad_button)

	# Quit button
	var quit_btn := Button.new()
	quit_btn.text = "Quit to Menu"
	quit_btn.custom_minimum_size = Vector2(280, 44)
	BS.apply_space_style(quit_btn, Color(1.0, 0.3, 0.3))
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	# Collect buttons for stagger animation
	var _buttons: Array[Button] = [retry_btn]
	if waypoint_btn:
		_buttons.append(waypoint_btn)
	if _ad_button:
		_buttons.append(_ad_button)
	_buttons.append(quit_btn)

	# Animate panel in (slide from bottom + fade)
	_panel.modulate = Color(1, 1, 1, 0)
	_panel.position.y += 40
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate", Color.WHITE, 0.4)
	tween.tween_property(_panel, "position:y", _panel.position.y - 40, 0.4)

	# Stagger buttons sliding in from right
	for i in _buttons.size():
		var btn := _buttons[i]
		var final_x := btn.position.x
		btn.position.x += 60
		btn.modulate = Color(1, 1, 1, 0)
		var btn_tw := create_tween()
		btn_tw.set_ease(Tween.EASE_OUT)
		btn_tw.set_trans(Tween.TRANS_CUBIC)
		btn_tw.set_parallel(true)
		var delay := 0.25 + i * 0.1  # after panel starts appearing
		btn_tw.tween_property(btn, "position:x", final_x, 0.35).set_delay(delay)
		btn_tw.tween_property(btn, "modulate", Color.WHITE, 0.25).set_delay(delay)


func _on_retry() -> void:
	_retry_count += 1
	if _retry_count % INTERSTITIAL_EVERY == 0:
		# Show interstitial before retrying; retry happens after it closes
		AdManager.interstitial_closed.connect(_do_retry, CONNECT_ONE_SHOT)
		AdManager.show_interstitial()
	else:
		_do_retry()


func _do_retry() -> void:
	Engine.time_scale = 1.0
	var scene_path: String = globalvar.get_level_scene(globalvar.nowlevel)
	get_tree().change_scene_to_file(scene_path)


func _on_retry_waypoint() -> void:
	Engine.time_scale = 1.0
	globalvar.restore_checkpoint = true
	var scene_path: String = globalvar.get_level_scene(globalvar.nowlevel)
	get_tree().change_scene_to_file(scene_path)


func _on_watch_ad() -> void:
	if _ad_button:
		_ad_button.disabled = true
		_ad_button.text = "Loading..."
	AdManager.show_rewarded(_on_rewarded_result)


func _on_rewarded_result(success: bool) -> void:
	if success:
		globalvar.add_crypto(AdManager.REWARDED_AD_WOW)
		if _ad_button:
			_ad_button.text = "+%d WOW!" % AdManager.REWARDED_AD_WOW
			_ad_button.disabled = true
	else:
		if _ad_button:
			_ad_button.text = "Ad unavailable"
			_ad_button.disabled = true


func _on_quit() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
