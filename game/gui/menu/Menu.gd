extends Control

const BS = preload("res://game/gui/ButtonStyles.gd")

var _level_select_visible := false
var _level_select_container: VBoxContainer = null
var _nick_label: Label = null
var _nick_edit: LineEdit = null
var _editing_nick := false
var _diff_btn: Button = null
var _lock_popup: PanelContainer = null

# Title screen background animation
var _bg_planets: Array[Dictionary] = []  # {sprite, center, radius, angle, speed}
var _bg_ships: Array[Dictionary] = []    # {sprite, velocity, alive}
var _ship_spawn_timer: float = 0.0
var _bg_action_delay: float = 0.0  # seconds before bg planets/ships start

const PLANET_TEXTURES := [
	"res://art/planets/mars.png",
	"res://art/planets/venus.png",
	"res://art/planets/jupiter.png",
	"res://art/planets/saturn.png",
	"res://art/planets/neptune.png",
	"res://art/planets/pluto.png",
	"res://art/planets/io.png",
]

const SHIP_TEXTURES := [
	"res://art/ship/skins/retro.png",
	"res://art/ship/skins/stealth.png",
	"res://art/ship/skins/gold.png",
	"res://art/ship/skins/alien.png",
	"res://art/ship/skins/wownero.png",
	"res://art/ship/skins/monero.png",
	"res://art/ship/skins/bitcoin.png",
	"res://art/ship/skins/litecoin.png",
	"res://art/ship/skins/alien_prem.png",
	"res://art/ship/skins/gold_prem.png",
	"res://art/ship/skins/retro_prem.png",
	"res://art/ship/skins/stealth_prem.png",
]

const DIFF_COLORS := {
	0: Color(0.3, 0.9, 0.4),  # Easy — green
	1: Color(1.0, 0.7, 0.1),  # Normal — gold
	2: Color(1.0, 0.25, 0.2), # Hard — red
}

func _ready():
	$RocketSprite/AnimationPlayer.play("move")
	globalvar.load_game()
	# Randomize Earth texture
	var earth_textures := [
		"res://art/planets/earth_real_1.png",
		"res://art/planets/earth_real_2.png",
		"res://art/planets/earth_real_3.png",
	]
	var earth_tex := load(earth_textures[randi() % earth_textures.size()])
	if earth_tex:
		$Earth.texture = earth_tex
	# Style menu buttons
	BS.apply_space_style($VButtonArray/PlayButton, Color.GREEN)
	BS.apply_space_style($VButtonArray/HelpButton, Color.CYAN)
	BS.apply_space_style($VButtonArray/QuitButton, Color.RED)
	_build_nickname_bar()
	_build_level_select()
	_build_difficulty_toggle()
	_build_cloud_restore_button()
	_bg_action_delay = randf_range(5.0, 7.0)
	AdManager.show_banner()


# --- Background Animation ---

func _build_bg_planets() -> void:
	## Add small orbiting planets — they drift in slowly from screen edges.
	var vp := get_viewport_rect().size
	# Exclusion zones around Earth and Moon so bg planets don't overlap them
	var exclusions: Array[Dictionary] = []
	if has_node("Earth"):
		var e := $Earth as Sprite2D
		exclusions.append({"pos": e.position, "r": e.texture.get_width() * e.scale.x * 0.55 + 40.0})
	if has_node("Moon"):
		var m := $Moon as Sprite2D
		exclusions.append({"pos": m.position, "r": m.texture.get_width() * m.scale.x * 0.55 + 30.0})
	var available := PLANET_TEXTURES.duplicate()
	available.shuffle()
	var count := mini(available.size(), randi_range(3, 4))
	for i in count:
		var tex := load(available[i])
		if not tex:
			continue
		var spr := Sprite2D.new()
		spr.texture = tex
		var s := randf_range(0.06, 0.14)
		spr.scale = Vector2(s, s)
		spr.modulate = Color(1, 1, 1, 0.0)  # start invisible
		spr.z_index = 1
		add_child(spr)
		# Pick orbit center that avoids Earth/Moon
		var orbit_center := _pick_clear_position(vp, exclusions)
		var orbit_radius := randf_range(30, 90)
		var orbit_speed := randf_range(0.08, 0.22) * (1.0 if randf() > 0.5 else -1.0)
		var start_angle := randf_range(0, TAU)
		var target_pos := orbit_center + Vector2(cos(start_angle), sin(start_angle)) * orbit_radius
		var spawn_pos := _nearest_edge_pos(target_pos, vp, s * 500.0)
		spr.position = spawn_pos
		_bg_planets.append({
			"sprite": spr,
			"center": orbit_center,
			"radius": orbit_radius,
			"angle": start_angle,
			"speed": orbit_speed,
			"visual_radius": s * 400.0,
			"target_pos": target_pos,
			"target_alpha": randf_range(0.3, 0.55),
			"entering": true,
			"drift_speed": randf_range(15.0, 25.0),
		})


