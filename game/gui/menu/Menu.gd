extends Control

const BS = preload("res://game/gui/ButtonStyles.gd")
const MENU_FONT := preload("res://fonts/Computer Speak v0.3.ttf")

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
	globalvar.load_game()

	# No AdMob banner on the dense mobile title screen — the bottom button row
	# sat too close to it (AdMob accidental-click policy risk); banners run on
	# the Upgrade Shop instead. The WEB build's bottom bar is a harmless itch
	# self-promo nag (no ad network, no policy), so keep it on web. Hiding on
	# mobile also clears any banner left showing when returning from the shop.
	if OS.get_name() == "Web":
		AdManager.show_banner()
	else:
		AdManager.hide_banner()

	# Adapt layout to actual viewport size (handles ultrawide displays)
	var vp := get_viewport_rect().size

	# Rebake the title-screen rocket flyover animation so it actually flies
	# OFF the right edge on wide viewports. The .tscn animation tweens to
	# x=1300 (just past 1024-wide design viewport), but on a 2400-wide phone
	# x=1300 is middle-right of the screen — the rocket sat there visibly for
	# 3 seconds (the gap between the last keyframe at t=11 and the loop at t=14)
	# before snapping back to the left.
	_adapt_rocket_animation(vp)
	$RocketSprite/AnimationPlayer.play("move")
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
	$Label.offset_left = -260
	$Label.offset_right = 260
	# Subtle pulsing glow on the title — alternates the shadow outline size.
	# (Reads "shadow_outline_size" from the .tscn theme override and modulates it.)
	var glow_tween := create_tween().set_loops()
	glow_tween.tween_method(_set_title_glow, 6, 14, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glow_tween.tween_method(_set_title_glow, 14, 6, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
	# Race mode is transient — clear it on entering the menu; the Race button re-arms it.
	globalvar.race_mode = false
	# Race is always available (it always races Level 1 — the only level the CPU
	# reliably lands in race time for now), shown right under Play.
	var race_btn := Button.new()
	race_btn.name = "RaceButton"
	race_btn.text = "🏁 Race the CPU"
	BS.apply_space_style(race_btn, Color(1.0, 0.5, 0.5))
	race_btn.pressed.connect(_on_race_pressed)
	$VButtonArray.add_child(race_btn)
	$VButtonArray.move_child(race_btn, $VButtonArray/PlayButton.get_index() + 1)
	_build_help_options_buttons()
	_build_level_select()
	_build_cloud_restore_button()
	_build_pgs_buttons()
	_layout_menu()
	get_viewport().size_changed.connect(_fit_menu_buttons)

	# Show nickname prompt on first launch only (independent of Level 1 tutorial)
	if not globalvar.welcome_shown:
		var timer := get_tree().create_timer(0.5)
		timer.timeout.connect(_show_first_time_nickname_prompt)
	
	_bg_action_delay = randf_range(5.0, 7.0)
	# NOTE: banner visibility for the title screen is decided ONCE near the top
	# of _ready (web => show the itch nag, mobile => hide the AdMob banner).
	# Do NOT call show_banner() here — a leftover unconditional call here was
	# re-showing the AdMob banner over the menu buttons on mobile (it only
	# looked "gone" on Android because real ads no-filled; iOS test ads always
	# filled, so it stayed visible and blocked the bottom buttons).


func _set_title_glow(size: int) -> void:
	if has_node("Label"):
		$Label.add_theme_constant_override("shadow_outline_size", size)


func _is_mobile_ui() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "iOS"


func _layout_menu() -> void:
	## Group the menu into rows that use the horizontal space and fit any viewport
	## (phone/tablet/desktop). Done once on load; _fit_menu_buttons() re-sizes the
	## rows on every resize/rotation. Final shape:
	##   [ PLAY ]            (full width)
	##   [ Race the CPU ]    (full width)
	##   [ Levels | Leaderboard | Achievements(mobile) ]
	##   [ Help | Options | Store(mobile/web) | Quit(desktop) ]
	if not has_node("VButtonArray"):
		return
	var arr: VBoxContainer = $VButtonArray
	var mobile := _is_mobile_ui()
	var utility := arr.get_node_or_null("HelpOptionsRow")  # HBox: Help/Options/Store
	var quit := arr.get_node_or_null("QuitButton")

	# Quit is meaningless on mobile (the OS owns the app lifecycle) — drop it there;
	# on desktop fold it into the utility row so it isn't a lonely full-width button.
	if quit:
		if mobile:
			quit.queue_free()
		elif utility:
			arr.remove_child(quit)
			utility.add_child(quit)

	# Secondary row: Levels | Leaderboard | Achievements(mobile).
	var secondary := HBoxContainer.new()
	secondary.name = "SecondaryRow"
	secondary.alignment = BoxContainer.ALIGNMENT_CENTER
	secondary.add_theme_constant_override("separation", 8)
	for bn in ["LevelsButton", "LeaderboardButton", "AchievementsButton"]:
		var b := arr.get_node_or_null(bn)
		if b:
			arr.remove_child(b)
			secondary.add_child(b)
	arr.add_child(secondary)

	# Order: Play, Race, Secondary, Utility.
	var idx := 0
	for n in [arr.get_node_or_null("PlayButton"), arr.get_node_or_null("RaceButton"), secondary, utility]:
		if n and n.get_parent() == arr:
			arr.move_child(n, idx)
			idx += 1

	_fit_menu_buttons()


func _menu_font_size(h: float, in_row: bool) -> int:
	if in_row:
		return 16 if h >= 36.0 else 13
	if h < 38.0:
		return 18
	elif h < 46.0:
		return 22
	return 26


func _fit_menu_buttons() -> void:
	## Size the rows to fit ANY viewport (phone/tablet/desktop) and give every button
	## the .tscn pixel font (code-built buttons were missing it). Full-width buttons
	## (Play/Race) take the design width; grouped-row buttons share their row.
	if not has_node("VButtonArray"):
		return
	var arr: VBoxContainer = $VButtonArray
	var rows := arr.get_child_count()
	if rows == 0:
		return
	var vp := get_viewport_rect().size
	var top := 120.0
	# Cap the button band so a very tall (portrait) viewport doesn't strand the
	# centered button block in the dead middle with a huge title->buttons gap. At the
	# 600 landscape base this cap never bites (588 < 660), so landscape is unchanged.
	var bottom := minf(vp.y - 12.0, top + 540.0)
	var band := maxf(bottom - top, 120.0)
	var sep := 10
	# Row height that fits every row in the band, capped so buttons don't balloon
	# on tall tablet/desktop viewports.
	var row_h := clampf((band - float(sep) * float(rows - 1)) / float(rows), 30.0, 56.0)
	arr.add_theme_constant_override("separation", sep)
	arr.alignment = BoxContainer.ALIGNMENT_CENTER
	arr.anchor_left = 0.5
	arr.anchor_right = 0.5
	arr.offset_left = -255
	arr.offset_right = 255
	arr.offset_top = top
	arr.offset_bottom = bottom
	for c in arr.get_children():
		if c is Button:
			c.custom_minimum_size = Vector2(510, row_h)
			c.add_theme_font_override("font", MENU_FONT)
			c.add_theme_font_size_override("font_size", _menu_font_size(row_h, false))
		elif c is HBoxContainer:
			var rh := minf(row_h, 46.0)
			for sub in c.get_children():
				if sub is Button:
					sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					sub.custom_minimum_size = Vector2(0, rh)
					sub.add_theme_font_override("font", MENU_FONT)
					sub.add_theme_font_size_override("font_size", _menu_font_size(rh, true))

	# Keep the button block in front of the décor planets, and push Earth toward
	# the corner on narrow (tablet) viewports so it never covers the left buttons.
	arr.z_index = 5
	if has_node("Earth") and $Earth.texture:
		var e: Sprite2D = $Earth
		var ehw := e.texture.get_width() * e.scale.x * 0.5
		e.position.x = minf(124.0, (vp.x / 2.0 - 255.0) - 22.0 - ehw)
		e.position.y = vp.y * (462.0 / 600.0)  # proportional: spread down in tall portrait, unchanged at the 600 base
	if has_node("Moon"):
		# Moon tracks the right edge + proportional height (x is also set once in
		# _ready; doing both here re-lays it out on an orientation flip).
		$Moon.position = Vector2(vp.x - 76.0, vp.y * (374.0 / 600.0))


func _adapt_rocket_animation(vp: Vector2) -> void:
	## Patch the .tscn-baked "move" animation so the title rocket actually
	## flies off the right edge on phones (wide viewports). Updates both
	## the entry position (just off left edge) and the exit position (just
	## off right edge) to viewport-relative pixels.
	var ap: AnimationPlayer = $RocketSprite/AnimationPlayer
	var lib_names := ap.get_animation_library_list()
	if lib_names.is_empty():
		return
	var lib := ap.get_animation_library(lib_names[0])
	if not lib or not lib.has_animation("move"):
		return
	var anim: Animation = lib.get_animation("move")
	# Find the position track (path ".:position")
	for i in anim.get_track_count():
		if anim.track_get_path(i) != NodePath(".:position"):
			continue
		if anim.track_get_key_count(i) < 2:
			continue
		# Proportional height so the flyover isn't stuck in the top strip of a tall
		# portrait viewport (design y was 519 at the 600 base).
		var y_pos: float = vp.y * (519.0 / 600.0)
		# Off-screen left at start, off-screen right at the end keyframe.
		anim.track_set_key_value(i, 0, Vector2(-200.0, y_pos))
		anim.track_set_key_value(i, 1, Vector2(vp.x + 200.0, y_pos))
		break


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
	var speed := randf_range(45, 80)
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

		# Off-screen cleanup. Margin scales with ship size so larger / faster
		# ships don't appear to "stick" at the edge before disappearing.
		# (Original 60px margin was too tight for wider-than-design viewports
		# on phones — ships looked stuck at the edge for several seconds.)
		var ship_w: float = 0.0
		if spr.texture:
			ship_w = spr.texture.get_width() * spr.scale.x
		var margin: float = maxf(400.0, ship_w * 2.0)
		if spr.position.x < -margin or spr.position.x > vp.x + margin \
			or spr.position.y < -margin or spr.position.y > vp.y + margin:
			spr.queue_free()
			ship["alive"] = false
			ships_to_remove.append(i)
			continue

		# Note: previously we'd explode the ship if it collided with a
		# bg planet or Earth/Moon. Removed — the explosion particles
		# linger ~1s after the kill, which on a busy menu looks like the
		# ship is "stuck" at the edge before disappearing. Letting ships
		# pass through planets reads as if they're flying behind them and
		# is visually cleaner.

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
	## Replace Help button with side-by-side Help / Options / Store buttons
	# Remove the original HelpButton
	var help_btn_original = $VButtonArray.find_child("HelpButton", true, false)
	if help_btn_original:
		help_btn_original.queue_free()

	# Create container for Help, Options, and Store buttons side-by-side
	var button_row := HBoxContainer.new()
	button_row.name = "HelpOptionsRow"
	button_row.add_theme_constant_override("separation", 8)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	$VButtonArray.add_child(button_row)

	var btn_size := Vector2(74, 36)

	# Help button
	var help_btn := Button.new()
	help_btn.name = "HelpButton"
	help_btn.text = "Help"
	help_btn.custom_minimum_size = btn_size
	help_btn.add_theme_font_size_override("font_size", 14)
	BS.apply_space_style(help_btn, Color.CYAN)
	help_btn.pressed.connect(_on_HelpButton_pressed)
	button_row.add_child(help_btn)

	# Options button
	var options_btn := Button.new()
	options_btn.name = "OptionsButton"
	options_btn.text = "Options"
	options_btn.custom_minimum_size = btn_size
	options_btn.add_theme_font_size_override("font_size", 14)
	BS.apply_space_style(options_btn, Color(0.5, 0.8, 1.0))
	options_btn.pressed.connect(_show_options_popup)
	button_row.add_child(options_btn)

	# Store button — opens IAP popup. Hidden on desktop where there's no
	# IAP layer AND the game is already ad-free (nothing to sell).
	if _store_should_show():
		var store_btn := Button.new()
		store_btn.name = "StoreButton"
		store_btn.text = "Store"
		store_btn.custom_minimum_size = btn_size
		store_btn.add_theme_font_size_override("font_size", 14)
		BS.apply_space_style(store_btn, Color(1.0, 0.85, 0.2))
		store_btn.pressed.connect(_show_store_popup)
		button_row.add_child(store_btn)


func _store_should_show() -> bool:
	## Show the Store on mobile + web. Hide on desktop (ad-free, no IAP).
	## Always show in screenshot-debug mode so we can capture the popup.
	if IAPManager.DEBUG_FAKE_IAP_FOR_SCREENSHOTS and OS.is_debug_build():
		return true
	if _is_mobile_ui():
		return true
	return OS.get_name() == "Web"


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
	_options_popup.offset_left = -210
	_options_popup.offset_right = 210
	_options_popup.offset_top = -250
	_options_popup.offset_bottom = 250

	# Scroll the content so the expanded control/audio rows never overflow the
	# panel on shorter viewports (WP-A3 adds several rows).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_options_popup.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

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

	# --- Control scheme (mobile only) ---
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		var ctrl_label := Label.new()
		ctrl_label.text = "Controls"
		ctrl_label.add_theme_font_size_override("font_size", 14)
		ctrl_label.add_theme_color_override("font_color", Color.ORANGE)
		vbox.add_child(ctrl_label)

		var ctrl_hbox := HBoxContainer.new()
		ctrl_hbox.add_theme_constant_override("separation", 8)
		var ctrl_value := Label.new()
		ctrl_value.text = globalvar.CONTROL_SCHEME_NAMES.get(globalvar.control_scheme, "Tilt")
		ctrl_value.add_theme_font_size_override("font_size", 13)
		ctrl_value.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		ctrl_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl_hbox.add_child(ctrl_value)

		var ctrl_btn := Button.new()
		ctrl_btn.text = "Change"
		ctrl_btn.custom_minimum_size = Vector2(90, 28)
		BS.apply_space_style(ctrl_btn, Color(0.5, 0.8, 1.0))
		ctrl_btn.add_theme_font_size_override("font_size", 12)
		ctrl_hbox.add_child(ctrl_btn)
		vbox.add_child(ctrl_hbox)

		var ctrl_hint := Label.new()
		ctrl_hint.text = "Tilt: roll to turn, button to thrust.  Joystick: on-screen stick.  Full Tilt: portrait — roll to turn, pitch to thrust, no buttons."
		ctrl_hint.add_theme_font_size_override("font_size", 11)
		ctrl_hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
		ctrl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		ctrl_hint.custom_minimum_size = Vector2(340, 0)
		vbox.add_child(ctrl_hint)

		# Orientation — portrait is first-class + independent of the control scheme.
		var orient_hbox := HBoxContainer.new()
		orient_hbox.add_theme_constant_override("separation", 8)
		var orient_label := Label.new()
		orient_label.text = "Orientation"
		orient_label.add_theme_font_size_override("font_size", 13)
		orient_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		orient_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		orient_hbox.add_child(orient_label)
		var orient_value := Label.new()
		orient_value.text = globalvar.ORIENTATION_NAMES.get(globalvar.orientation_pref, "Landscape")
		orient_value.add_theme_font_size_override("font_size", 13)
		orient_value.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		orient_hbox.add_child(orient_value)
		var orient_btn := Button.new()
		orient_btn.text = "Change"
		orient_btn.custom_minimum_size = Vector2(90, 28)
		BS.apply_space_style(orient_btn, Color(0.5, 0.8, 1.0))
		orient_btn.add_theme_font_size_override("font_size", 12)
		orient_btn.pressed.connect(func():
			globalvar.set_orientation_pref((globalvar.orientation_pref + 1) % 2)
			globalvar.save_game()
			orient_value.text = globalvar.ORIENTATION_NAMES.get(globalvar.orientation_pref, "Landscape")
		)
		orient_hbox.add_child(orient_btn)
		vbox.add_child(orient_hbox)

		# Tilt sensitivity slider (WP-A3) — visible only in Tilt mode.
		var tilt_row := VBoxContainer.new()
		tilt_row.add_theme_constant_override("separation", 4)
		var tilt_hbox := HBoxContainer.new()
		tilt_hbox.add_theme_constant_override("separation", 8)
		var tilt_label := Label.new()
		tilt_label.text = "Tilt Sensitivity"
		tilt_label.add_theme_font_size_override("font_size", 13)
		tilt_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		tilt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tilt_hbox.add_child(tilt_label)
		var tilt_value := Label.new()
		tilt_value.text = "%.2f" % globalvar.tilt_sensitivity
		tilt_value.add_theme_font_size_override("font_size", 13)
		tilt_value.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		tilt_hbox.add_child(tilt_value)
		tilt_row.add_child(tilt_hbox)
		var tilt_slider := HSlider.new()
		tilt_slider.min_value = 1.0
		tilt_slider.max_value = 4.0
		tilt_slider.step = 0.25
		tilt_slider.value = globalvar.tilt_sensitivity
		tilt_slider.custom_minimum_size = Vector2(340, 20)
		tilt_slider.value_changed.connect(func(v: float):
			globalvar.tilt_sensitivity = v
			globalvar.save_game()
			tilt_value.text = "%.2f" % v
		)
		tilt_row.add_child(tilt_slider)
		tilt_row.visible = (globalvar.control_scheme == globalvar.ControlScheme.TILT)
		vbox.add_child(tilt_row)

		ctrl_btn.pressed.connect(func():
			globalvar.set_control_scheme((globalvar.control_scheme + 1) % 3)
			globalvar.save_game()
			ctrl_value.text = globalvar.CONTROL_SCHEME_NAMES.get(globalvar.control_scheme, "Tilt")
			tilt_row.visible = (globalvar.control_scheme == globalvar.ControlScheme.TILT)
		)

	# --- Desktop control glyphs (desktop + gamepad connected) — WP-A3 ---
	elif Input.get_connected_joypads().size() > 0:
		var dctrl_label := Label.new()
		dctrl_label.text = "Controls"
		dctrl_label.add_theme_font_size_override("font_size", 14)
		dctrl_label.add_theme_color_override("font_color", Color.ORANGE)
		vbox.add_child(dctrl_label)

		var dctrl_hbox := HBoxContainer.new()
		dctrl_hbox.add_theme_constant_override("separation", 8)
		var dctrl_value := Label.new()
		dctrl_value.text = globalvar.DESKTOP_CONTROL_NAMES.get(globalvar.desktop_control, "Keyboard")
		dctrl_value.add_theme_font_size_override("font_size", 13)
		dctrl_value.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		dctrl_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dctrl_hbox.add_child(dctrl_value)

		var dctrl_btn := Button.new()
		dctrl_btn.text = "Change"
		dctrl_btn.custom_minimum_size = Vector2(90, 28)
		BS.apply_space_style(dctrl_btn, Color(0.5, 0.8, 1.0))
		dctrl_btn.add_theme_font_size_override("font_size", 12)
		dctrl_btn.pressed.connect(func():
			globalvar.set_desktop_control((globalvar.desktop_control + 1) % 2)
			globalvar.save_game()
			dctrl_value.text = globalvar.DESKTOP_CONTROL_NAMES.get(globalvar.desktop_control, "Keyboard")
		)
		dctrl_hbox.add_child(dctrl_btn)
		vbox.add_child(dctrl_hbox)

		var dctrl_hint := Label.new()
		dctrl_hint.text = "Keyboard and controller both work — this picks which button hints you see."
		dctrl_hint.add_theme_font_size_override("font_size", 11)
		dctrl_hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
		dctrl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		dctrl_hint.custom_minimum_size = Vector2(340, 0)
		vbox.add_child(dctrl_hint)

	# --- Audio (all platforms) — WP-A3, Music-only v1 ---
	var audio_label := Label.new()
	audio_label.text = "Audio"
	audio_label.add_theme_font_size_override("font_size", 14)
	audio_label.add_theme_color_override("font_color", Color.ORANGE)
	vbox.add_child(audio_label)

	var music_chk := CheckButton.new()
	music_chk.text = "Music"
	music_chk.button_pressed = globalvar.music_enabled
	music_chk.add_theme_font_size_override("font_size", 13)
	music_chk.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	music_chk.toggled.connect(func(pressed: bool):
		globalvar.set_music_enabled(pressed)
	)
	vbox.add_child(music_chk)

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


# --- Store popup (IAP shortcut from main menu) ---

var _store_popup: PanelContainer = null

func _show_store_popup() -> void:
	if _store_popup and is_instance_valid(_store_popup):
		_store_popup.queue_free()

	var panel := PanelContainer.new()
	panel.name = "StorePopup"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.1, 0.97)
	style.border_color = Color(1.0, 0.85, 0.2, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(1.0, 0.85, 0.2, 0.25)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	panel.z_index = 15
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -240
	panel.offset_bottom = 240
	_store_popup = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Store"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Wallet:  %d Moonrocks" % globalvar.wallet
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# --- Remove Ads ---
	# Mobile (iOS/Android) ALWAYS shows the real-money IAP button regardless
	# of whether StoreKit/Play Billing has finished its async product fetch.
	# Otherwise Apple review opens Store within the few-second window before
	# init completes, sees the moonrock fallback (and it's disabled because
	# wallet is 0 on a fresh install), and rejects with "Remove Ads
	# unresponsive" / "cannot locate IAPs".
	if not globalvar.is_ads_removed():
		var ra_btn := Button.new()
		ra_btn.custom_minimum_size = Vector2(420, 44)
		ra_btn.add_theme_font_size_override("font_size", 16)
		BS.apply_space_style(ra_btn, Color(0.9, 0.3, 0.9))
		if IAPManager.is_supported():
			ra_btn.text = "Remove Ads — %s" % IAPManager.get_price(IAPManager.PRODUCT_REMOVE_ADS)
			ra_btn.pressed.connect(func(): IAPManager.purchase(IAPManager.PRODUCT_REMOVE_ADS))
		else:
			# Web/desktop fallback: spend 10k Moonrocks
			ra_btn.text = "Remove Ads — %d Moonrocks" % globalvar.AD_REMOVAL_COST
			ra_btn.disabled = globalvar.wallet < globalvar.AD_REMOVAL_COST
			ra_btn.pressed.connect(func():
				if AdManager.remove_ads():
					_close_store_popup()
			)
		vbox.add_child(ra_btn)
	else:
		var ad_free := Label.new()
		ad_free.text = "✅ Ad-free unlocked — thank you!"
		ad_free.add_theme_font_size_override("font_size", 14)
		ad_free.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		ad_free.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(ad_free)

	# --- Moonrock packs (real IAP only) ---
	# Same fix as Remove Ads above — gate on is_supported (platform) not
	# is_available (init state) so Apple review sees the buttons on first
	# Store popup open before StoreKit's async product fetch finishes.
	if IAPManager.is_supported():
		vbox.add_child(HSeparator.new())
		var pack_header := Label.new()
		pack_header.text = "Moonrock Packs"
		pack_header.add_theme_font_size_override("font_size", 16)
		pack_header.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
		pack_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(pack_header)

		for pid in [IAPManager.PRODUCT_MOONROCKS_10K, IAPManager.PRODUCT_MOONROCKS_50K]:
			var btn := Button.new()
			var label: String = IAPManager.PRODUCT_LABELS.get(pid, pid)
			var price: String = IAPManager.get_price(pid)
			btn.text = "%s   —   %s" % [label, price]
			btn.custom_minimum_size = Vector2(420, 44)
			btn.add_theme_font_size_override("font_size", 16)
			BS.apply_space_style(btn, Color(0.5, 0.85, 1.0))
			var product_id: String = pid
			btn.pressed.connect(func(): IAPManager.purchase(product_id))
			vbox.add_child(btn)

		var restore_btn := Button.new()
		restore_btn.text = "Restore Purchases"
		restore_btn.flat = true
		restore_btn.custom_minimum_size = Vector2(420, 28)
		restore_btn.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85))
		restore_btn.add_theme_font_size_override("font_size", 12)
		restore_btn.pressed.connect(func(): IAPManager.restore_purchases())
		vbox.add_child(restore_btn)

	vbox.add_child(HSeparator.new())

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(140, 36)
	BS.apply_space_style(close, Color.RED)
	close.pressed.connect(_close_store_popup)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	close_row.add_child(close)
	vbox.add_child(close_row)


