extends Control

const BS = preload("res://game/gui/ButtonStyles.gd")

var _level_select_visible := false
var _level_select_container: VBoxContainer = null
var _options_popup: PanelContainer = null
var _options_diff_label: Label = null
var _lock_popup: PanelContainer = null
var _lb_popup: PanelContainer = null
var _lb_content: RichTextLabel = null
var _lb_level_label: Label = null
var _lb_level: int = 1
var _lb_board: String = "time"

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

	# Adapt layout to actual viewport size (handles ultrawide displays)
	var vp := get_viewport_rect().size
	# Center and scale background starfield to cover viewport
	if $SpaceBG.texture:
		$SpaceBG.position = Vector2(vp.x / 2.0, vp.y / 2.0)
		var tex_size: Vector2 = $SpaceBG.texture.get_size()
		var s := maxf(vp.x / tex_size.x, vp.y / tex_size.y) * 1.02
		$SpaceBG.scale = Vector2(s, s)
	# Center button array and title label horizontally
	$VButtonArray.anchor_left = 0.5
	$VButtonArray.anchor_right = 0.5
	$VButtonArray.offset_left = -240
	$VButtonArray.offset_right = 240
	$Label.anchor_left = 0.5
	$Label.anchor_right = 0.5
	$Label.offset_left = -237
	$Label.offset_right = 237
	# Moon tracks right edge
	$Moon.position.x = vp.x - 76

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
	# Update Play button to show current level
	var play_level_name: String = globalvar.LEVEL_NAMES.get(globalvar.nowlevel, "")
	$VButtonArray/PlayButton.text = "Play - Level " + str(globalvar.nowlevel) + " " + play_level_name
	BS.apply_space_style($VButtonArray/PlayButton, Color.GREEN)
	BS.apply_space_style($VButtonArray/LevelsButton, Color.ORANGE)
	BS.apply_space_style($VButtonArray/LeaderboardButton, Color(1.0, 0.85, 0.2))
	BS.apply_space_style($VButtonArray/QuitButton, Color.RED)
	_build_help_options_buttons()
	_build_level_select()
	_build_cloud_restore_button()
	_build_pgs_buttons()
	
	# Show nickname prompt on first launch
	if not globalvar.tutorial_shown:
		var timer := get_tree().create_timer(0.5)
		timer.timeout.connect(_show_first_time_nickname_prompt)
	
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





func _build_help_options_buttons() -> void:
	## Replace Help button with side-by-side Help and Options buttons
	# Remove the original HelpButton
	var help_btn_original = $VButtonArray.find_child("HelpButton", true, false)
	if help_btn_original:
		help_btn_original.queue_free()

	# Create container for Help and Options buttons side-by-side
	var button_row := HBoxContainer.new()
	button_row.name = "HelpOptionsRow"
	button_row.add_theme_constant_override("separation", 8)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	$VButtonArray.add_child(button_row)

	# Help button (half-width)
	var help_btn := Button.new()
	help_btn.name = "HelpButton"
	help_btn.text = "Help"
	help_btn.custom_minimum_size = Vector2(110, 36)
	help_btn.add_theme_font_size_override("font_size", 14)
	BS.apply_space_style(help_btn, Color.CYAN)
	help_btn.pressed.connect(_on_HelpButton_pressed)
	button_row.add_child(help_btn)

	# Options button (half-width)
	var options_btn := Button.new()
	options_btn.name = "OptionsButton"
	options_btn.text = "Options"
	options_btn.custom_minimum_size = Vector2(110, 36)
	options_btn.add_theme_font_size_override("font_size", 14)
	BS.apply_space_style(options_btn, Color(0.5, 0.8, 1.0))
	options_btn.pressed.connect(_show_options_popup)
	button_row.add_child(options_btn)


