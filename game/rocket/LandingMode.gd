extends CanvasLayer
## 3D Landing Mode — activates near landing target.
## Shows a 3D chase-cam view of the planet surface with the rocket descending.
## 2D physics remains the source of truth; 3D is a visual mirror.
## The normal 2D game continues running underneath — player keeps full control.

const TILT_DEATH_ANGLE := deg_to_rad(35.0)
const TILT_WARN_ANGLE := deg_to_rad(18.0)

# 3D mapping
var _max_altitude: float = 150.0   # set from trigger range
const ALTITUDE_3D_MAX := 12.0
const LATERAL_SCALE := 0.03
const GROUND_SIZE := 30.0

# References
var _rocket: RigidBody2D = null
var _target: Node2D = null

# 3D scene
var _viewport_3d: SubViewport = null
var _container_3d: SubViewportContainer = null
var _scene_3d: Node3D = null
var _camera_3d: Camera3D = null
var _rocket_sprite_3d: Sprite3D = null
var _ground_mesh: MeshInstance3D = null
var _hazard_sprites: Dictionary = {}

# HUD
var _altitude_label: Label = null
var _speed_label: Label = null
var _tilt_indicator: Control = null
var _landing_label: Label = null
var _left_arrow: Label = null
var _right_arrow: Label = null
var _landing_flash_tween: Tween = null

var _active: bool = false


func setup(rocket: RigidBody2D, target: Node2D, trigger_range: float = 150.0) -> void:
	_rocket = rocket
	_target = target
	_max_altitude = trigger_range
	layer = 8


func _ready() -> void:
	_build_3d_viewport()
	_build_hud()
	_active = true


func _build_3d_viewport() -> void:
	# Use half-res viewport to reduce GPU cost — upscaled via stretch
	_viewport_3d = SubViewport.new()
	_viewport_3d.size = Vector2i(512, 300)
	_viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_3d.transparent_bg = false
	_viewport_3d.own_world_3d = true

	_container_3d = SubViewportContainer.new()
	_container_3d.stretch = true
	_container_3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container_3d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container_3d.add_child(_viewport_3d)
	add_child(_container_3d)

	_scene_3d = Node3D.new()
	_viewport_3d.add_child(_scene_3d)

	# Simple environment — dark sky, some ambient light
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.06)
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_scene_3d.add_child(world_env)

	# Single directional light (sun)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-40), deg_to_rad(25), 0)
	light.light_energy = 0.9
	light.shadow_enabled = false
	light.light_color = Color(1.0, 0.95, 0.85)
	_scene_3d.add_child(light)

	# Fill light from below for surface detail
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation = Vector3(deg_to_rad(30), deg_to_rad(-60), 0)
	fill_light.light_energy = 0.25
	fill_light.light_color = Color(0.6, 0.7, 1.0)
	fill_light.shadow_enabled = false
	_scene_3d.add_child(fill_light)

	# Planet surface — large sphere rotated so pole singularity faces sideways (not camera)
	_ground_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 50.0
	sphere.height = 100.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_ground_mesh.mesh = sphere
	_ground_mesh.position = Vector3(0, -50.0, 0)  # top of sphere at Y=0
	_ground_mesh.rotation.x = PI / 2.0  # rotate pole to face Z, equator faces up

	var ground_mat := StandardMaterial3D.new()
	# Sample the planet sprite's average color for the surface
	var planet_tex := _get_target_texture()
	var surface_color := Color(0.5, 0.5, 0.5)
	if planet_tex:
		var img: Image = planet_tex.get_image()
		if img:
			img.resize(4, 4)  # tiny sample for average color
			var r := 0.0; var g := 0.0; var b := 0.0; var count := 0
			for py in 4:
				for px in 4:
					var c := img.get_pixel(px, py)
					if c.a > 0.1:
						r += c.r; g += c.g; b += c.b; count += 1
			if count > 0:
				surface_color = Color(r / count, g / count, b / count)
	ground_mat.albedo_color = surface_color
	ground_mat.roughness = 0.85
	# Procedural noise for terrain variation (craters/highlands)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	ground_mat.detail_enabled = true
	ground_mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	ground_mat.detail_albedo = noise_tex
	ground_mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	# Rim lighting for atmosphere glow
	ground_mat.rim_enabled = true
	ground_mat.rim = 0.4
	ground_mat.rim_tint = 0.3
	_ground_mesh.material_override = ground_mat
	_scene_3d.add_child(_ground_mesh)

	# Background stars — lightweight
	_add_background_stars()

	# Camera — chase cam behind and above
	_camera_3d = Camera3D.new()
	_camera_3d.fov = 65.0
	_camera_3d.position = Vector3(0, ALTITUDE_3D_MAX + 2, 4)
	_camera_3d.look_at(Vector3.ZERO)
	_scene_3d.add_child(_camera_3d)

	# Rocket as Sprite3D
	_rocket_sprite_3d = Sprite3D.new()
	var skin_tex := load(globalvar.get_skin_texture_path())
	if skin_tex:
		_rocket_sprite_3d.texture = skin_tex
	_rocket_sprite_3d.pixel_size = 0.004
	_rocket_sprite_3d.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_rocket_sprite_3d.rotation.y = PI  # face the camera (behind)
	_rocket_sprite_3d.position = Vector3(0, ALTITUDE_3D_MAX, 0)
	_scene_3d.add_child(_rocket_sprite_3d)


