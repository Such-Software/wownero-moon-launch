extends Control
## Debug overlay — toggled with F3. Shows FPS, physics info, rocket state.
## Standalone widget: create with Control.new(), set_script(), add_child().

var _visible := false
var _rocket: Node = null


func _ready() -> void:
	visible = false
	await get_tree().process_frame
	_rocket = get_tree().get_first_node_in_group("rocket")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_visible = !_visible
		visible = _visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _visible:
		queue_redraw()


func _draw() -> void:
	if not _visible:
		return

	var font := ThemeDB.fallback_font
	if not font:
		return

	var lines: Array[String] = []
	lines.append("FPS: " + str(Engine.get_frames_per_second()))
	lines.append("Physics: " + str(Engine.physics_ticks_per_second) + " tps")

	if _rocket and is_instance_valid(_rocket):
		var vel := Vector2.ZERO
		if _rocket.has_method("get_linear_velocity"):
			vel = _rocket.get_linear_velocity()
		elif "linear_velocity" in _rocket:
			vel = _rocket.linear_velocity
		lines.append("Pos: " + str(Vector2i(_rocket.global_position)))
		lines.append("Vel: %.0f px/s" % vel.length())
		lines.append("Fuel: %.0f / %.0f" % [_rocket.fuel, _rocket.max_fuel])
	
	lines.append("Wallet: " + str(globalvar.wallet) + " WOW")
	lines.append("Level: " + str(globalvar.nowlevel))

	# Draw background
	var line_h := 15
	var bg_h := lines.size() * line_h + 8
	draw_rect(Rect2(0, 0, 200, bg_h), Color(0.0, 0.0, 0.0, 0.6))

	# Draw lines
	for i in range(lines.size()):
		draw_string(font, Vector2(6, 14 + i * line_h), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.0, 1.0, 0.0, 0.9))