func _show_options_popup() -> void:
	if _options_popup and is_instance_valid(_options_popup):
		_options_popup.queue_free()

	_options_popup = PanelContainer.new()
	_options_popup.name = "OptionsPopup"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.1, 0.96)
	style.border_color = Color(0.5, 0.8, 1.0, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_options_popup.add_theme_stylebox_override("panel", style)
	_options_popup.z_index = 10
	add_child(_options_popup)

	_options_popup.set_anchors_preset(Control.PRESET_CENTER)
	_options_popup.offset_left = -200
	_options_popup.offset_right = 200
	_options_popup.offset_top = -220
	_options_popup.offset_bottom = 220

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_options_popup.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "⚙️ Options"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# --- Difficulty Section ---
	var diff_label := Label.new()
	diff_label.text = "Difficulty"
	diff_label.add_theme_font_size_override("font_size", 14)
	diff_label.add_theme_color_override("font_color", Color.ORANGE)
	vbox.add_child(diff_label)

	var diff_hbox := HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 8)
	var diff_name_str: String = globalvar.DIFFICULTY_NAMES.get(globalvar.difficulty, "Normal")
	_options_diff_label = Label.new()
	_options_diff_label.text = diff_name_str
	_options_diff_label.add_theme_font_size_override("font_size", 13)
	_options_diff_label.add_theme_color_override("font_color", DIFF_COLORS.get(globalvar.difficulty, Color.YELLOW))
	_options_diff_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_hbox.add_child(_options_diff_label)

	var diff_change_btn := Button.new()
	diff_change_btn.text = "Change"
	diff_change_btn.custom_minimum_size = Vector2(90, 28)
	BS.apply_space_style(diff_change_btn, Color.YELLOW)
	diff_change_btn.add_theme_font_size_override("font_size", 12)
	diff_change_btn.pressed.connect(func():
		globalvar.difficulty = (globalvar.difficulty + 1) % 3
		globalvar.save_game()
		var new_diff_name: String = globalvar.DIFFICULTY_NAMES.get(globalvar.difficulty, "Normal")
		_options_diff_label.text = new_diff_name
		_options_diff_label.add_theme_color_override("font_color", DIFF_COLORS.get(globalvar.difficulty, Color.YELLOW))
	)
	diff_hbox.add_child(diff_change_btn)
	vbox.add_child(diff_hbox)

	# --- Nickname Section ---
	var nick_label := Label.new()
	nick_label.text = "Nickname"
	nick_label.add_theme_font_size_override("font_size", 14)
	nick_label.add_theme_color_override("font_color", Color.ORANGE)
	vbox.add_child(nick_label)

	var nick_hbox := HBoxContainer.new()
	nick_hbox.add_theme_constant_override("separation", 8)
	var curr_nick_label := Label.new()
	curr_nick_label.text = globalvar.nickname
	curr_nick_label.add_theme_font_size_override("font_size", 13)
	curr_nick_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	curr_nick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick_hbox.add_child(curr_nick_label)

	var reroll_nick_btn := Button.new()
	reroll_nick_btn.text = "Generate Random Nickname"
	reroll_nick_btn.custom_minimum_size = Vector2(75, 28)
	BS.apply_space_style(reroll_nick_btn, Color(1.0, 0.7, 0.1))
	reroll_nick_btn.add_theme_font_size_override("font_size", 12)
	reroll_nick_btn.pressed.connect(func():
		globalvar.nickname = globalvar.generate_random_nickname()
		globalvar.save_game()
		curr_nick_label.text = globalvar.nickname
	)
	nick_hbox.add_child(reroll_nick_btn)

	var edit_nick_btn := Button.new()
	edit_nick_btn.text = "Edit"
	edit_nick_btn.custom_minimum_size = Vector2(75, 28)
	BS.apply_space_style(edit_nick_btn, Color(0.5, 0.8, 1.0))
	edit_nick_btn.add_theme_font_size_override("font_size", 12)
	edit_nick_btn.pressed.connect(func(): _show_nickname_edit_popup(curr_nick_label))
	nick_hbox.add_child(edit_nick_btn)
	vbox.add_child(nick_hbox)

	# Separator
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Reset Progress button
	var reset_btn := Button.new()
	reset_btn.text = "Reset Progress"
	reset_btn.custom_minimum_size = Vector2(240, 32)
	BS.apply_space_style(reset_btn, Color(1.0, 0.2, 0.2))
	reset_btn.pressed.connect(_show_reset_confirmation)
	vbox.add_child(reset_btn)

	# Close button
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 32)
	BS.apply_space_style(close, Color.RED)
	close.pressed.connect(func(): _options_popup.queue_free())
	vbox.add_child(close)