func _add_background_stars() -> void:
	var star_mat := StandardMaterial3D.new()
	star_mat.emission_enabled = true
	star_mat.emission = Color(0.9, 0.9, 1.0)
	star_mat.emission_energy_multiplier = 2.0
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mat.no_depth_test = true
	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.04, 0.04)
	for i in range(30):
		var mi := MeshInstance3D.new()
		mi.mesh = star_mesh
		mi.material_override = star_mat
		var angle := randf() * TAU
		var elev := randf_range(0.2, 0.9)
		var dist := randf_range(40.0, 80.0)
		mi.position = Vector3(cos(angle) * dist, elev * 30.0 + 5.0, sin(angle) * dist)
		_scene_3d.add_child(mi)


func _build_hud() -> void:
	# Altitude — top-right
	_altitude_label = Label.new()
	_altitude_label.add_theme_font_size_override("font_size", 18)
	_altitude_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 0.9))
	_altitude_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_altitude_label.anchor_left = 1.0
	_altitude_label.anchor_right = 1.0
	_altitude_label.offset_left = -160
	_altitude_label.offset_right = -10
	_altitude_label.offset_top = 10
	_altitude_label.offset_bottom = 32
	add_child(_altitude_label)

	# Speed — below altitude
	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 18)
	_speed_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 0.9))
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.anchor_left = 1.0
	_speed_label.anchor_right = 1.0
	_speed_label.offset_left = -160
	_speed_label.offset_right = -10
	_speed_label.offset_top = 34
	_speed_label.offset_bottom = 56
	add_child(_speed_label)

	# Tilt indicator — center-top
	_tilt_indicator = Control.new()
	_tilt_indicator.set_script(_create_tilt_indicator_script())
	_tilt_indicator.anchor_left = 0.5
	_tilt_indicator.anchor_right = 0.5
	_tilt_indicator.offset_left = -50
	_tilt_indicator.offset_right = 50
	_tilt_indicator.offset_top = 8
	_tilt_indicator.offset_bottom = 42
	_tilt_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tilt_indicator)

	# Flashing "LANDING" label — center top
	_landing_label = Label.new()
	_landing_label.text = "LANDING"
	_landing_label.add_theme_font_size_override("font_size", 28)
	_landing_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_landing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_landing_label.anchor_left = 0.5
	_landing_label.anchor_right = 0.5
	_landing_label.offset_left = -100
	_landing_label.offset_right = 100
	_landing_label.offset_top = 50
	_landing_label.offset_bottom = 82
	add_child(_landing_label)
	_landing_flash_tween = create_tween()
	_landing_flash_tween.set_loops()
	_landing_flash_tween.tween_property(_landing_label, "modulate:a", 0.2, 0.5)
	_landing_flash_tween.tween_property(_landing_label, "modulate:a", 1.0, 0.5)

	# Directional tilt arrows — show which way to correct
	_left_arrow = Label.new()
	_left_arrow.text = "◄◄◄"
	_left_arrow.add_theme_font_size_override("font_size", 32)
	_left_arrow.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1, 0.8))
	_left_arrow.anchor_top = 0.5
	_left_arrow.anchor_bottom = 0.5
	_left_arrow.offset_left = 10
	_left_arrow.offset_top = -20
	_left_arrow.offset_bottom = 20
	_left_arrow.visible = false
	add_child(_left_arrow)

	_right_arrow = Label.new()
	_right_arrow.text = "►►►"
	_right_arrow.add_theme_font_size_override("font_size", 32)
	_right_arrow.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1, 0.8))
	_right_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_right_arrow.anchor_left = 1.0
	_right_arrow.anchor_right = 1.0
	_right_arrow.anchor_top = 0.5
	_right_arrow.anchor_bottom = 0.5
	_right_arrow.offset_left = -100
	_right_arrow.offset_right = -10
	_right_arrow.offset_top = -20
	_right_arrow.offset_bottom = 20
	_right_arrow.visible = false
	add_child(_right_arrow)


