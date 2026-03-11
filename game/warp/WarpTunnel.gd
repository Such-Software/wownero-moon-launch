extends Node3D
## Hyperspace warp tunnel — 3D transition scene between menu/shop and gameplay levels.
## Displays a cockpit frame over a rushing star tunnel.
## Usage: add_child(WarpTunnel), call warp_to(target_scene_path).

const WARP_DURATION := 3.0  # seconds of tunnel before loading target
const STAR_COUNT := 300
const TUNNEL_RADIUS := 8.0
const TUNNEL_LENGTH := 100.0

var _target_scene: String = ""
var _elapsed: float = 0.0
var _stars: Array[MeshInstance3D] = []
var _camera: Camera3D = null
var _cockpit_layer: CanvasLayer = null
var _speed_lines_layer: CanvasLayer = null
var _speed_progress: float = 0.0  # 0→1 over duration

func _ready() -> void:
	# Environment — black void
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Camera — looking forward down the tunnel
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 0)
	_camera.rotation = Vector3.ZERO
	_camera.fov = 75.0
	add_child(_camera)
	_camera.make_current()

	# Generate star meshes scattered in a tunnel ahead of camera
	_generate_stars()

	# Cockpit overlay (CanvasLayer on top of 3D)
	_cockpit_layer = CanvasLayer.new()
	_cockpit_layer.layer = 10
	add_child(_cockpit_layer)

	var cockpit_tex = load("res://art/ship/cockpit.png")
	if cockpit_tex:
		# Cockpit image — full screen width, bottom-aligned, pushed slightly below screen
		var cockpit_sprite := TextureRect.new()
		cockpit_sprite.texture = cockpit_tex
		cockpit_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cockpit_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cockpit_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cockpit_sprite.anchor_left = 0.0
		cockpit_sprite.anchor_right = 1.0
		cockpit_sprite.anchor_bottom = 1.0
		cockpit_sprite.anchor_top = 1.0
		cockpit_sprite.offset_left = 0
		cockpit_sprite.offset_right = 0
		# Push bottom edge 10% of screen height below screen bottom
		cockpit_sprite.offset_bottom = 600.0 * 0.10
		# Height from aspect ratio: full viewport width / image aspect
		var img_aspect := float(cockpit_tex.get_width()) / float(cockpit_tex.get_height())
		cockpit_sprite.offset_top = cockpit_sprite.offset_bottom - (1024.0 / img_aspect)
		_cockpit_layer.add_child(cockpit_sprite)

	# Speed lines overlay (drawn procedurally)
	_speed_lines_layer = CanvasLayer.new()
	_speed_lines_layer.layer = 9
	add_child(_speed_lines_layer)
	var speed_rect := ColorRect.new()
	speed_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_rect.color = Color(0, 0, 0, 0)
	speed_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_rect.set_script(_create_speed_lines_script())
	_speed_lines_layer.add_child(speed_rect)

	# HUD text — "ENTERING HYPERSPACE" label
	var label := Label.new()
	label.text = ""
	label.name = "WarpLabel"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0, 0.8))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_top = -80
	label.offset_bottom = -40
	label.offset_left = -200
	label.offset_right = 200
	_cockpit_layer.add_child(label)

	# Animate label text
	_animate_label(label)

	# Fade in from black
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cockpit_layer.add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.5)
	tw.tween_callback(fade.queue_free)


func warp_to(target_scene: String) -> void:
	_target_scene = target_scene


func _generate_stars() -> void:
	# Simple star material — white emissive quad
	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = Color.WHITE
	star_mat.emission_enabled = true
	star_mat.emission = Color(0.8, 0.9, 1.0)
	star_mat.emission_energy_multiplier = 3.0
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mat.no_depth_test = true

	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.04, 0.04)

	for i in range(STAR_COUNT):
		var mi := MeshInstance3D.new()
		mi.mesh = star_mesh
		mi.material_override = star_mat.duplicate()
		# Random position in a cylinder ahead of the camera
		var angle := randf() * TAU
		var r := randf_range(1.0, TUNNEL_RADIUS)
		var z := randf_range(-5.0, -TUNNEL_LENGTH)
		mi.position = Vector3(cos(angle) * r, sin(angle) * r, z)
		add_child(mi)
		_stars.append(mi)