func _show_reset_confirmation() -> void:
	## Show confirmation dialog before resetting progress.
	var confirm := ConfirmationDialog.new()
	confirm.title = "Reset Progress?"
	confirm.dialog_text = "This will delete all your progress, stats, and upgrades.\n\nYou will get a new nickname and restart the tutorial.\n\nThis cannot be undone!"
	confirm.ok_button_text = "Reset"
	confirm.cancel_button_text = "Cancel"
	confirm.confirmed.connect(func():
		globalvar.reset_progress()
		if _options_popup and is_instance_valid(_options_popup):
			_options_popup.queue_free()
		_show_reset_toast()
		# Reload the menu scene so nickname prompt and tutorial check run again
		var timer := get_tree().create_timer(2.0)
		timer.timeout.connect(func():
			get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
		)
	)
	add_child(confirm)
	confirm.popup_centered()


func _show_reset_toast() -> void:
	## Show toast message that progress was reset.
	var toast := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.06, 0.04, 0.14, 0.95)
	ts.border_color = Color(1.0, 0.85, 0.2, 0.6)
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(8)
	ts.content_margin_left = 16
	ts.content_margin_right = 16
	ts.content_margin_top = 8
	ts.content_margin_bottom = 8
	toast.add_theme_stylebox_override("panel", ts)
	toast.z_index = 20
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = -120
	toast.offset_bottom = -80
	var lbl := Label.new()
	lbl.text = "Progress reset! You'll see the tutorial when you play."
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(lbl)
	add_child(toast)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)


func _show_first_time_nickname_prompt() -> void:
	## Show nickname prompt dialog on first launch.
	var dialog := AcceptDialog.new()
	dialog.title = "Welcome!"
	dialog.ok_button_text = "Start Game"
	
	var vbox := VBoxContainer.new()
	var prompt_label := Label.new()
	prompt_label.text = "Enter your pilot nickname:\n(or leave blank for a random one)"
	vbox.add_child(prompt_label)
	var line_edit := LineEdit.new()
	line_edit.max_length = 20
	line_edit.placeholder_text = "Enter nickname..."
	line_edit.custom_minimum_size = Vector2(300, 36)
	vbox.add_child(line_edit)
	
	dialog.add_child(vbox)
	dialog.move_child(vbox, 1)  # Insert after title
	
	dialog.confirmed.connect(func():
		var cleaned := line_edit.text.strip_edges().left(20)
		if cleaned != "":
			globalvar.nickname = cleaned
		globalvar.save_game()
	)
	
	add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()


func _show_nickname_edit_popup(nick_label: Label) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Edit Nickname"
	dialog.dialog_text = ""  # Clear default text
	dialog.add_cancel_button("Cancel")

	var vbox := VBoxContainer.new()

	var prompt_label := Label.new()  # Add label manually
	prompt_label.text = "Enter your new nickname:"
	vbox.add_child(prompt_label)

	var line_edit := LineEdit.new()
	line_edit.text = globalvar.nickname
	line_edit.max_length = 20
	line_edit.custom_minimum_size = Vector2(300, 32)
	vbox.add_child(line_edit)

	dialog.add_child(vbox)
	dialog.move_child(vbox, 1)

	dialog.confirmed.connect(func():
		var cleaned := line_edit.text.strip_edges().left(20)
		if cleaned == "":
			cleaned = globalvar.generate_random_nickname()
		globalvar.nickname = cleaned
		globalvar.save_game()
		nick_label.text = cleaned
	)

	add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()
	line_edit.caret_column = line_edit.text.length()


