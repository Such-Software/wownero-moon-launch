extends CanvasLayer

## UI overlay controller.
## On mobile: hides old TouchScreenButtons, creates virtual joystick + thrust buttons.
## On desktop: hides all touch controls, adds Escape key for pause menu.

const VirtualJoystickScript = preload("res://game/gui/VirtualJoystick.gd")
const ThrustButtonScript = preload("res://game/gui/ThrustButton.gd")
const FireButtonScript = preload("res://game/gui/FireButton.gd")
const WeaponButtonScript = preload("res://game/gui/WeaponButton.gd")
const FuelBarScript = preload("res://game/gui/hud/FuelBar.gd")
const WalletHUDScript = preload("res://game/gui/hud/WalletHUD.gd")
const DebugOverlayScript = preload("res://game/gui/hud/DebugOverlay.gd")
const BS = preload("res://game/gui/ButtonStyles.gd")

var is_mobile: bool = false
var _joystick: Control = null
var _thrust_btn: Control = null
var _reverse_btn: Control = null
var _fire_btn: Control = null
var _missile_btn: Control = null
var _laser_btn: Control = null
var _emp_btn: Control = null
var _fuel_bar: Control = null
var _wallet_hud: Control = null
var _debug_overlay: Control = null
var _target_arrow: Control = null
var _pause_controls_btn: Button = null
var _highlight_tweens: Dictionary = {}

# List of old TouchScreenButton node names to hide/disable
var _touch_button_names := ["left", "right", "up", "down", "menu"]


func _ready() -> void:
	# Detect platform: true on Android, iOS, Web on mobile
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

	# Style the pause popup buttons
	var resume_btn = get_node_or_null("popupMenu/Resume")
	var restart_btn = get_node_or_null("popupMenu/Restart")
	var back_btn = get_node_or_null("popupMenu/backtomenu")
	if resume_btn:
		BS.apply_space_style(resume_btn, Color.GREEN)
	if restart_btn:
		BS.apply_space_style(restart_btn, Color(0.2, 0.8, 1.0))
	if back_btn:
		BS.apply_space_style(back_btn, Color.RED)

	# A proper, always-tappable Pause button (top-right). The legacy `menu`
	# TouchScreenButton was hidden on mobile / freed on desktop, so there was
	# no way to pause on phones. This replaces it on every platform.
	_setup_pause_button()

	if is_mobile:
		_setup_mobile()
	else:
		_setup_desktop()

	# HUD widgets — always visible on all platforms
	_setup_hud()

	# Live control-scheme hot-swap (WP-A2): joystick visibility + tilt
	# recalibration update the instant the setting changes, no level reload.
	globalvar.control_scheme_changed.connect(_on_control_scheme_changed)
	# Gamepad hotplug (desktop): one-time hint + reveal the pause Controls row.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Pause popup Controls row (mobile cycles scheme, desktop cycles glyphs).
	_setup_pause_controls_row()


func _setup_pause_button() -> void:
	var vp := get_viewport().get_visible_rect().size
	var btn := Button.new()
	btn.name = "PauseButton"
	btn.text = "II"
	btn.custom_minimum_size = Vector2(54, 54)
	btn.add_theme_font_size_override("font_size", 22)
	btn.focus_mode = Control.FOCUS_NONE
	# Stays tappable even while paused (harmless) and during slow-mo.
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	BS.apply_space_style(btn, Color(0.7, 0.7, 0.85))
	add_child(btn)
	btn.position = Vector2(vp.x - 66.0, 12.0)
	btn.pressed.connect(_on_menu_pressed)
	get_viewport().size_changed.connect(func() -> void:
		if is_instance_valid(btn):
			var v := get_viewport().get_visible_rect().size
			btn.position = Vector2(v.x - 66.0, 12.0)
	)