func _close_store_popup() -> void:
	if _store_popup and is_instance_valid(_store_popup):
		_store_popup.queue_free()
	_store_popup = null


func _show_reset_confirmation() -> void:
	## Custom-styled, scary reset confirmation. Cloud save gets overwritten —
	## this is permanent and cannot be undone.
	var popup := _build_styled_popup(Color(1.0, 0.25, 0.2, 0.9))
	popup.name = "ResetConfirmPopup"
	add_child(popup)
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.offset_left = -260
	popup.offset_right = 260
	popup.offset_top = -210
	popup.offset_bottom = 210

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)

	var title := Label.new()
	title.text = "⚠️  RESET PROGRESS?  ⚠️"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var warn := Label.new()
	warn.text = "THIS CANNOT BE UNDONE"
	warn.add_theme_font_size_override("font_size", 18)
	warn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(warn)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(440, 0)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_color_override("default_color", Color(0.85, 0.88, 0.95))
	body.text = (
		"You will permanently lose:\n"
		+ "  • All level progress and best times\n"
		+ "  • Your wallet, upgrades, and skins\n"
		+ "  • Your stats (deaths, lifetime crypto)\n\n"
		+ "[color=#ff8866]Your cloud save will also be overwritten[/color] with the empty progress, "
		+ "so [b]even restoring from cloud will not bring it back[/b].\n\n"
		+ "You will get a new random nickname and see the tutorial again."
	)
	vbox.add_child(body)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Keep My Progress"
	cancel_btn.custom_minimum_size = Vector2(180, 36)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	BS.apply_space_style(cancel_btn, Color.GREEN)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	btn_row.add_child(cancel_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset Everything"
	reset_btn.custom_minimum_size = Vector2(180, 36)
	reset_btn.add_theme_font_size_override("font_size", 14)
	BS.apply_space_style(reset_btn, Color(1.0, 0.25, 0.2))
	reset_btn.pressed.connect(func():
		popup.queue_free()
		globalvar.reset_progress()
		if _options_popup and is_instance_valid(_options_popup):
			_options_popup.queue_free()
		_show_reset_toast()
		var timer := get_tree().create_timer(2.0)
		timer.timeout.connect(func():
			get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
		)
	)
	btn_row.add_child(reset_btn)
	cancel_btn.grab_focus()


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


func _build_styled_nickname_line_edit(initial_text: String) -> LineEdit:
	## Styled LineEdit matching the dark/cyan space theme.
	var le := LineEdit.new()
	le.text = initial_text
	le.max_length = 20
	le.placeholder_text = "Enter nickname..."
	le.custom_minimum_size = Vector2(320, 38)
	le.add_theme_font_size_override("font_size", 16)
	le.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	le.add_theme_color_override("font_placeholder_color", Color(0.5, 0.6, 0.7))
	le.add_theme_color_override("caret_color", Color(0.5, 0.85, 1.0))
	le.add_theme_color_override("selection_color", Color(0.3, 0.6, 1.0, 0.5))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.14, 0.9)
	sb.border_color = Color(0.5, 0.8, 1.0, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	le.add_theme_stylebox_override("normal", sb)
	var sb_focus := sb.duplicate()
	sb_focus.border_color = Color(0.6, 0.95, 1.0, 1.0)
	sb_focus.set_border_width_all(2)
	le.add_theme_stylebox_override("focus", sb_focus)
	return le


func _build_styled_popup(border_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.1, 0.97)
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.25)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	panel.z_index = 15
	# Grow from the anchor in BOTH directions so a popup whose content exceeds its
	# offset box stays CENTERED instead of drifting right/down (the default
	# GROW_DIRECTION_END caused the off-center welcome popup in portrait). This one
	# line immunizes every _build_styled_popup caller.
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	return panel