func _build_level_select() -> void:
	# Level select panel — toggled via Levels button (or D key in debug)
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
	header.text = "Select Level"
	header.add_theme_color_override("font_color", Color.ORANGE)
	header.add_theme_font_size_override("font_size", 14)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_select_container.add_child(header)

	# Level buttons — generated from globalvar.LEVEL_SCENES
	for level_num in globalvar.LEVEL_SCENES.keys():
		var btn := Button.new()
		var level_name: String = globalvar.LEVEL_NAMES.get(level_num, str(level_num))
		var reachable := globalvar.is_level_reachable(level_num)
		var best_stars: int = globalvar.get_best_stars(level_num)
		var star_str := ""
		if best_stars > 0:
			star_str = " " + "★".repeat(best_stars) + "☆".repeat(3 - best_stars)
		var prefix := "🔒 " if not reachable else ""
		btn.text = prefix + "Level " + str(level_num) + " — " + level_name + star_str
		btn.custom_minimum_size = Vector2(250, 32)
		btn.flat = true
		BS.apply_space_style(btn, Color(0.4, 0.4, 0.5) if not reachable else Color.ORANGE)
		var scene_path: String = globalvar.LEVEL_SCENES[level_num]
		var lvl_num: int = level_num
		btn.pressed.connect(func():
			if not globalvar.is_level_reachable(lvl_num):
				if not globalvar.is_level_unlocked(lvl_num):
					_show_lock_popup()
				return
			globalvar.nowlevel = lvl_num
			globalvar.get_level_scene(lvl_num)  # set endless_mode flag if needed
			WarpTransition.warp_to(scene_path)
		)
		_level_select_container.add_child(btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
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
	# Fade Moon based on level select visibility
	$Moon.modulate.a = 0.2 if _level_select_visible else 1.0

func _on_QuitButton_pressed():
	get_tree().quit()

func _on_PlayButton_pressed():
	if not globalvar.is_level_unlocked(globalvar.nowlevel):
		_show_lock_popup()
		return
	var scene := globalvar.get_level_scene(globalvar.nowlevel)
	WarpTransition.warp_to(scene)

func _on_LevelsButton_pressed():
	_toggle_level_select()

func _on_HelpButton_pressed():
	get_tree().change_scene_to_file("res://game/gui/help/Help.tscn")


func _on_LeaderboardButton_pressed():
	_show_leaderboard_popup()


# --- Leaderboard Popup ---

func _show_leaderboard_popup() -> void:
	if _lb_popup and is_instance_valid(_lb_popup):
		_lb_popup.queue_free()

	_lb_popup = PanelContainer.new()
	_lb_popup.name = "LeaderboardPopup"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.1, 0.96)
	style.border_color = Color(1.0, 0.85, 0.2, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_lb_popup.add_theme_stylebox_override("panel", style)
	_lb_popup.z_index = 10
	add_child(_lb_popup)

	_lb_popup.set_anchors_preset(Control.PRESET_CENTER)
	_lb_popup.offset_left = -240
	_lb_popup.offset_right = 240
	_lb_popup.offset_top = -200
	_lb_popup.offset_bottom = 200

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_lb_popup.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "🏆  Leaderboard"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Level selector row
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(level_row)

	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(36, 30)
	BS.apply_space_style(prev_btn, Color(0.5, 0.8, 1.0))
	prev_btn.pressed.connect(func(): _lb_change_level(-1))
	level_row.add_child(prev_btn)

	_lb_level_label = Label.new()
	_lb_level_label.name = "LBLevelLabel"
	_lb_level_label.add_theme_font_size_override("font_size", 16)
	_lb_level_label.add_theme_color_override("font_color", Color.CYAN)
	_lb_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lb_level_label.custom_minimum_size = Vector2(260, 0)
	level_row.add_child(_lb_level_label)

	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(36, 30)
	BS.apply_space_style(next_btn, Color(0.5, 0.8, 1.0))
	next_btn.pressed.connect(func(): _lb_change_level(1))
	level_row.add_child(next_btn)

	# Board type selector row
	var board_row := HBoxContainer.new()
	board_row.name = "BoardRow"
	board_row.add_theme_constant_override("separation", 6)
	board_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(board_row)
	_lb_build_board_buttons(board_row)

	# Scrollable scores content
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 260)
	vbox.add_child(scroll)

	_lb_content = RichTextLabel.new()
	_lb_content.bbcode_enabled = true
	_lb_content.fit_content = true
	_lb_content.scroll_active = false
	_lb_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lb_content.custom_minimum_size = Vector2(420, 0)
	_lb_content.add_theme_font_size_override("normal_font_size", 14)
	_lb_content.add_theme_color_override("default_color", Color(0.8, 0.85, 0.9))
	scroll.add_child(_lb_content)

	# Close button
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 34)
	BS.apply_space_style(close, Color.RED)
	close.pressed.connect(func(): _lb_popup.queue_free())
	vbox.add_child(close)

	_lb_level = globalvar.nowlevel
	_lb_board = "time"
	_lb_update_level_label()
	_lb_fetch()