func _setup_mobile() -> void:
	# Hide the old TouchScreenButton nodes
	for btn_name in _touch_button_names:
		var btn = get_node_or_null(btn_name)
		if btn:
			btn.visible = false

	var vp := get_viewport().get_visible_rect().size

	# Create virtual joystick (bottom-left) — hidden when tilt-to-turn is active
	_joystick = Control.new()
	_joystick.set_script(VirtualJoystickScript)
	_joystick.name = "VirtualJoystick"
	add_child(_joystick)
	_joystick.position = Vector2(20, vp.y - 170)
	_joystick.visible = (globalvar.control_scheme != globalvar.ControlScheme.TILT)

	# Create thrust button (right side, upper)
	_thrust_btn = Control.new()
	_thrust_btn.set_script(ThrustButtonScript)
	_thrust_btn.name = "ThrustBtn"
	_thrust_btn.set("action_name", "thrust")
	_thrust_btn.set("arrow_up", true)
	add_child(_thrust_btn)
	_thrust_btn.position = Vector2(vp.x - 104, vp.y - 250)

	# Create reverse thrust button (right side, lower)
	_reverse_btn = Control.new()
	_reverse_btn.set_script(ThrustButtonScript)
	_reverse_btn.name = "ReverseBtn"
	_reverse_btn.set("action_name", "revthrust")
	_reverse_btn.set("arrow_up", false)
	add_child(_reverse_btn)
	_reverse_btn.position = Vector2(vp.x - 104, vp.y - 140)

	# Fire button — only if cannon upgrade purchased (left side, above joystick)
	if globalvar.upgrades.get("cannon", 0) > 0:
		_fire_btn = Control.new()
		_fire_btn.set_script(FireButtonScript)
		_fire_btn.name = "FireBtn"
		add_child(_fire_btn)
		_fire_btn.position = Vector2(20, vp.y - 260)

	# Weapon buttons — stack vertically on right side above thrust buttons
	var weapon_y := vp.y - 320
	if globalvar.upgrades.get("missile", 0) > 0:
		_missile_btn = Control.new()
		_missile_btn.set_script(WeaponButtonScript)
		_missile_btn.name = "MissileBtn"
		_missile_btn.set("action_name", "missile")
		_missile_btn.set("icon_text", "M")
		_missile_btn.set("base_color", Color(1.0, 0.3, 0.1))
		_missile_btn.set("ring_color", Color(1.0, 0.4, 0.2, 0.35))
		_missile_btn.set("ammo_count", globalvar.upgrades.get("missile", 0) * 2)
		add_child(_missile_btn)
		_missile_btn.position = Vector2(vp.x - 174, weapon_y)
		weapon_y -= 68.0

	if globalvar.upgrades.get("laser", 0) > 0:
		_laser_btn = Control.new()
		_laser_btn.set_script(WeaponButtonScript)
		_laser_btn.name = "LaserBtn"
		_laser_btn.set("action_name", "laser")
		_laser_btn.set("icon_text", "L")
		_laser_btn.set("base_color", Color(0.2, 0.8, 1.0))
		_laser_btn.set("ring_color", Color(0.3, 0.7, 1.0, 0.35))
		add_child(_laser_btn)
		_laser_btn.position = Vector2(vp.x - 174, weapon_y)
		weapon_y -= 68.0

	if globalvar.upgrades.get("emp", 0) > 0:
		_emp_btn = Control.new()
		_emp_btn.set_script(WeaponButtonScript)
		_emp_btn.name = "EMPBtn"
		_emp_btn.set("action_name", "emp")
		_emp_btn.set("icon_text", "E")
		_emp_btn.set("base_color", Color(0.4, 0.6, 1.0))
		_emp_btn.set("ring_color", Color(0.5, 0.7, 1.0, 0.35))
		_emp_btn.set("ammo_count", globalvar.upgrades.get("emp", 0))
		add_child(_emp_btn)
		_emp_btn.position = Vector2(vp.x - 174, weapon_y)

	# Reposition controls on viewport resize (orientation change, etc.)
	get_viewport().size_changed.connect(_reposition_controls)