func _nearest_edge_pos(target: Vector2, vp: Vector2, margin: float) -> Vector2:
	## Return a position just off the nearest screen edge from `target`.
	var dist_left := target.x
	var dist_right := vp.x - target.x
	var dist_top := target.y
	var dist_bottom := vp.y - target.y
	var min_dist := minf(minf(dist_left, dist_right), minf(dist_top, dist_bottom))
	if min_dist == dist_left:
		return Vector2(-margin, target.y)
	elif min_dist == dist_right:
		return Vector2(vp.x + margin, target.y)
	elif min_dist == dist_top:
		return Vector2(target.x, -margin)
	else:
		return Vector2(target.x, vp.y + margin)


func _pick_clear_position(vp: Vector2, exclusions: Array[Dictionary]) -> Vector2:
	## Pick a random position that doesn't overlap any exclusion zone.
	for _attempt in 20:
		var pos := Vector2(randf_range(100, vp.x - 100), randf_range(80, vp.y - 80))
		var clear := true
		for ex in exclusions:
			if pos.distance_to(ex["pos"]) < ex["r"]:
				clear = false
				break
		if clear:
			return pos
	# Fallback: top-center area (always far from bottom-left Earth and right Moon)
	return Vector2(randf_range(300, 700), randf_range(60, 180))