func _lb_build_board_buttons(row: HBoxContainer) -> void:
	for child in row.get_children():
		child.queue_free()

	var boards: Array
	if _lb_level == 12:
		boards = [
			{"id": "wave", "label": "Waves"},
			{"id": "score", "label": "Moonrocks"},
			{"id": "time", "label": "Fastest"},
		]
	else:
		boards = [
			{"id": "time", "label": "Fastest"},
			{"id": "score", "label": "Moonrocks"},
		]

	for b in boards:
		var btn := Button.new()
		btn.text = b["label"]
		btn.custom_minimum_size = Vector2(100, 28)
		var is_active: bool = (b["id"] == _lb_board)
		var col := Color(1.0, 0.85, 0.2) if is_active else Color(0.4, 0.5, 0.6)
		BS.apply_space_style(btn, col)
		var board_id: String = b["id"]
		btn.pressed.connect(func(): _lb_switch_board(board_id))
		row.add_child(btn)


func _lb_switch_board(board: String) -> void:
	_lb_board = board
	# Rebuild board buttons to update highlight
	if _lb_popup and is_instance_valid(_lb_popup):
		var board_row = _lb_popup.find_child("BoardRow", true, false)
		if board_row:
			_lb_build_board_buttons(board_row)
	_lb_fetch()


func _lb_change_level(delta: int) -> void:
	_lb_level = clampi(_lb_level + delta, 1, globalvar.MAX_LEVEL)
	# Reset board — wave only for level 12
	if _lb_board == "wave" and _lb_level != 12:
		_lb_board = "time"
	_lb_update_level_label()
	# Rebuild board buttons for new level
	if _lb_popup and is_instance_valid(_lb_popup):
		var board_row = _lb_popup.find_child("BoardRow", true, false)
		if board_row:
			_lb_build_board_buttons(board_row)
	_lb_fetch()


func _lb_update_level_label() -> void:
	if not _lb_level_label or not is_instance_valid(_lb_level_label):
		return
	var name_str: String = globalvar.LEVEL_NAMES.get(_lb_level, str(_lb_level))
	_lb_level_label.text = "Level %d - %s" % [_lb_level, name_str]


func _lb_fetch() -> void:
	_lb_content.text = "[center]Loading...[/center]"
	ScoreClient.leaderboard_received.connect(_on_leaderboard_received, CONNECT_ONE_SHOT)
	ScoreClient.fetch_leaderboard(_lb_level, 20, _lb_board)


