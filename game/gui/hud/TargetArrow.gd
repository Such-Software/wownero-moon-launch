extends Control
## Off-screen target arrow (WP-B2).
##
## Standalone HUD widget: MobileUI creates it with Control.new() + set_script(),
## full-rect on the HUD CanvasLayer (see MobileUI._setup_hud). It finds the player
## rocket via the "rocket" group and reads the SAME target the death forensics /
## proximity beeps use (rocket.target plus any unvisited waypoint bodies — the
## nearest one, mirroring the beep logic at rocket.gd:491-499).
##
## Each frame: if that target is OFF-screen it draws a thin, ~60%-alpha chevron at
## the screen edge pointing toward it, with a distance label ("MOON 1240", rounded
## to 10s). On-screen -> nothing. It fades out entirely while 3D landing mode is
## active (rocket._landing_mode_active) so it never fights the landing overlay.
##
## Deliberately drawn as a semi-transparent vector chevron + text, NOT a sprite,
## so it reads as guidance UI and never as a gameplay object.

# Style — thin, translucent, target-accent-tinted.
const BASE_ALPHA := 0.6           # spec: ~60% alpha
const EDGE_PAD := 46.0            # keep the chevron this far inside the screen edge
const CHEV_LEN := 15.0           # arrowhead reach in front of the anchor
const CHEV_SPREAD := 12.0        # half-height of the chevron arms
const CHEV_WIDTH := 3.0          # stroke width (thin — not a solid object)
const LABEL_SIZE := 13
const LABEL_GAP := 24.0          # how far back toward center the label sits
const FADE_TIME := 0.3           # landing-mode fade in/out seconds
const DEFAULT_ACCENT := Color(0.55, 0.8, 1.0)  # fallback when a target has no sprite

var _rocket: Node = null
var _fade: float = 1.0                       # 1 = shown, 0 = fully faded (landing mode)
var _accent_cache: Dictionary = {}           # target instance_id -> Color


func _ready() -> void:
	# Let the scene tree finish building, then locate the player rocket (same
	# pattern as FuelBar.gd). Re-acquired lazily in _process if it goes invalid.
	await get_tree().process_frame
	_rocket = _find_player_rocket()


func _process(delta: float) -> void:
	if not _rocket or not is_instance_valid(_rocket):
		_rocket = _find_player_rocket()
	# Ease the landing-mode fade so the arrow melts away instead of popping.
	var want_fade := 1.0
	if _rocket and is_instance_valid(_rocket) and ("_landing_mode_active" in _rocket) \
			and _rocket._landing_mode_active:
		want_fade = 0.0
	_fade = move_toward(_fade, want_fade, delta / FADE_TIME)
	queue_redraw()