func _reposition_controls() -> void:
	var vp := get_viewport().get_visible_rect().size
	if _joystick:
		_joystick.position = Vector2(20, vp.y - 170)
	if _thrust_btn:
		_thrust_btn.position = Vector2(vp.x - 104, vp.y - 250)
	if _reverse_btn:
		_reverse_btn.position = Vector2(vp.x - 104, vp.y - 140)
	if _fire_btn:
		_fire_btn.position = Vector2(20, vp.y - 260)
	var weapon_y := vp.y - 320
	for btn in [_missile_btn, _laser_btn, _emp_btn]:
		if btn and is_instance_valid(btn):
			btn.position = Vector2(vp.x - 174, weapon_y)
			weapon_y -= 68.0


func _setup_desktop() -> void:
	# Remove old TouchScreenButton nodes entirely on desktop
	for btn_name in _touch_button_names:
		var btn = get_node_or_null(btn_name)
		if btn:
			btn.queue_free()


func _setup_hud() -> void:
	# Fuel bar — top-left, clear of the small menu button at (51,34)
	_fuel_bar = Control.new()
	_fuel_bar.set_script(FuelBarScript)
	_fuel_bar.name = "FuelBar"
	add_child(_fuel_bar)
	_fuel_bar.position = Vector2(120, 10)

	# Wallet display — next to fuel bar
	_wallet_hud = Control.new()
	_wallet_hud.set_script(WalletHUDScript)
	_wallet_hud.name = "WalletHUD"
	add_child(_wallet_hud)
	_wallet_hud.position = Vector2(120, 28)

	# Debug overlay — toggled with F3 (starts hidden)
	_debug_overlay = Control.new()
	_debug_overlay.set_script(DebugOverlayScript)
	_debug_overlay.name = "DebugOverlay"
	add_child(_debug_overlay)
	_debug_overlay.position = Vector2(400, 10)

	# Off-screen target arrow (WP-B2). Guarded so this compiles/runs before B2
	# lands the script — mounts full-rect on this HUD CanvasLayer.
	const TARGET_ARROW_PATH := "res://game/gui/hud/TargetArrow.gd"
	if ResourceLoader.exists(TARGET_ARROW_PATH):
		_target_arrow = Control.new()
		_target_arrow.set_script(load(TARGET_ARROW_PATH))
		_target_arrow.name = "TargetArrow"
		_target_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
		_target_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_target_arrow)


# --- Live control-scheme hot-swap (WP-A2) ---

func _on_control_scheme_changed() -> void:
	## Fired whenever control_scheme / desktop_control changes. Update the
	## joystick live (fixes the one-shot at _setup_mobile:97) and re-calibrate the
	## tilt baseline when tilt just became the active input, so there's no stuck
	## turn from a stale hold position.
	if _joystick and is_instance_valid(_joystick):
		_joystick.visible = (globalvar.control_scheme != globalvar.ControlScheme.TILT)
	if globalvar.active_input_hint() == globalvar.InputHint.TILT:
		var rocket := get_tree().get_first_node_in_group("rocket")
		if rocket and rocket.has_method("_calibrate_tilt"):
			rocket.call("_calibrate_tilt")
	_refresh_pause_controls_row()


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	## Desktop gamepad hotplug: first connect while still on KEYBOARD surfaces a
	## one-time hint pointing at Pause/Options. Also reveals the pause row.
	if not is_mobile and connected and globalvar.desktop_control == globalvar.DesktopControl.KEYBOARD:
		var hs := get_node_or_null("/root/HintService")
		if hs:
			hs.show_hint("gamepad_detected", "Controller detected — switch to gamepad in Pause/Options")
	_refresh_pause_controls_row()


# --- Coach-mark highlight (WP-B1 calls this) ---

