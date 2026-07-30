class_name TalkingPortrait
extends Control
## Lightweight runtime portrait. It can either draw a mouth over a 2D puppet or
## cycle pre-rendered procedural 3D visemes, avoiding a live 3D scene on mobile.

var portrait_texture: Texture2D = null
var mouth_anchor := Vector2(0.5, 0.65)
var mouth_width := 0.16
var mouth_height := 0.075
var mouth_color := Color(0.08, 0.045, 0.035)
var lip_color := Color(0.38, 0.18, 0.12)
var rest_curve := 1.0
var bottom_aligned := false
var talking_textures: Array[Texture2D] = []

var _talking := false
var _active := false
var _phase := 0.0
var _state_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_refresh_pivot)
	_refresh_pivot()
	set_process(true)
	queue_redraw()


func configure(texture: Texture2D, anchor: Vector2, width: float,
		height: float, mouth_fill: Color, lip: Color, curve := 1.0) -> void:
	portrait_texture = texture
	mouth_anchor = anchor
	mouth_width = width
	mouth_height = height
	mouth_color = mouth_fill
	lip_color = lip
	rest_curve = curve
	if is_inside_tree():
		queue_redraw()


func configure_visemes(rest_texture: Texture2D, textures: Array) -> void:
	portrait_texture = rest_texture
	talking_textures.clear()
	for texture in textures:
		if texture is Texture2D:
			talking_textures.append(texture)
	if is_inside_tree():
		queue_redraw()


func set_talking(talking: bool) -> void:
	if _talking == talking:
		return
	_talking = talking
	queue_redraw()


func set_bottom_aligned(aligned: bool) -> void:
	bottom_aligned = aligned
	queue_redraw()


func set_active(active: bool, animate := true) -> void:
	_active = active
	if _state_tween != null and _state_tween.is_valid():
		_state_tween.kill()
	var target_scale := Vector2(1.06, 1.06) if active else Vector2(0.92, 0.92)
	var target_color := Color.WHITE if active else Color(0.48, 0.52, 0.62, 0.72)
	z_index = 2 if active else 1
	if not animate or not is_inside_tree():
		scale = target_scale
		modulate = target_color
		return
	_state_tween = create_tween().set_parallel(true)
	_state_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_state_tween.tween_property(self, "scale", target_scale, 0.24)
	_state_tween.tween_property(self, "modulate", target_color, 0.24)


func _refresh_pivot() -> void:
	pivot_offset = size / 2.0


func _process(delta: float) -> void:
	_phase += delta
	rotation = sin(_phase * (2.7 if _active else 1.4)) * (0.012 if _active else 0.004)
	if _talking:
		queue_redraw()


func _draw() -> void:
	if portrait_texture == null:
		return
	var display_texture := portrait_texture
	if _talking and not talking_textures.is_empty():
		var frame_i := int(floor(_phase * 8.0)) % talking_textures.size()
		display_texture = talking_textures[frame_i]
	var side := minf(size.x, size.y)
	var portrait_position := Vector2((size.x - side) / 2.0, size.y - side if bottom_aligned else (size.y - side) / 2.0)
	var portrait_rect := Rect2(portrait_position, Vector2(side, side))
	draw_texture_rect(display_texture, portrait_rect, false)

	# A 3D frame already contains its modeled mouth.
	if not talking_textures.is_empty():
		return

	var center := portrait_rect.position + portrait_rect.size * mouth_anchor
	var width_px := portrait_rect.size.x * mouth_width
	if _talking:
		var openness := 0.3 + 0.7 * absf(sin(_phase * 10.0))
		var radii := Vector2(width_px * 0.5, portrait_rect.size.y * mouth_height * openness * 0.5)
		draw_colored_polygon(_ellipse_points(center, radii, 28), mouth_color)
		draw_polyline(_ellipse_outline(center, radii, 28), lip_color, maxf(2.0, side * 0.007), true)
		if openness > 0.62:
			var tongue_center := center + Vector2(0, radii.y * 0.45)
			var tongue_radii := Vector2(radii.x * 0.48, maxf(1.5, radii.y * 0.22))
			draw_colored_polygon(_ellipse_points(tongue_center, tongue_radii, 18), lip_color.lightened(0.42))
	else:
		var smile := PackedVector2Array()
		for i in range(19):
			var t := float(i) / 18.0
			var x := center.x + (t - 0.5) * width_px
			var y := center.y + sin(t * PI) * portrait_rect.size.y * 0.014 * rest_curve
			smile.append(Vector2(x, y))
		draw_polyline(smile, lip_color, maxf(2.0, side * 0.009), true)


func _ellipse_points(center: Vector2, radii: Vector2, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _ellipse_outline(center: Vector2, radii: Vector2, count: int) -> PackedVector2Array:
	var points := _ellipse_points(center, radii, count)
	if not points.is_empty():
		points.append(points[0])
	return points