func _spawn_bg_ship() -> void:
	## Spawn a small ship that flies across the screen in a random direction.
	var vp := get_viewport_rect().size
	var tex := load(SHIP_TEXTURES[randi() % SHIP_TEXTURES.size()])
	if not tex:
		return
	var spr := Sprite2D.new()
	spr.texture = tex
	var s := randf_range(0.15, 0.3)
	spr.scale = Vector2(s, s)
	spr.modulate = Color(1, 1, 1, randf_range(0.5, 0.8))
	spr.z_index = 2
	add_child(spr)

	# Pick a random edge to spawn from and direction
	var side := randi() % 4
	var pos := Vector2.ZERO
	var angle := 0.0
	match side:
		0:  # left
			pos = Vector2(-30, randf_range(50, vp.y - 50))
			angle = randf_range(-0.6, 0.6)
		1:  # right
			pos = Vector2(vp.x + 30, randf_range(50, vp.y - 50))
			angle = randf_range(PI - 0.6, PI + 0.6)
		2:  # top
			pos = Vector2(randf_range(50, vp.x - 50), -30)
			angle = randf_range(0.5, PI - 0.5)
		3:  # bottom
			pos = Vector2(randf_range(50, vp.x - 50), vp.y + 30)
			angle = randf_range(-PI + 0.5, -0.5)

	spr.position = pos
	spr.rotation = angle + PI / 2.0  # nose points in travel direction
	var speed := randf_range(20, 50)
	var vel := Vector2(cos(angle), sin(angle)) * speed

	_bg_ships.append({
		"sprite": spr,
		"velocity": vel,
		"alive": true,
	})


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size

	# Wait for startup delay before spawning anything
	if _bg_action_delay > 0.0:
		_bg_action_delay -= delta
		if _bg_action_delay <= 0.0:
			_build_bg_planets()
			_ship_spawn_timer = randf_range(1.0, 2.5)
		return

	# Update orbiting planets
	for p in _bg_planets:
		var spr: Sprite2D = p["sprite"]
		if not is_instance_valid(spr):
			continue
		if p["entering"]:
			# Slowly drift toward target position
			var target: Vector2 = p["target_pos"]
			var diff := target - spr.position
			var dist := diff.length()
			if dist < 2.0:
				# Arrived — switch to orbiting
				spr.position = target
				spr.modulate.a = p["target_alpha"]
				p["entering"] = false
			else:
				spr.position += diff.normalized() * p["drift_speed"] * delta
				spr.modulate.a = minf(spr.modulate.a + delta * 0.08, p["target_alpha"])
		else:
			p["angle"] += p["speed"] * delta
			spr.position = p["center"] + Vector2(cos(p["angle"]), sin(p["angle"])) * p["radius"]
		# Slow self-rotation always
		spr.rotation += p.get("speed", 0.1) * 0.15 * delta

	# Spawn ships periodically
	_ship_spawn_timer -= delta
	if _ship_spawn_timer <= 0.0:
		_spawn_bg_ship()
		_ship_spawn_timer = randf_range(2.5, 5.0)

	# Update ships + check collisions with planets
	var margin := 60.0
	var ships_to_remove: Array[int] = []
	for i in _bg_ships.size():
		var ship: Dictionary = _bg_ships[i]
		if not ship["alive"]:
			ships_to_remove.append(i)
			continue
		var spr: Sprite2D = ship["sprite"]
		if not is_instance_valid(spr):
			ship["alive"] = false
			ships_to_remove.append(i)
			continue
		spr.position += ship["velocity"] * delta

		# Off-screen cleanup
		if spr.position.x < -margin or spr.position.x > vp.x + margin \
			or spr.position.y < -margin or spr.position.y > vp.y + margin:
			spr.queue_free()
			ship["alive"] = false
			ships_to_remove.append(i)
			continue

		# Check collision with background planets
		for p in _bg_planets:
			var planet_spr: Sprite2D = p["sprite"]
			if not is_instance_valid(planet_spr):
				continue
			var dist := spr.position.distance_to(planet_spr.position)
			var hit_radius: float = p["visual_radius"] + 4.0
			if dist < hit_radius:
				_explode_ship(spr.position, spr.scale.x)
				spr.queue_free()
				ship["alive"] = false
				ships_to_remove.append(i)
				break

		# Also check collision with scene Earth and Moon
		if ship["alive"] and is_instance_valid(spr):
			for body_name in ["Earth", "Moon"]:
				if not has_node(body_name):
					continue
				var body: Sprite2D = get_node(body_name)
				var body_radius: float = body.texture.get_width() * body.scale.x * 0.4
				if spr.position.distance_to(body.position) < body_radius:
					_explode_ship(spr.position, spr.scale.x)
					spr.queue_free()
					ship["alive"] = false
					break

	# Remove dead ships (reverse order)
	ships_to_remove.sort()
	for idx in range(ships_to_remove.size() - 1, -1, -1):
		_bg_ships.remove_at(ships_to_remove[idx])