func highlight(btn_name: String, on: bool) -> void:
	## Pulse-scale an on-screen control to draw the eye. Accepts "thrust",
	## "revthrust"/"reverse", or "joystick". No-op if that control isn't present.
	var node: Control = null
	match btn_name:
		"thrust": node = _thrust_btn
		"revthrust", "reverse": node = _reverse_btn
		"joystick": node = _joystick
	if node == null or not is_instance_valid(node):
		return
	var existing = _highlight_tweens.get(btn_name)
	if existing and existing.is_valid():
		existing.kill()
	_highlight_tweens.erase(btn_name)
	if not on:
		node.scale = Vector2.ONE
		return
	node.pivot_offset = node.size / 2.0
	var t := create_tween().set_loops()
	t.tween_property(node, "scale", Vector2(1.18, 1.18), 0.4).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)
	_highlight_tweens[btn_name] = t


# --- Pause popup Controls row (WP-A2) ---

func _setup_pause_controls_row() -> void:
	_pause_controls_btn = get_node_or_null("popupMenu/Controls") as Button
	if _pause_controls_btn == null:
		return
	BS.apply_space_style(_pause_controls_btn, Color(0.5, 0.8, 1.0))
	_pause_controls_btn.pressed.connect(_on_pause_controls_pressed)
	_refresh_pause_controls_row()


func _refresh_pause_controls_row() -> void:
	if _pause_controls_btn == null or not is_instance_valid(_pause_controls_btn):
		return
	if is_mobile:
		# Mobile always cycles Tilt / Joystick.
		_pause_controls_btn.visible = true
		_pause_controls_btn.text = "Controls: %s" % globalvar.CONTROL_SCHEME_NAMES.get(globalvar.control_scheme, "Tilt")
	else:
		# Desktop: only meaningful (and only shown) when a controller is connected.
		_pause_controls_btn.visible = Input.get_connected_joypads().size() > 0
		_pause_controls_btn.text = "Controls: %s" % globalvar.DESKTOP_CONTROL_NAMES.get(globalvar.desktop_control, "Keyboard")


func _on_pause_controls_pressed() -> void:
	if is_mobile:
		globalvar.set_control_scheme((globalvar.control_scheme + 1) % 2)
	else:
		globalvar.set_desktop_control((globalvar.desktop_control + 1) % 2)
	globalvar.save_game()
	_refresh_pause_controls_row()


func _unhandled_input(event: InputEvent) -> void:
	# Escape key toggles pause menu on any platform
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	if get_tree().paused:
		_on_Resume_pressed()
	else:
		_on_menu_pressed()


# --- Signal callbacks (kept for scene signal connections) ---

func _on_left_pressed():
	Input.action_press("ui_left")

func _on_right_pressed():
	Input.action_press("ui_right")

func _on_up_pressed():
	Input.action_press("thrust")

func _on_down_pressed():
	Input.action_press("revthrust")

func _on_left_released():
	Input.action_release("ui_left")

func _on_right_released():
	Input.action_release("ui_right")

func _on_up_released():
	Input.action_release("thrust")

func _on_down_released():
	Input.action_release("revthrust")

func _on_menu_pressed():
	get_tree().paused = true
	_refresh_pause_controls_row()
	var popup := $popupMenu
	var vp := get_viewport().get_visible_rect().size
	var sz: Vector2 = popup.get_combined_minimum_size()
	popup.position = Vector2((vp.x - sz.x) / 2.0, (vp.y - sz.y) / 2.0)
	popup.show()

func _on_Resume_pressed():
	get_tree().paused = false
	$popupMenu.hide()

func _on_restart_pressed():
	# Restart the current level — mirrors DeathScreen._on_retry so behavior is
	# identical to a death-retry: reset time scale, reload the level scene.
	get_tree().paused = false
	$popupMenu.hide()
	Engine.time_scale = 1.0
	var scene_path: String = globalvar.get_level_scene(globalvar.nowlevel)
	get_tree().change_scene_to_file(scene_path)

func _on_backtomenu_pressed():
	get_tree().paused = false
	$popupMenu.hide()
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