func _process(_delta: float) -> void:
	if not _active or not is_instance_valid(_rocket) or not is_instance_valid(_target):
		return

	var dist := _rocket.global_position.distance_to(_target.global_position)
	var rocket_vel := _rocket.linear_velocity
	# Tilt relative to target: 0 = tail pointing at target (correct landing)
	var dir_to_target := (_target.global_position - _rocket.global_position).angle()
	var ideal_rot := dir_to_target - PI / 2.0
	var rocket_rot := wrapf(_rocket.rotation - ideal_rot, -PI, PI)

	# Altitude mapping
	var alt_ratio := clampf(dist / _max_altitude, 0.0, 1.0)
	var alt_3d := alt_ratio * ALTITUDE_3D_MAX

	# Lateral offset
	var offset_2d := _rocket.global_position - _target.global_position
	var lx := clampf(offset_2d.x * LATERAL_SCALE, -GROUND_SIZE * 0.35, GROUND_SIZE * 0.35)
	var lz := clampf(-offset_2d.y * LATERAL_SCALE, -GROUND_SIZE * 0.35, GROUND_SIZE * 0.35)

	# Rocket position and rotation
	_rocket_sprite_3d.position = Vector3(lx, alt_3d + 0.3, lz)
	_rocket_sprite_3d.rotation = Vector3(0, PI, rocket_rot)

	# Camera tracks rocket smoothly — center on rocket X to avoid perspective skew
	var cam_h := alt_3d + 2.5
	var cam_back := 4.0 + alt_ratio * 2.0
	_camera_3d.position = Vector3(lx, cam_h, lz + cam_back)
	_camera_3d.look_at(_rocket_sprite_3d.position)

	# Mirror nearby hazards
	_update_hazard_sprites()

	# HUD updates
	_altitude_label.text = "ALT %d" % int(dist)

	var speed := rocket_vel.length()
	_speed_label.text = "SPD %d" % int(speed)
	if speed > _rocket.crashspeed:
		_speed_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	elif speed > _rocket.landingspeed:
		_speed_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	else:
		_speed_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))

	# Tilt indicator
	_tilt_indicator.set_meta("tilt", clampf(rocket_rot / TILT_DEATH_ANGLE, -1.0, 1.0))
	_tilt_indicator.set_meta("warn", absf(rocket_rot) > TILT_WARN_ANGLE)
	_tilt_indicator.set_meta("danger", absf(rocket_rot) > TILT_DEATH_ANGLE)
	_tilt_indicator.queue_redraw()

	# Directional arrows — show correction direction when tilted past warning
	if absf(rocket_rot) > TILT_WARN_ANGLE:
		_left_arrow.visible = rocket_rot > 0
		_right_arrow.visible = rocket_rot < 0
	else:
		_left_arrow.visible = false
		_right_arrow.visible = false