func _explode_ship(pos: Vector2, ship_scale: float) -> void:
	## Quick particle burst at position — ship hit a planet.
	var particles := GPUParticles2D.new()
	particles.position = pos
	particles.z_index = 3
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 12
	particles.lifetime = 0.6
	particles.explosiveness = 1.0

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 100.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = ship_scale * 1.5
	mat.scale_max = ship_scale * 3.0
	mat.damping_min = 30.0
	mat.damping_max = 50.0
	# Orange-red-yellow fire gradient
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1.0, 0.9, 0.3, 1.0),
		Color(1.0, 0.4, 0.1, 0.8),
		Color(0.6, 0.1, 0.0, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	mat.color_ramp = grad_tex
	particles.process_material = mat

	# Use a simple circle texture
	var circle_tex := load("res://art/effects/glowingCircle.png")
	if circle_tex:
		particles.texture = circle_tex

	add_child(particles)
	# Auto-remove after particles finish
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(particles.queue_free)


func _build_nickname_bar() -> void:
	## Nickname bar at bottom-left: "Pilot: NickName  [🎲] [✏️]"
	# Dark panel behind the bar so it's readable over any background
	var panel := PanelContainer.new()
	panel.name = "NicknamePanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(4, -56)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.02, 0.08, 0.85)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var bar := HBoxContainer.new()
	bar.name = "NicknameBar"
	bar.add_theme_constant_override("separation", 10)
	panel.add_child(bar)

	var pilot_label := Label.new()
	pilot_label.text = "Pilot:"
	pilot_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	pilot_label.add_theme_font_size_override("font_size", 18)
	bar.add_child(pilot_label)

	_nick_label = Label.new()
	_nick_label.name = "NickLabel"
	_nick_label.text = globalvar.nickname
	_nick_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_nick_label.add_theme_font_size_override("font_size", 18)
	bar.add_child(_nick_label)

	# Dice button — reroll random name
	var dice_btn := Button.new()
	dice_btn.text = "Reroll"
	dice_btn.custom_minimum_size = Vector2(80, 32)
	BS.apply_space_style(dice_btn, Color(1.0, 0.7, 0.1))
	dice_btn.add_theme_font_size_override("font_size", 15)
	dice_btn.pressed.connect(_on_reroll_nickname)
	bar.add_child(dice_btn)

	# Edit button — toggle inline text edit
	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.custom_minimum_size = Vector2(65, 32)
	BS.apply_space_style(edit_btn, Color(0.5, 0.8, 1.0))
	edit_btn.add_theme_font_size_override("font_size", 15)
	edit_btn.pressed.connect(_on_edit_nickname)
	bar.add_child(edit_btn)

	# Hidden LineEdit for custom entry
	_nick_edit = LineEdit.new()
	_nick_edit.name = "NickEdit"
	_nick_edit.visible = false
	_nick_edit.custom_minimum_size = Vector2(180, 32)
	_nick_edit.max_length = 20
	_nick_edit.placeholder_text = "Enter nickname..."
	_nick_edit.text = globalvar.nickname
	_nick_edit.add_theme_font_size_override("font_size", 16)
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


func _build_difficulty_toggle() -> void:
	_diff_btn = Button.new()
	_diff_btn.name = "DifficultyButton"
	_diff_btn.custom_minimum_size = Vector2(180, 36)
	_diff_btn.add_theme_font_size_override("font_size", 14)
	_update_difficulty_button()
	_diff_btn.pressed.connect(_on_difficulty_pressed)
	# Place below main buttons
	$VButtonArray.add_child(_diff_btn)


func _update_difficulty_button() -> void:
	var name_str: String = globalvar.DIFFICULTY_NAMES.get(globalvar.difficulty, "Normal")
	_diff_btn.text = "Difficulty: " + name_str
	var color: Color = DIFF_COLORS.get(globalvar.difficulty, Color.YELLOW)
	BS.apply_space_style(_diff_btn, color)


func _on_difficulty_pressed() -> void:
	globalvar.difficulty = (globalvar.difficulty + 1) % 3
	globalvar.save_game()
	_update_difficulty_button()


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
		var locked := not globalvar.is_level_unlocked(level_num)
		var prefix := "🔒 " if locked else ""
		btn.text = prefix + "Level " + str(level_num) + " — " + level_name
		btn.custom_minimum_size = Vector2(250, 32)
		btn.flat = true
		BS.apply_space_style(btn, Color(0.4, 0.4, 0.5) if locked else Color.ORANGE)
		var scene_path: String = globalvar.LEVEL_SCENES[level_num]
		var lvl_num: int = level_num
		btn.pressed.connect(func():
			if not globalvar.is_level_unlocked(lvl_num):
				_show_lock_popup()
				return
			globalvar.get_level_scene(lvl_num)  # set endless_mode flag if needed
			WarpTransition.warp_to(scene_path)
		)
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
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_D:
				_toggle_level_select()
				get_viewport().set_input_as_handled()
			KEY_M:
				# Debug: add 500 Moonrocks
				globalvar.add_crypto(500)
				_show_debug_toast("+500 Moonrocks (debug)")
				get_viewport().set_input_as_handled()
			KEY_U:
				# Debug: unlock all levels
				globalvar.unlock_all_levels()
				_show_debug_toast("All levels unlocked (debug)")
				get_viewport().set_input_as_handled()


func _show_debug_toast(msg: String) -> void:
	var toast := Label.new()
	toast.text = msg
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toast.offset_top = -80
	toast.offset_bottom = -60
	add_child(toast)
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 0.0, 1.5).set_delay(1.0)
	tw.tween_callback(toast.queue_free)