func _show_first_time_nickname_prompt() -> void:
	## First-launch welcome popup. Custom-styled to match the rest of the menu.
	# Skip during automated capture/autopilot/sim runs so video renders and headless
	# bots never stall here waiting on nickname input.
	var _argv := OS.get_cmdline_args()
	if "--capture" in _argv or "--autopilot" in _argv or "--sim" in _argv:
		return
	# Adaptive first-run picker (WP-A1). Control section content depends on
	# platform + connected devices; both option cards are equal weight (no nudge).
	var is_mob := OS.get_name() == "Android" or OS.get_name() == "iOS"
	var has_pad := Input.get_connected_joypads().size() > 0
	# Control section shown on mobile (always) and on desktop with a pad. Desktop
	# with no pad keeps the original nickname-only welcome.
	var show_controls := is_mob or has_pad

	var popup := _build_styled_popup(Color(0.5, 0.85, 1.0, 0.7))
	popup.name = "WelcomePopup"
	add_child(popup)
	popup.set_anchors_preset(Control.PRESET_CENTER)
	if show_controls:
		popup.offset_left = -240
		popup.offset_right = 240
		popup.offset_top = -210
		popup.offset_bottom = 210
	else:
		popup.offset_left = -220
		popup.offset_right = 220
		popup.offset_top = -150
		popup.offset_bottom = 150

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)

	var title := Label.new()
	title.text = "🚀  Welcome, Pilot!"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Pending control choice; value = -1 means nothing picked yet. Dictionary so
	# the select/commit closures share one mutable reference.
	var sel := { "value": -1, "style": "" }
	var card_btns: Array = []
	# Created up-front so the select closure can enable it on pick.
	var start_btn := Button.new()

	if show_controls:
		var prompt_c := Label.new()
		prompt_c.text = "How do you want to steer?" if is_mob else "Choose your controls"
		prompt_c.add_theme_font_size_override("font_size", 15)
		prompt_c.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		prompt_c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(prompt_c)

		var opts: Array = []
		if is_mob:
			opts = [
				{ "emoji": "📱", "title": "Tilt", "sub": "Roll to turn, tap to thrust", "value": globalvar.ControlScheme.TILT, "style": "tilt" },
				{ "emoji": "🕹", "title": "Joystick", "sub": "On-screen stick + buttons", "value": globalvar.ControlScheme.JOYSTICK, "style": "joystick" },
				{ "emoji": "🎢", "title": "Full Tilt", "sub": "Portrait · tilt to fly, no buttons", "value": globalvar.ControlScheme.FULL_TILT, "style": "full_tilt" },
			]
		else:
			opts = [
				{ "emoji": "⌨", "title": "Keyboard", "sub": "Arrow keys + Space", "value": globalvar.DesktopControl.KEYBOARD, "style": "keyboard" },
				{ "emoji": "🎮", "title": "Gamepad", "sub": "Stick + buttons", "value": globalvar.DesktopControl.GAMEPAD, "style": "gamepad" },
			]

		var cards_row := HBoxContainer.new()
		cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
		cards_row.add_theme_constant_override("separation", 14)
		vbox.add_child(cards_row)

		# Selecting highlights the chosen card and enables Start.
		var select := func(idx: int) -> void:
			sel["value"] = opts[idx]["value"]
			sel["style"] = opts[idx]["style"]
			for i in card_btns.size():
				card_btns[i].modulate = Color.WHITE if i == idx else Color(0.6, 0.63, 0.7)
			start_btn.disabled = false

		for i in opts.size():
			var opt: Dictionary = opts[i]
			var card := Button.new()
			card.custom_minimum_size = Vector2(200, 100)
			# Emoji / title / subtitle on three lines. No autowrap (kept off the
			# Button API): the card is sized so the longest subtitle fits one line.
			card.text = "%s\n%s\n%s" % [opt["emoji"], opt["title"], opt["sub"]]
			card.add_theme_font_size_override("font_size", 13)
			BS.apply_space_style(card, Color(0.5, 0.85, 1.0))
			card.modulate = Color(0.6, 0.63, 0.7)
			var idx := i
			card.pressed.connect(func() -> void: select.call(idx))
			card_btns.append(card)
			cards_row.add_child(card)

		# Desktop: keyboard is a safe default — pre-select it (Start stays
		# enabled). Mobile: NO default — Start disabled until one is tapped.
		if not is_mob:
			select.call(0)

		var footer := Label.new()
		footer.text = "Change anytime in Options or Pause."
		footer.add_theme_font_size_override("font_size", 11)
		footer.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(footer)

	# --- Nickname (optional) ---
	var prompt := Label.new()
	prompt.text = "Enter your pilot nickname"
	prompt.add_theme_font_size_override("font_size", 14)
	prompt.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt)

	var hint := Label.new()
	hint.text = "(leave blank for a random one)"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var line_edit := _build_styled_nickname_line_edit("")
	vbox.add_child(line_edit)

	start_btn.text = "Start Game"
	start_btn.custom_minimum_size = Vector2(180, 36)
	BS.apply_space_style(start_btn, Color.GREEN)
	start_btn.add_theme_font_size_override("font_size", 14)
	# Mobile with an unpicked control section: disabled until a card is tapped
	# (the anti-churn point — tilt must not be a silent default).
	start_btn.disabled = (show_controls and is_mob and int(sel["value"]) < 0)
	var commit := func() -> void:
		var cleaned := line_edit.text.strip_edges().left(20)
		if cleaned != "":
			globalvar.nickname = cleaned
		if show_controls and int(sel["value"]) >= 0:
			if is_mob:
				globalvar.set_control_scheme(int(sel["value"]))
			else:
				globalvar.set_desktop_control(int(sel["value"]))
			# Learn the real control split.
			Analytics.event("control_scheme_chosen", { "style": sel["style"] })
		globalvar.welcome_shown = true
		globalvar.save_game()
		popup.queue_free()
	start_btn.pressed.connect(func() -> void:
		if not start_btn.disabled:
			commit.call()
	)
	line_edit.text_submitted.connect(func(_t):
		if not start_btn.disabled:
			commit.call()
	)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_child(start_btn)
	vbox.add_child(btn_row)

	# On mobile, top-anchor so the (optional) on-screen keyboard doesn't cover
	# the field if the player taps it. Do NOT auto-grab focus here — the control
	# cards must stay visible/tappable (raising the keyboard would hide them).
	if is_mob:
		vbox.add_theme_constant_override("separation", 8)
		if globalvar.wants_portrait():
			# Portrait: the popup sits upper-middle, well clear of the keyboard —
			# center it so it isn't stranded at the top of the tall viewport.
			popup.set_anchors_preset(Control.PRESET_CENTER)
			popup.offset_left = -240
			popup.offset_right = 240
			popup.offset_top = -235
			popup.offset_bottom = 235
		else:
			# Landscape (short): top-anchor so the on-screen keyboard doesn't cover
			# the nickname field when tapped.
			popup.set_anchors_preset(Control.PRESET_CENTER_TOP)
			popup.offset_left = -240
			popup.offset_right = 240
			popup.offset_top = 8
			popup.offset_bottom = 430