func _draw() -> void:
	if _fade <= 0.01:
		return
	if not _rocket or not is_instance_valid(_rocket):
		return
	# Once landed there's no destination to point at.
	if ("flagplaced" in _rocket) and _rocket.flagplaced:
		return
	var target := _current_target()
	if not target or not is_instance_valid(target):
		return

	var vis := get_viewport().get_visible_rect()
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * target.global_position

	# On-screen -> hide (nothing to draw).
	if vis.has_point(screen_pos):
		return

	var center := vis.get_center()
	var to_t := screen_pos - center
	if to_t.length() < 0.001:
		return
	var dir := to_t.normalized()

	# Clamp the anchor to the padded screen rectangle along the target direction.
	var half := vis.size * 0.5 - Vector2(EDGE_PAD, EDGE_PAD)
	half.x = maxf(half.x, 0.0)
	half.y = maxf(half.y, 0.0)
	var tx := INF
	if absf(dir.x) > 0.0001:
		tx = half.x / absf(dir.x)
	var ty := INF
	if absf(dir.y) > 0.0001:
		ty = half.y / absf(dir.y)
	var t := minf(tx, ty)
	var anchor := center + dir * t

	var alpha := BASE_ALPHA * _fade
	var accent := _target_accent(target)
	var stroke := Color(accent.r, accent.g, accent.b, alpha)

	# Chevron: an open "^" pointing along dir (two thin strokes) — reads as a
	# direction cue, not a filled gameplay shape.
	var ang := dir.angle()
	var tip := anchor + Vector2(CHEV_LEN, 0.0).rotated(ang)
	var arm_a := anchor + Vector2(-CHEV_LEN * 0.2, -CHEV_SPREAD).rotated(ang)
	var arm_b := anchor + Vector2(-CHEV_LEN * 0.2, CHEV_SPREAD).rotated(ang)
	draw_polyline(PackedVector2Array([arm_a, tip, arm_b]), stroke, CHEV_WIDTH, true)

	# Distance label — pull back toward center so it stays on-screen at the edge.
	var font := ThemeDB.fallback_font
	if not font:
		return
	var dist: float = _rocket.global_position.distance_to(target.global_position)
	var dist_10 := int(round(dist / 10.0)) * 10
	var label := "%s %d" % [_target_name(target), dist_10]
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var label_center := anchor - dir * LABEL_GAP
	var text_pos := label_center - text_size * 0.5 + Vector2(0.0, text_size.y * 0.5)
	# Shadow first, then accent text — matches the tutorial/HUD label styling.
	draw_string(font, text_pos + Vector2(1.0, 1.0), label, HORIZONTAL_ALIGNMENT_LEFT,
		-1, LABEL_SIZE, Color(0.0, 0.0, 0.0, alpha * 0.9))
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT,
		-1, LABEL_SIZE, Color(accent.r, accent.g, accent.b, minf(alpha + 0.2, 1.0)))


# --- Target resolution -------------------------------------------------------

func _find_player_rocket() -> Node:
	# Prefer the human-controlled rocket; in race mode the AI rival also joins the
	# "rocket" group (rocket.gd:148) but must not steal the arrow.
	for r in get_tree().get_nodes_in_group("rocket"):
		if is_instance_valid(r) and ("ai_controlled" in r) and not r.ai_controlled:
			return r
	return get_tree().get_first_node_in_group("rocket")


func _current_target() -> Node2D:
	## Same target the beeps track: rocket.target, but if the level has waypoints
	## (L5+/wormholes) point at the nearest UNVISITED one first so the arrow follows
	## checkpoint order and survives a mid-level target swap.
	if not _rocket or not is_instance_valid(_rocket):
		return null
	var best: Node2D = null
	var best_d := INF
	var t = _rocket.target
	if t != null and is_instance_valid(t):
		best = t
		best_d = _rocket.global_position.distance_to(t.global_position)
	if "_waypoint_bodies" in _rocket:
		var visited: Dictionary = {}
		if "_visited_waypoints" in _rocket:
			visited = _rocket._visited_waypoints
		for wp in _rocket._waypoint_bodies:
			if not is_instance_valid(wp):
				continue
			if visited.has(wp.get_instance_id()):
				continue
			var d: float = _rocket.global_position.distance_to(wp.global_position)
			if d < best_d:
				best_d = d
				best = wp
	return best


func _target_name(t: Node2D) -> String:
	return String(t.name).to_upper()


func _target_accent(t: Node2D) -> Color:
	## The level-target accent color — sampled once from the target's sprite (same
	## trick LandingMode uses) so Moon reads grey, Mars red, etc. Cached per target.
	var id := t.get_instance_id()
	if _accent_cache.has(id):
		return _accent_cache[id]
	var col := DEFAULT_ACCENT
	for child in t.get_children():
		if child is Sprite2D and child.texture:
			var img: Image = child.texture.get_image()
			if img:
				img.resize(4, 4)
				var r := 0.0
				var g := 0.0
				var b := 0.0
				var n := 0
				for py in 4:
					for px in 4:
						var c := img.get_pixel(px, py)
						# Skip transparent border pixels so the planet's true color
						# isn't washed toward black (matches LandingMode).
						if c.a > 0.1:
							r += c.r
							g += c.g
							b += c.b
							n += 1
				if n > 0:
					col = Color(r / n, g / n, b / n)
					# Lift toward white a touch so the thin stroke stays legible on
					# dark space without looking like the planet itself.
					col = col.lerp(Color.WHITE, 0.3)
			break
	_accent_cache[id] = col
	return col
