extends Node2D
## Procedural endless mode — random planets, scaling difficulty, infinite waves.
## Unlocked after completing the main campaign. Each landing starts a new wave.

const PLANET_SCENES := [
	preload("res://game/mars/Mars.tscn"),
	preload("res://game/moon/Moon.tscn"),
	preload("res://game/venus/Venus.tscn"),
	preload("res://game/jupiter/Jupiter.tscn"),
	preload("res://game/saturn/Saturn.tscn"),
	preload("res://game/neptune/Neptune.tscn"),
	preload("res://game/pluto/Pluto.tscn"),
]

var gammaray = preload("res://game/gammaray/GammeRay.tscn")
var asteriod = preload("res://game/asteriod/Asteriod.tscn")
var asteriod2 = preload("res://game/asteriod/Asteriod2.tscn")
var martian_scene = preload("res://game/martian/Martian.tscn")
var orbiting_ast = preload("res://game/asteriod/OrbitingAsteroid.tscn")
var crypto_spawner_scene = preload("res://game/crypto/CryptoSpawner.tscn")
var fuel_spawner_scene = preload("res://game/fuel/FuelSpawner.tscn")

var wave: int = 1


func _ready():
	globalvar.nowlevel = 12
	globalvar.endless_mode = true
	wave = globalvar.endless_wave

	var space = get_world_2d().get_space()
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, 0)
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR, Vector2(0, 1))

	_generate_wave()
	_show_wave_label()


func _generate_wave() -> void:
	# Target planet at scaling distance
	var target_dist := 800 + wave * 200
	var target_y := randf_range(-300, 300)
	var target_pos := Vector2(target_dist, target_y)

	var planet := PLANET_SCENES.pick_random().instantiate()
	planet.position = target_pos
	add_child(planet)

	# Optional waypoint planet halfway (waves 3+)
	if wave >= 3:
		var wp_pos := Vector2(target_dist * 0.5, randf_range(-200, 200))
		var wp := PLANET_SCENES.pick_random().instantiate()
		wp.position = wp_pos
		add_child(wp)
		# Orbiting asteroids around waypoint
		var orb_count := mini(wave - 1, 5)
		for i in range(orb_count):
			var oa := orbiting_ast.instantiate()
			add_child(oa)
			oa.setup(wp, 100.0 + randf_range(-15, 30), randf_range(0.8, 1.5))

	# Martians — scales with wave
	var martian_count := mini(2 + wave * 2, 24)
	for i in range(martian_count):
		var m := martian_scene.instantiate()
		m.position = Vector2(
			randf_range(350, target_dist - 100),
			randf_range(-400, 400)
		)
		m.speed = mini(30 + wave * 4, 80)
		add_child(m)

	# Crypto spawners
	var crypto_count := mini(1 + wave / 2, 4)
	for i in range(crypto_count):
		var cs := crypto_spawner_scene.instantiate()
		cs.position = Vector2(
			randf_range(400, target_dist - 200),
			randf_range(-300, 300)
		)
		cs.spawn_count = randi_range(3, 5)
		cs.spawn_radius = 200.0
		# Higher waves = rarer crypto
		if wave >= 4:
			cs.xmr_weight = 4.0
			cs.btc_weight = 2.0
		add_child(cs)

	# Fuel spawner — always one near the midpoint
	var fs := fuel_spawner_scene.instantiate()
	fs.position = Vector2(target_dist * 0.5 + randf_range(-100, 100), randf_range(-150, 150))
	fs.spawn_count = 1
	fs.fuel_percent = maxf(0.15, 0.3 - wave * 0.02)  # Less fuel in later waves
	add_child(fs)

	# Extra fuel near target for long journeys
	if wave >= 4:
		var fs2 := fuel_spawner_scene.instantiate()
		fs2.position = Vector2(target_dist * 0.75, randf_range(-200, 200))
		fs2.spawn_count = 1
		fs2.fuel_percent = 0.15
		add_child(fs2)


func _show_wave_label() -> void:
	var label := Label.new()
	label.text = "WAVE  %d" % wave
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position.y -= 80
	get_node("CanvasLayer").add_child(label)
	# Animate: pop in, hold, fade out
	label.scale = Vector2(0.3, 0.3)
	label.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_ELASTIC)
	tw.set_parallel(true)
	tw.tween_property(label, "scale", Vector2.ONE, 0.5)
	tw.tween_property(label, "modulate", Color.WHITE, 0.3)
	tw.set_parallel(false)
	tw.tween_interval(1.5)
	tw.tween_property(label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(label.queue_free)


func add_laser():
	var g_ray = gammaray.instantiate()
	add_child(g_ray)
	if randf() < 0.5:
		g_ray.global_position = $Rocket.global_position + Vector2(0, randf_range(-400, 400))
		g_ray.move_landR()
	else:
		g_ray.global_position = $Rocket.global_position + Vector2(randf_range(-700, 700), 0)
		g_ray.move_tandB()


func add_asteriod():
	var ast = asteriod.instantiate()
	if randf() < 0.5:
		ast = asteriod2.instantiate()
	add_child(ast)
	if randf() < 0.5:
		ast.global_position = $Rocket.global_position + Vector2(0, randf_range(-400, 400))
		ast.move_landR()
	else:
		ast.global_position = $Rocket.global_position + Vector2(randf_range(-700, 700), 0)
		ast.move_tandB()


func _on_RayTimer_timeout():
	if wave >= 2:
		add_laser()
	# Faster rays in later waves
	var base_min := maxf(1.5, 4.0 - wave * 0.3)
	var base_max := maxf(3.0, 7.0 - wave * 0.4)
	$RayTimer.wait_time = randf_range(base_min, base_max) * globalvar.get_spawn_interval_mult()


func _on_AsteriodTimer_timeout():
	if wave >= 3:
		add_asteriod()
	var base_min := maxf(1.5, 4.0 - wave * 0.2)
	var base_max := maxf(3.0, 6.0 - wave * 0.3)
	$AsteriodTimer.wait_time = randf_range(base_min, base_max) * globalvar.get_spawn_interval_mult()