func _update_hazard_sprites() -> void:
	var all_hazards: Array[Node] = []
	for grp in ["martians", "asteroids"]:
		all_hazards.append_array(_rocket.get_tree().get_nodes_in_group(grp))

	var seen: Dictionary = {}
	for hazard in all_hazards:
		if not is_instance_valid(hazard) or not hazard is Node2D:
			continue
		var haz: Node2D = hazard
		if haz.global_position.distance_to(_target.global_position) > 300.0:
			continue
		var iid := haz.get_instance_id()
		seen[iid] = true

		var h_off := haz.global_position - _target.global_position
		var hx := clampf(h_off.x * LATERAL_SCALE, -GROUND_SIZE * 0.4, GROUND_SIZE * 0.4)
		var hz := clampf(-h_off.y * LATERAL_SCALE, -GROUND_SIZE * 0.4, GROUND_SIZE * 0.4)

		if iid in _hazard_sprites:
			var spr: Sprite3D = _hazard_sprites[iid]
			if is_instance_valid(spr):
				spr.position = Vector3(hx, 1.0, hz)
		else:
			var spr := Sprite3D.new()
			var found_tex := false
			for child in haz.get_children():
				if child is Sprite2D and child.texture:
					spr.texture = child.texture
					found_tex = true
					break
				elif child is AnimatedSprite2D and child.sprite_frames:
					var anim_name: String = child.animation
					if child.sprite_frames.has_animation(anim_name):
						var frame: int = child.frame
						spr.texture = child.sprite_frames.get_frame_texture(anim_name, frame)
						found_tex = true
					break
			if not found_tex:
				spr.queue_free()
				continue
			spr.pixel_size = 0.006
			spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			spr.position = Vector3(hx, 1.0, hz)
			_scene_3d.add_child(spr)
			_hazard_sprites[iid] = spr

	# Cleanup gone hazards
	var to_remove: Array = []
	for iid in _hazard_sprites:
		if iid not in seen:
			to_remove.append(iid)
	for iid in to_remove:
		if is_instance_valid(_hazard_sprites[iid]):
			_hazard_sprites[iid].queue_free()
		_hazard_sprites.erase(iid)


func _get_target_texture() -> Texture2D:
	if not is_instance_valid(_target):
		return null
	for child in _target.get_children():
		if child is Sprite2D and child.texture:
			return child.texture
	return null


func deactivate() -> void:
	_active = false
	if _landing_flash_tween:
		_landing_flash_tween.kill()
	queue_free()


func _create_tilt_indicator_script() -> GDScript:
	var src := """extends Control

func _draw():
	var tilt: float = get_meta("tilt") if has_meta("tilt") else 0.0
	var warn: bool = get_meta("warn") if has_meta("warn") else false
	var danger: bool = get_meta("danger") if has_meta("danger") else false
	var center := size / 2.0
	var hw := size.x * 0.4
	var color := Color(0.3, 1.0, 0.5, 0.8)
	if danger:
		color = Color(1.0, 0.2, 0.2, 1.0)
	elif warn:
		color = Color(1.0, 0.8, 0.2, 0.9)
	draw_line(Vector2(center.x - hw, center.y), Vector2(center.x + hw, center.y), Color(0.5, 0.5, 0.5, 0.4), 1.0)
	var a := tilt * deg_to_rad(35.0)
	var dx := cos(a) * hw
	var dy := sin(a) * hw
	draw_line(Vector2(center.x - dx, center.y - dy), Vector2(center.x + dx, center.y + dy), color, 2.0)
	draw_circle(center, 3.0, color)
"""
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	return script