func _on_leaderboard_received(success: bool, scores: Array) -> void:
	if not _lb_content or not is_instance_valid(_lb_content):
		return
	if not success or scores.is_empty():
		_lb_content.text = "[center][color=gray]No scores yet for this level.[/color][/center]"
		return

	var text := ""
	if _lb_board == "wave":
		text = "[table=5]"
		text += "[cell][b]#[/b][/cell][cell][b]Pilot[/b][/cell][cell][b]Wave[/b][/cell][cell][b]Moonrocks[/b][/cell][cell][/cell]"
	elif _lb_board == "score":
		text = "[table=5]"
		text += "[cell][b]#[/b][/cell][cell][b]Pilot[/b][/cell][cell][b]Moonrocks[/b][/cell][cell][b]Time[/b][/cell][cell][/cell]"
	else:  # time
		text = "[table=5]"
		text += "[cell][b]#[/b][/cell][cell][b]Pilot[/b][/cell][cell][b]Time[/b][/cell][cell][b]Stars[/b][/cell][cell][/cell]"

	var rank := 1
	for entry in scores:
		var nick: String = str(entry.get("nickname", "???"))
		var is_me: bool = entry.get("is_self", false)
		var color := "[color=cyan]" if is_me else ""
		var end_color := "[/color]" if is_me else ""
		var plat_icon := _platform_icon(str(entry.get("platform", "")))

		if _lb_board == "wave":
			var wave_n: int = int(entry.get("wave", 0))
			var rocks: int = int(entry.get("crypto_collected", 0))
			text += "[cell]%s%d%s[/cell][cell]%s%s%s[/cell][cell]%s%d%s[/cell][cell]%s%d%s[/cell][cell]%s[/cell]" % [
				color, rank, end_color,
				color, nick.left(14), end_color,
				color, wave_n, end_color,
				color, rocks, end_color,
				plat_icon,
			]
		elif _lb_board == "score":
			var rocks: int = int(entry.get("crypto_collected", 0))
			var time_s: float = float(entry.get("completion_time", 0))
			text += "[cell]%s%d%s[/cell][cell]%s%s%s[/cell][cell]%s%d%s[/cell][cell]%s%.2fs%s[/cell][cell]%s[/cell]" % [
				color, rank, end_color,
				color, nick.left(14), end_color,
				color, rocks, end_color,
				color, time_s, end_color,
				plat_icon,
			]
		else:  # time
			var time_s: float = float(entry.get("completion_time", 0))
			var star_count: int = int(entry.get("stars", 0))
			var star_str := "★".repeat(star_count) + "☆".repeat(3 - star_count)
			text += "[cell]%s%d%s[/cell][cell]%s%s%s[/cell][cell]%s%.2fs%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [
				color, rank, end_color,
				color, nick.left(14), end_color,
				color, time_s, end_color,
				star_str,
				plat_icon,
			]
		rank += 1
	text += "[/table]"
	_lb_content.text = text


static func _platform_icon(platform: String) -> String:
	match platform.to_upper():
		"ANDROID": return "[color=lime]A[/color]"
		"IOS": return "[color=white]i[/color]"
		"WEB": return "[color=orange]W[/color]"
		"MACOS": return "[color=silver]M[/color]"
		"WINDOWS": return "[color=dodgerblue]P[/color]"
		"LINUX": return "[color=yellow]L[/color]"
	return ""


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
	_lock_popup.z_index = 10
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

func _build_pgs_buttons() -> void:
	## Add platform achievements button (Android: PGS, iOS: Game Center).
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		return
	var ach_btn := Button.new()
	ach_btn.name = "AchievementsButton"
	ach_btn.text = "Achievements"
	ach_btn.custom_minimum_size = Vector2(480, 52)
	BS.apply_space_style(ach_btn, Color(0.4, 0.85, 0.4))
	ach_btn.add_theme_font_size_override("font_size", 25)
	if OS.get_name() == "Android":
		ach_btn.pressed.connect(func():
			if PlayGamesManager.is_available():
				PlayGamesManager.show_achievements()
			else:
				PlayGamesManager.try_sign_in()
				_show_toast("Signing in to Google Play Games...")
		)
	else:
		ach_btn.pressed.connect(func():
			if GameCenterManager.is_available():
				GameCenterManager.show_achievements()
			else:
				_show_toast("Sign in to Game Center in Settings to view achievements")
		)
	# Insert before Quit button
	$VButtonArray.add_child(ach_btn)
	$VButtonArray.move_child(ach_btn, $VButtonArray/QuitButton.get_index())


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


func _show_toast(msg: String) -> void:
	var toast := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.06, 0.04, 0.14, 0.95)
	ts.border_color = Color(1.0, 0.85, 0.2, 0.6)
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(8)
	ts.content_margin_left = 16
	ts.content_margin_right = 16
	ts.content_margin_top = 8
	ts.content_margin_bottom = 8
	toast.add_theme_stylebox_override("panel", ts)
	toast.z_index = 20
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = -120
	toast.offset_bottom = -80
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(lbl)
	add_child(toast)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)
