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

# List of old TouchScreenButton node names to hide/disable
var _touch_button_names := ["left", "right", "up", "down", "menu"]


func _ready() -> void:
	# Detect platform: true on Android, iOS, Web on mobile
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

	# Style the pause popup buttons
	var resume_btn = get_node_or_null("popupMenu/Resume")
	var back_btn = get_node_or_null("popupMenu/backtomenu")
	if resume_btn:
		BS.apply_space_style(resume_btn, Color.GREEN)
	if back_btn:
		BS.apply_space_style(back_btn, Color.RED)

	if is_mobile:
		_setup_mobile()
	else:
		_setup_desktop()

	# HUD widgets — always visible on all platforms
	_setup_hud()


func _setup_mobile() -> void:
	# Hide the old TouchScreenButton nodes
	for btn_name in _touch_button_names:
		var btn = get_node_or_null(btn_name)
		if btn:
			btn.visible = false

	# Create virtual joystick (bottom-left)
	_joystick = Control.new()
	_joystick.set_script(VirtualJoystickScript)
	_joystick.name = "VirtualJoystick"
	add_child(_joystick)
	# Position: bottom-left with some padding
	# Joystick size is 140x140, place at bottom-left
	_joystick.position = Vector2(20, 430)

	# Create thrust button (right side, upper)
	_thrust_btn = Control.new()
	_thrust_btn.set_script(ThrustButtonScript)
	_thrust_btn.name = "ThrustBtn"
	_thrust_btn.set("action_name", "thrust")
	_thrust_btn.set("arrow_up", true)
	add_child(_thrust_btn)
	_thrust_btn.position = Vector2(920, 350)

	# Create reverse thrust button (right side, lower)
	_reverse_btn = Control.new()
	_reverse_btn.set_script(ThrustButtonScript)
	_reverse_btn.name = "ReverseBtn"
	_reverse_btn.set("action_name", "revthrust")
	_reverse_btn.set("arrow_up", false)
	add_child(_reverse_btn)
	_reverse_btn.position = Vector2(920, 460)

	# Fire button — only if cannon upgrade purchased (left side, above joystick)
	if globalvar.upgrades.get("cannon", 0) > 0:
		_fire_btn = Control.new()
		_fire_btn.set_script(FireButtonScript)
		_fire_btn.name = "FireBtn"
		add_child(_fire_btn)
		_fire_btn.position = Vector2(20, 340)

	# Weapon buttons — stack vertically on right side below thrust buttons
	var weapon_y := 280.0
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
		_missile_btn.position = Vector2(850, weapon_y)
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
		_laser_btn.position = Vector2(850, weapon_y)
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
		_emp_btn.position = Vector2(850, weapon_y)


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
	$popupMenu.show()

func _on_Resume_pressed():
	get_tree().paused = false
	$popupMenu.hide()

func _on_backtomenu_pressed():
	_on_Resume_pressed()
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