func _process(delta: float) -> void:
	_elapsed += delta
	_speed_progress = clampf(_elapsed / WARP_DURATION, 0.0, 1.0)

	# Accelerating speed curve — slow start, fast end
	var speed_curve := _speed_progress * _speed_progress * _speed_progress
	var star_speed := lerpf(5.0, 120.0, speed_curve)

	# Move stars toward camera (streaming effect)
	for star in _stars:
		star.position.z += star_speed * delta
		# Stretch stars into lines at high speed
		var stretch := lerpf(1.0, 30.0, speed_curve)
		star.scale = Vector3(1.0, 1.0, stretch)
		# Intensify color over time — white → blue-shifted
		var mat: StandardMaterial3D = star.material_override
		var blue_shift := lerpf(0.0, 0.5, _speed_progress)
		mat.emission = Color(0.8 - blue_shift * 0.4, 0.9 - blue_shift * 0.2, 1.0)
		mat.emission_energy_multiplier = lerpf(2.0, 6.0, speed_curve)
		# Recycle stars that pass behind camera
		if star.position.z > 5.0:
			var angle := randf() * TAU
			var r := randf_range(1.0, TUNNEL_RADIUS)
			star.position = Vector3(cos(angle) * r, sin(angle) * r, -TUNNEL_LENGTH)

	# Camera shake increases with speed
	var shake := speed_curve * 0.15
	_camera.rotation.x = randf_range(-shake, shake) * 0.3
	_camera.rotation.y = randf_range(-shake, shake) * 0.3

	# FOV widens as speed increases
	_camera.fov = lerpf(75.0, 95.0, speed_curve)

	# Transition out
	if _elapsed >= WARP_DURATION - 0.4 and _elapsed < WARP_DURATION:
		# White flash + fade
		pass

	if _elapsed >= WARP_DURATION:
		_finish_warp()


func _finish_warp() -> void:
	set_process(false)
	# White flash then load target
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cockpit_layer.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 1.0, 0.3)
	tw.tween_callback(func():
		if _target_scene.is_empty():
			return
		get_tree().change_scene_to_file(_target_scene)
	)


func _animate_label(label: Label) -> void:
	# Level name from globalvar
	var level_name: String = globalvar.LEVEL_NAMES.get(globalvar.nowlevel, "Unknown")
	var full_text := "WARPING TO %s..." % level_name.to_upper()

	# Typewriter effect
	var tw := create_tween()
	for i in range(full_text.length() + 1):
		var partial := full_text.substr(0, i)
		tw.tween_callback(func(): label.text = partial)
		tw.tween_interval(0.04)

	# Pulse after complete
	tw.tween_interval(0.3)
	tw.tween_callback(func():
		var pulse := create_tween().set_loops(5)
		pulse.tween_property(label, "modulate:a", 0.4, 0.3)
		pulse.tween_property(label, "modulate:a", 1.0, 0.3)
	)


func _create_speed_lines_script() -> GDScript:
	## Returns an inline script for the speed-lines overlay.
	var src := """extends ColorRect

var _warp_parent: Node = null

func _ready():
	_warp_parent = get_parent().get_parent()

func _process(_d):
	queue_redraw()

func _draw():
	if not is_instance_valid(_warp_parent):
		return
	var progress: float = _warp_parent._speed_progress
	if progress < 0.1:
		return
	var center := size / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec() / 50)
	var line_count := int(lerpf(5.0, 40.0, progress))
	for i in range(line_count):
		var angle := rng.randf() * TAU
		var dir := Vector2(cos(angle), sin(angle))
		var inner_r := lerpf(50.0, 20.0, progress)
		var outer_r := lerpf(100.0, maxf(size.x, size.y) * 0.7, progress)
		var p1 := center + dir * inner_r
		var p2 := center + dir * outer_r
		var alpha := lerpf(0.05, 0.25, progress) * rng.randf_range(0.5, 1.0)
		var w := lerpf(0.5, 2.0, progress)
		draw_line(p1, p2, Color(0.6, 0.8, 1.0, alpha), w)
"""
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	return script
