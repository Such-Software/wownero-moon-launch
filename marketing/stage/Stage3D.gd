extends Node3D
## Reusable 3D mascot stage for marketing clips. Loads a GLB (e.g. a Meshy.ai
## Cosmonaut Doge), auto-frames it with a camera + light, plays its animation,
## and shows a doge caption. Captured to video with marketing/lib/capture.sh.
##
## Everything is configured by env vars so one scene makes any mascot shot
## without editing code:
##   MK_GLB       res:// path to a .glb (empty -> a spinning placeholder box, so
##                the whole pipeline is testable before any GLB exists)
##   MK_ANIM      animation name to play (empty -> first animation in the GLB)
##   MK_CAPTION   doge caption text shown along the bottom
##   MK_BG        background color, e.g. "0.04,0.03,0.10" (rgb 0..1) or a hex
##   MK_CAM_DIST  absolute camera distance (empty -> auto-fit to the model)
##   MK_SPIN      turntable spin in degrees/sec (default 18; 0 = still)
##
## See marketing/README.md.

var _pivot: Node3D
var _spin_dps := 18.0


func _env(name: String, def: String = "") -> String:
	var v := OS.get_environment(name)
	return v if v != "" else def


func _ready() -> void:
	_spin_dps = float(_env("MK_SPIN", "18"))

	# --- environment + lighting ---
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _parse_color(_env("MK_BG", "0.04,0.03,0.10"))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.3
	add_child(key)

	# --- the model (or a placeholder) under a spinnable pivot at the origin ---
	_pivot = Node3D.new()
	add_child(_pivot)

	var model: Node3D = null
	var glb := _env("MK_GLB")
	if glb != "" and ResourceLoader.exists(glb):
		var packed := load(glb) as PackedScene
		if packed != null:
			model = packed.instantiate() as Node3D
	if model == null:
		model = _placeholder()
	_pivot.add_child(model)

	# center the model on the pivot and frame the camera to fit it
	var aabb := _merged_aabb(model)
	model.position -= aabb.get_center()
	_setup_camera(aabb.size)
	_play_animation(model, _env("MK_ANIM"))

	# --- caption overlay ---
	var caption := _env("MK_CAPTION")
	if caption != "":
		_add_caption(caption)


func _process(delta: float) -> void:
	if _pivot != null and _spin_dps != 0.0:
		_pivot.rotate_y(deg_to_rad(_spin_dps) * delta)


func _placeholder() -> Node3D:
	# doge-yellow rounded box so the stage renders something before any GLB.
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 1.4, 1.4)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.78, 0.16)
	mat.roughness = 0.5
	mi.material_override = mat
	return mi


func _merged_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in _all_nodes(root):
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var box := vi.get_aabb()
			# to the model-root's local space
			var t := (root as Node3D).global_transform.affine_inverse() * vi.global_transform
			box = t * box
			if first:
				out = box; first = false
			else:
				out = out.merge(box)
	if first:
		out = AABB(Vector3(-0.7, -0.7, -0.7), Vector3(1.4, 1.4, 1.4))
	return out


func _all_nodes(n: Node) -> Array:
	var arr := [n]
	for c in n.get_children():
		arr.append_array(_all_nodes(c))
	return arr


func _setup_camera(size: Vector3) -> void:
	var cam := Camera3D.new()
	var span := maxf(maxf(size.x, size.y), size.z)
	var dist_env := _env("MK_CAM_DIST")
	var dist := float(dist_env) if dist_env != "" else span * 1.7 + 1.0
	cam.position = Vector3(0, span * 0.12, dist)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true
	add_child(cam)


func _play_animation(model: Node, want: String) -> void:
	var ap: AnimationPlayer = null
	for n in _all_nodes(model):
		if n is AnimationPlayer:
			ap = n as AnimationPlayer
			break
	if ap == null:
		return
	var list := ap.get_animation_list()
	if list.is_empty():
		return
	var name := want
	if name == "" or not ap.has_animation(name):
		name = list[0]
	var anim := ap.get_animation(name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	ap.play(name)


func _add_caption(text: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -150
	label.offset_bottom = -40
	var font := load("res://fonts/Computer Speak v0.3.ttf")
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 56)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	layer.add_child(label)


func _parse_color(s: String) -> Color:
	if s.begins_with("#") or s.length() == 6:
		return Color.html(s)
	var parts := s.split(",")
	if parts.size() >= 3:
		return Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return Color(0.04, 0.03, 0.10)