func _toggle_level_select() -> void:
	_level_select_visible = !_level_select_visible
	var panel: PanelContainer = get_node("LevelSelectPanel")
	panel.visible = _level_select_visible

func _on_QuitButton_pressed():
	get_tree().quit()

func _on_PlayButton_pressed():
	if not globalvar.is_level_unlocked(globalvar.nowlevel):
		_show_lock_popup()
		return
	var scene := globalvar.get_level_scene(globalvar.nowlevel)
	WarpTransition.warp_to(scene)

func _on_HelpButton_pressed():
	get_tree().change_scene_to_file("res://game/gui/help/Help.tscn")


# --- Level Pack Lock Popup ---

func _show_lock_popup() -> void:
	if _lock_popup and is_instance_valid(_lock_popup):
		_lock_popup.queue_free()

	_lock_popup = PanelContainer.new()
	_lock_popup.name = "LockPopup"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.12, 0.95)
	style.border_color = Color(1.0, 0.85, 0.2, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(1.0, 0.85, 0.2, 0.2)
	style.shadow_size = 10
	_lock_popup.add_theme_stylebox_override("panel", style)
	add_child(_lock_popup)

	# Center it
	_lock_popup.set_anchors_preset(Control.PRESET_CENTER)
	_lock_popup.offset_left = -180
	_lock_popup.offset_right = 180
	_lock_popup.offset_top = -100
	_lock_popup.offset_bottom = 100

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_lock_popup.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Levels 5+ Locked"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Progress info
	var progress := globalvar.total_crypto_earned
	var target := globalvar.LEVEL_PACK_GRIND_COST
	var pct := mini(int(float(progress) * 100.0 / float(target)), 100)
	var info := Label.new()
	info.text = "Earn %d Moonrocks to unlock.\nProgress: %d / %d (%d%%)" % [target, progress, target, pct]
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(info)

	# Progress bar
	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(280, 12)
	bar_bg.color = Color(0.15, 0.15, 0.25)
	vbox.add_child(bar_bg)
	var bar_fill := ColorRect.new()
	bar_fill.custom_minimum_size = Vector2(280.0 * pct / 100.0, 12)
	bar_fill.color = Color(1.0, 0.85, 0.2, 0.9)
	bar_bg.add_child(bar_fill)

	# Close button
	var close := Button.new()
	close.text = "OK"
	close.custom_minimum_size = Vector2(100, 32)
	close.add_theme_font_size_override("font_size", 16)
	BS.apply_space_style(close, Color.CYAN)
	close.pressed.connect(func(): _lock_popup.queue_free())
	vbox.add_child(close)


# --- Cloud Restore Button ---

func _build_cloud_restore_button() -> void:
	var bar := HBoxContainer.new()
	bar.name = "CloudBar"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.position = Vector2(-170, -44)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)

	var restore_btn := Button.new()
	restore_btn.text = "Restore Cloud Save"
	restore_btn.custom_minimum_size = Vector2(160, 28)
	BS.apply_space_style(restore_btn, Color(0.4, 0.7, 1.0))
	restore_btn.add_theme_font_size_override("font_size", 12)
	restore_btn.pressed.connect(_on_cloud_restore_pressed)
	bar.add_child(restore_btn)


func _on_cloud_restore_pressed() -> void:
	# Show confirmation dialog
	var popup := AcceptDialog.new()
	popup.title = "Restore from Cloud?"
	popup.dialog_text = "This will download your cloud save.\nLocal progress will be kept if it's further ahead."
	popup.ok_button_text = "Restore"
	popup.add_cancel_button("Cancel")
	popup.confirmed.connect(func():
		globalvar.restore_from_cloud()
		# Refresh the menu after a brief delay for download
		var timer := get_tree().create_timer(2.0)
		timer.timeout.connect(func():
			get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
		)
	)
	add_child(popup)
	popup.popup_centered()