func _show_nickname_edit_popup(nick_label: Label) -> void:
	## Styled nickname-edit popup (replaces AcceptDialog OS chrome).
	var popup := _build_styled_popup(Color(0.5, 0.85, 1.0, 0.7))
	popup.name = "NicknameEditPopup"
	add_child(popup)
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.offset_left = -220
	popup.offset_right = 220
	popup.offset_top = -130
	popup.offset_bottom = 130

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)

	var title := Label.new()
	title.text = "Edit Nickname"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var line_edit := _build_styled_nickname_line_edit(globalvar.nickname)
	vbox.add_child(line_edit)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var commit := func():
		var cleaned := line_edit.text.strip_edges().left(20)
		if cleaned == "":
			cleaned = globalvar.generate_random_nickname()
		globalvar.nickname = cleaned
		globalvar.save_game()
		nick_label.text = cleaned
		popup.queue_free()

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(120, 32)
	BS.apply_space_style(save_btn, Color.GREEN)
	save_btn.pressed.connect(commit)
	btn_row.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 32)
	BS.apply_space_style(cancel_btn, Color.RED)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	btn_row.add_child(cancel_btn)

	line_edit.text_submitted.connect(func(_t): commit.call())
	# On mobile, pin to the top so the field stays above the landscape
	# on-screen keyboard (same reasoning as the first-launch prompt).
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		popup.set_anchors_preset(Control.PRESET_CENTER_TOP)
		popup.offset_left = -220
		popup.offset_right = 220
		popup.offset_top = 8
		popup.offset_bottom = 230
	line_edit.call_deferred("grab_focus")
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


func _on_race_pressed():
	# Race always uses Level 1 (the only level the CPU reliably lands in race time).
	globalvar.nowlevel = 1
	globalvar.race_mode = true
	WarpTransition.warp_to(globalvar.get_level_scene(1))

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

	# Bottom row: open the full web leaderboard + close
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var web_btn := Button.new()
	web_btn.text = "🌐 Full Board"
	web_btn.custom_minimum_size = Vector2(180, 34)
	BS.apply_space_style(web_btn, Color(1.0, 0.85, 0.2))
	web_btn.pressed.connect(func(): OS.shell_open("https://such.software/products/such-moon-launch/leaderboard"))
	btn_row.add_child(web_btn)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 34)
	BS.apply_space_style(close, Color.RED)
	close.pressed.connect(func(): _lb_popup.queue_free())
	btn_row.add_child(close)

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
	if not _is_mobile_ui():
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
