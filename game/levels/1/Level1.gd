extends Node2D

const UI_FONT := preload("res://fonts/Computer Speak v0.3.ttf")
const DOGE_TEXTURE := preload("res://art/characters/dialogue/spacedoge.svg")
const FirstFlightBriefingScene = preload("res://game/gui/onboarding/FirstFlightBriefing.gd")

# --- Action-gated Level 1 tutorial + coach marks (WP-B1) -----------------------
# Each step WAITS for the thing it teaches (thrust held, rotation turned, reverse
# tapped, slingshot achieved, Moon approached) instead of a fixed 4s timer. Message
# text adapts to globalvar.active_input_hint() across FIVE styles — KEYBOARD,
# GAMEPAD, TILT, TOUCH_JOYSTICK, FULL_TILT. Coach marks pulse the matching on-screen control
# on touch styles; desktop styles rely on the text. Fallback timers on every
# waiting step guarantee the sequence can never soft-lock.

# Step kinds (drive advance conditions + message selection).
enum Step { TITLE, THRUST, ROTATE, REVERSE, SLINGSHOT, LAND }

# Ordered sequence actually played. Step 6 ("Don't fly straight at it") from the
# spec table is merged into SLINGSHOT's hold text, so it isn't a separate step.
const STEP_ORDER: Array[int] = [Step.TITLE, Step.THRUST, Step.ROTATE, Step.REVERSE, Step.SLINGSHOT, Step.LAND]

# Analytics step numbers — match the SPEC table (1,2,3,4,5,7) so the funnel lines
# up with the design doc. 6 is intentionally absent (merged into 5).
const STEP_IDS := {
	Step.TITLE: 1,
	Step.THRUST: 2,
	Step.ROTATE: 3,
	Step.REVERSE: 4,
	Step.SLINGSHOT: 5,
	Step.LAND: 7,
}

# Advance thresholds / timings (seconds unless noted).
const TITLE_HOLD := 2.0           # step 1: title beat
const THRUST_HOLD := 0.5          # step 2: thrust held this long
const ROTATE_RAD := 0.5           # step 3: cumulative turn (radians)
const REVERSE_HOLD := 0.3         # step 4: reverse held this long
const SLINGSHOT_FALLBACK := 20.0  # step 5: advance anyway after this (never lock)
const LAND_SHOW_DIST := 600.0     # step 7: reveal once this close to the Moon (px)
const STALL_NUDGE_AFTER := 10.0   # re-show + shake after this much idle on a waiting step
const PULSE_SPEED := 3.0          # waiting-message gentle alpha pulse (rad/s)
const ROT_NOISE := 0.0008         # ignore per-frame rotation below this as numeric noise

# Local mirror of globalvar.InputHint so control text still resolves even if the
# WP-A1 helper isn't present yet. Values MUST match globalvar.InputHint.
const HINT_KEYBOARD := 0
const HINT_GAMEPAD := 1
const HINT_TILT := 2
const HINT_TOUCH_JOYSTICK := 3
const HINT_FULL_TILT := 4

var _tut_active := false
var _tut_panel: PanelContainer = null
var _tut_kicker: Label = null
var _tut_label: Label = null
var _tut_detail: Label = null
var _coach_portrait: TalkingPortrait = null
var _tilt_icon: Label = null      # step 3 TILT-style phone-wobble coach mark
var _ui: CanvasLayer = null       # MobileUI overlay (hosts labels + highlight())
var _rocket: Node2D = null

var _step_i := -1                 # index into STEP_ORDER
var _step_elapsed := 0.0          # seconds spent in the current step
var _hold_accum := 0.0            # qualifying-input hold time (thrust/reverse)
var _rot_accum := 0.0             # cumulative |turn| for the rotate step
var _prev_rot := 0.0
var _idle_time := 0.0             # since last qualifying progress (drives stall nudge)
var _pulse_t := 0.0
var _slingshot_hit := false
var _coach_btn := ""              # currently highlighted MobileUI control (if any)
var _advance_queued := false
var _coach_talk_remaining := 0.0


func _ready():
	globalvar.nowlevel = 1
	var space = get_world_2d().get_space()
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, 0)
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)
	if OS.get_environment("SML_RACE") != "":
		globalvar.race_mode = true   # dev/test hook for a direct scene load
	if globalvar.race_mode:
		# Spawn the CPU rival once the player rocket is in the tree (deferred).
		RaceController.call_deferred("setup", self)
	elif not globalvar.tutorial_shown:
		if _should_show_first_flight_briefing():
			_start_first_flight_briefing()
		else:
			_start_tutorial()


func _should_show_first_flight_briefing() -> bool:
	if globalvar.first_flight_briefing_shown:
		return false
	# Blocking overlays must never stall bots, simulations or unattended capture.
	var argv := OS.get_cmdline_args()
	return not ("--capture" in argv or "--autopilot" in argv or "--sim" in argv)


func _start_first_flight_briefing() -> void:
	_ui = get_node_or_null("CanvasLayer")
	if _ui == null:
		_ui = get_node_or_null("UIOverLay")
	if _ui == null:
		# Bare simulation/training scenes do not carry a HUD host.
		_start_tutorial()
		return
	var briefing := FirstFlightBriefingScene.new()
	briefing.ready_to_launch.connect(func() -> void:
		globalvar.first_flight_briefing_shown = true
		globalvar.save_game()
		_start_tutorial()
	)
	_ui.add_child(briefing)


func _start_tutorial() -> void:
	# Tutorial prompts display now; the flag is only persisted when Level 1 is
	# actually completed (Victory.gd), so an abandoned first run still re-teaches.
	# Capture/headless gating (SPEC convention #2, Menu.gd:1172-1173): never show
	# tutorial UI during video/autopilot/sim runs, unless SML_SHOW_HINTS=1 asks
	# for it (promo takes that deliberately want the coaching on screen).
	var argv := OS.get_cmdline_args()
	if ("--capture" in argv or "--autopilot" in argv or "--sim" in argv) and OS.get_environment("SML_SHOW_HINTS") != "1":
		return

	_ui = get_node_or_null("CanvasLayer")
	if _ui == null:
		_ui = get_node_or_null("UIOverLay")
	_rocket = get_tree().get_first_node_in_group("rocket") as Node2D
	if _rocket:
		_prev_rot = _rocket.rotation

	_build_tutorial_card()

	# Rebuild message text live if the control style changes mid-tutorial — a
	# scheme toggle (WP-A2) or a gamepad hotplug both flip active_input_hint().
	if not globalvar.control_scheme_changed.is_connected(_on_input_style_changed):
		globalvar.control_scheme_changed.connect(_on_input_style_changed)
	if not Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.connect(_on_joy_changed)

	# Slingshot hook: rocket broadcasts a `slingshot_achieved` signal when the
	# gold "SLINGSHOT! +N" is awarded (cross-file need). If the signal isn't
	# present yet, step 5 relies purely on its 20s fallback — never locks.
	if _rocket and _rocket.has_signal("slingshot_achieved"):
		_rocket.connect("slingshot_achieved", _on_slingshot)

	_tut_active = true
	_enter_step(0)


func _build_tutorial_card() -> void:
	_tut_panel = PanelContainer.new()
	_tut_panel.name = "FlightCoach"
	_label_host().add_child(_tut_panel)
	_layout_tutorial_card()
	get_viewport().size_changed.connect(_layout_tutorial_card)
	_tut_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tut_panel.add_theme_stylebox_override("panel", _tutorial_panel_style())

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tut_panel.add_child(content)

	_coach_portrait = TalkingPortrait.new()
	_coach_portrait.name = "CoachPortrait"
	_coach_portrait.custom_minimum_size = Vector2(82, 82)
	_coach_portrait.configure(
		DOGE_TEXTURE,
		Vector2(0.5, 0.653),
		0.155,
		0.08,
		Color(0.12, 0.065, 0.045),
		Color(0.48, 0.24, 0.15),
		1.0
	)
	_coach_portrait.set_active(true, false)
	content.add_child(_coach_portrait)

	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 2)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(copy)

	_tut_kicker = Label.new()
	_tut_kicker.name = "Step"
	_tut_kicker.add_theme_font_override("font", UI_FONT)
	_tut_kicker.add_theme_font_size_override("font_size", 11)
	_tut_kicker.add_theme_color_override("font_color", Color(1.0, 0.81, 0.31))
	_tut_kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(_tut_kicker)

	_tut_label = Label.new()
	_tut_label.name = "Instruction"
	_tut_label.add_theme_font_size_override("font_size", 22)
	_tut_label.add_theme_color_override("font_color", Color(0.52, 1.0, 0.68))
	_tut_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_tut_label.add_theme_constant_override("shadow_offset_x", 2)
	_tut_label.add_theme_constant_override("shadow_offset_y", 2)
	_tut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tut_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tut_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(_tut_label)

	_tut_detail = Label.new()
	_tut_detail.name = "Detail"
	_tut_detail.add_theme_font_size_override("font_size", 12)
	_tut_detail.add_theme_color_override("font_color", Color(0.7, 0.76, 0.88))
	_tut_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(_tut_detail)


func _layout_tutorial_card() -> void:
	if _tut_panel == null or not is_instance_valid(_tut_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	var width := minf(clampf(vp.x * 0.72, 460.0, 760.0), maxf(280.0, vp.x - 32.0))
	# Keep the top-right time and velocity instruments visible while coaching.
	_tut_panel.position = Vector2(16.0, 76.0)
	_tut_panel.size = Vector2(width, 108.0)


func _tutorial_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.018, 0.075, 0.93)
	style.border_color = Color(0.48, 0.84, 1.0, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0.3, 0.72, 1.0, 0.24)
	style.shadow_size = 10
	return style


func _label_host() -> Node:
	## CanvasLayer overlay when available (screen space), else fall back to self.
	if _ui != null and is_instance_valid(_ui):
		return _ui
	return self


# --- Step engine ---------------------------------------------------------------

func _enter_step(i: int) -> void:
	_clear_coach_marks()
	if i >= STEP_ORDER.size():
		_finish_tutorial()
		return
	_step_i = i
	_step_elapsed = 0.0
	_hold_accum = 0.0
	_rot_accum = 0.0
	_idle_time = 0.0
	_pulse_t = 0.0
	_advance_queued = false
	_coach_talk_remaining = 1.35
	if _coach_portrait != null:
		_coach_portrait.set_talking(true)
	if _rocket and is_instance_valid(_rocket):
		_prev_rot = _rocket.rotation
	var kind: int = STEP_ORDER[i]
	# The LAND message stays hidden until the Moon is close; keep it blank so it
	# doesn't linger on screen during the whole transit.
	if kind == Step.LAND and not _near_moon():
		_tut_label.text = ""
		_tut_panel.visible = false
	else:
		_tut_panel.visible = true
		_refresh_step_text()
		_tut_panel.modulate = Color.WHITE
		_apply_coach_marks()
	# Funnel: one event each time a step becomes active (i.e. on every advance).
	Analytics.event("tutorial_step", {"i": STEP_IDS[kind]})


func _advance() -> void:
	_enter_step(_step_i + 1)


func _complete_step(kind: int) -> void:
	if _advance_queued:
		return
	_advance_queued = true
	_clear_coach_marks()
	if _coach_portrait != null:
		_coach_portrait.set_talking(false)
	_tut_kicker.text = "FLIGHT COACH  //  CONFIRMED"
	_tut_label.text = _step_confirmation(kind)
	_tut_label.modulate = Color.WHITE
	_tut_detail.text = "Nice work. Next callout incoming."
	var timer := get_tree().create_timer(0.62)
	timer.timeout.connect(func() -> void:
		if _tut_active and _advance_queued:
			_advance()
	)


func _process(delta):
	if not _tut_active:
		return
	if _tut_label == null or not is_instance_valid(_tut_label):
		return
	if _coach_talk_remaining > 0.0:
		_coach_talk_remaining -= delta
		if _coach_talk_remaining <= 0.0 and _coach_portrait != null:
			_coach_portrait.set_talking(false)
	if _advance_queued:
		return
	# Rocket may spawn deferred (or be replaced) — re-acquire if we lost it.
	if _rocket == null or not is_instance_valid(_rocket):
		_rocket = get_tree().get_first_node_in_group("rocket") as Node2D
		if _rocket:
			_prev_rot = _rocket.rotation

	_step_elapsed += delta
	_pulse_t += delta

	var kind: int = STEP_ORDER[_step_i]
	var progressed := false   # did the taught input make progress this frame?

	match kind:
		Step.TITLE:
			if _step_elapsed >= TITLE_HOLD:
				_advance()
				return
		Step.THRUST:
			if _tutorial_thrust_held():
				_hold_accum += delta
				progressed = true
				if _hold_accum >= THRUST_HOLD:
					_complete_step(kind)
					return
			else:
				_hold_accum = 0.0
		Step.ROTATE:
			if _rocket and is_instance_valid(_rocket):
				var turned := absf(angle_difference(_prev_rot, _rocket.rotation))
				_prev_rot = _rocket.rotation
				if turned > ROT_NOISE:
					_rot_accum += turned
					progressed = true
				if _rot_accum >= ROTATE_RAD:
					_complete_step(kind)
					return
			elif _step_elapsed >= SLINGSHOT_FALLBACK:
				# No rocket to measure turn against — bail out so we never lock.
				_advance()
				return
		Step.REVERSE:
			if _tutorial_reverse_held():
				_hold_accum += delta
				progressed = true
				if _hold_accum >= REVERSE_HOLD:
					_complete_step(kind)
					return
			else:
				_hold_accum = 0.0
		Step.SLINGSHOT:
			if _slingshot_hit or _step_elapsed >= SLINGSHOT_FALLBACK:
				_complete_step(kind)
				return
		Step.LAND:
			# Reveal only once the Moon is close; then hold until landing mode.
			if _tut_label.text == "" and _near_moon():
				_tut_panel.visible = true
				_refresh_step_text()
				_tut_panel.modulate = Color.WHITE
				_coach_talk_remaining = 1.35
				if _coach_portrait != null:
					_coach_portrait.set_talking(true)
			if _landing_mode_on():
				_finish_tutorial()
				return

	# --- Waiting-step visuals (everything but the title beat) ---
	if kind != Step.TITLE and _tut_panel.visible:
		# Gentle alpha pulse instead of a fade-out — the message keeps breathing
		# while it waits for the player.
		_tut_label.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * sin(_pulse_t * PULSE_SPEED))
		# Stall nudge on the input-teaching steps: if no qualifying input for a
		# while, re-show at full opacity with a subtle shake.
		if kind == Step.THRUST or kind == Step.ROTATE or kind == Step.REVERSE:
			if progressed:
				_idle_time = 0.0
			else:
				_idle_time += delta
				if _idle_time >= STALL_NUDGE_AFTER:
					_idle_time = 0.0
					_stall_nudge()

	# Wobble the TILT phone-tilt coach-mark icon, if shown.
	if _tilt_icon and is_instance_valid(_tilt_icon):
		_tilt_icon.rotation = 0.25 * sin(_pulse_t * 4.0)


func _stall_nudge() -> void:
	if _tut_panel == null or not is_instance_valid(_tut_panel):
		return
	_pulse_t = 0.0
	_tut_label.modulate.a = 1.0
	_coach_talk_remaining = 1.1
	if _coach_portrait != null:
		_coach_portrait.set_talking(true)
	# Subtle horizontal shake to re-catch the eye.
	var base_x := _tut_panel.position.x
	var t := create_tween()
	t.tween_property(_tut_panel, "position:x", base_x + 6.0, 0.05)
	t.tween_property(_tut_panel, "position:x", base_x - 6.0, 0.05)
	t.tween_property(_tut_panel, "position:x", base_x, 0.05)


func _finish_tutorial() -> void:
	_tut_active = false
	_clear_coach_marks()
	if globalvar.control_scheme_changed.is_connected(_on_input_style_changed):
		globalvar.control_scheme_changed.disconnect(_on_input_style_changed)
	if Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.disconnect(_on_joy_changed)
	if _coach_portrait != null:
		_coach_portrait.set_talking(false)
	if _tut_panel and is_instance_valid(_tut_panel):
		var t := create_tween()
		t.tween_property(_tut_panel, "modulate:a", 0.0, 0.6)
		t.tween_callback(_tut_panel.queue_free)
	_tut_panel = null
	_tut_kicker = null
	_tut_label = null
	_tut_detail = null
	_coach_portrait = null


# --- Message text (input-style adaptive) ---------------------------------------

func _input_hint() -> int:
	## Active control-hint style. Prefer the shared WP-A1 helper; fall back to a
	## local derivation (platform + control_scheme) if it isn't present yet.
	if globalvar.has_method("active_input_hint"):
		return globalvar.active_input_hint()
	var os := OS.get_name()
	if os == "Android" or os == "iOS":
		if globalvar.control_scheme == globalvar.ControlScheme.FULL_TILT:
			return HINT_FULL_TILT
		if globalvar.control_scheme == globalvar.ControlScheme.JOYSTICK:
			return HINT_TOUCH_JOYSTICK
		return HINT_TILT
	if globalvar.get("desktop_control") == 1:
		return HINT_GAMEPAD
	return HINT_KEYBOARD


func _step_message(kind: int) -> String:
	var hint := _input_hint()
	match kind:
		Step.TITLE:
			return "Your turn, Pilot."
		Step.THRUST:
			match hint:
				HINT_KEYBOARD: return "Press UP to thrust"
				HINT_GAMEPAD: return "Press Ⓐ / right trigger to thrust"
				HINT_FULL_TILT: return "Pitch phone FORWARD to thrust"
				_: return "Hold THRUST to fly up"   # TILT + TOUCH_JOYSTICK
		Step.ROTATE:
			match hint:
				HINT_KEYBOARD: return "LEFT / RIGHT to rotate"
				HINT_GAMEPAD: return "Left stick to rotate"
				HINT_TILT: return "Tilt phone LEFT / RIGHT to turn"
				HINT_FULL_TILT: return "Roll phone LEFT / RIGHT to turn"
				_: return "Use the joystick to rotate"   # TOUCH_JOYSTICK
		Step.REVERSE:
			match hint:
				HINT_KEYBOARD: return "Press DOWN for reverse thrust"
				HINT_GAMEPAD: return "Press Ⓑ / left trigger for reverse"
				HINT_FULL_TILT: return "Pitch phone BACK to brake"
				_: return "Tap REVERSE to slow your descent"   # TILT + TOUCH_JOYSTICK
		Step.SLINGSHOT:
			return "Swing wide around Earth — let gravity bend your path"
		Step.LAND:
			return "Land slowly and upright on the Moon!"
	return ""


func _step_detail(kind: int) -> String:
	match kind:
		Step.TITLE:
			return "Training flight: Earth → Moon"
		Step.THRUST:
			return "Hold steady until thrust comes online."
		Step.ROTATE:
			return "Small corrections beat sharp turns."
		Step.REVERSE:
			return "Reverse thrust is your brake."
		Step.SLINGSHOT:
			return "Build speed beside Earth; don't point straight at the Moon."
		Step.LAND:
			return "Safe touchdown: slow, feet-first, upright."
	return ""


func _step_confirmation(kind: int) -> String:
	match kind:
		Step.THRUST:
			return "THRUST ONLINE  ✓"
		Step.ROTATE:
			return "STEERING CONFIRMED  ✓"
		Step.REVERSE:
			return "BRAKES ONLINE  ✓"
		Step.SLINGSHOT:
			return "TRAJECTORY LOCKED  ✓"
	return "CONTROL CONFIRMED  ✓"


func _refresh_step_text() -> void:
	if _tut_label == null or not is_instance_valid(_tut_label):
		return
	var kind: int = STEP_ORDER[_step_i]
	_tut_kicker.text = "FLIGHT COACH  //  STEP %02d / %02d" % [_step_i + 1, STEP_ORDER.size()]
	_tut_label.text = _step_message(kind)
	_tut_detail.text = _step_detail(kind)


func _rebuild_text() -> void:
	## Control style changed mid-tutorial — refresh copy + coach marks in place.
	if not _tut_active or _advance_queued or _tut_label == null or not is_instance_valid(_tut_label):
		return
	var kind: int = STEP_ORDER[_step_i]
	# Leave the LAND step blank if it hasn't been revealed yet.
	if kind == Step.LAND and _tut_label.text == "":
		return
	_refresh_step_text()
	_apply_coach_marks()


func _on_input_style_changed() -> void:
	_rebuild_text()


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_rebuild_text()


func _on_slingshot(_speed_gain := 0.0) -> void:
	_slingshot_hit = true


func _tutorial_thrust_held() -> bool:
	## Full Tilt drives thrust from the rocket's calibrated pitch state rather than
	## an InputMap action, so the coach must observe the same source as gameplay.
	if _input_hint() == HINT_FULL_TILT:
		return _rocket != null and is_instance_valid(_rocket) and bool(_rocket.get("_fulltilt_thrust"))
	return Input.is_action_pressed("thrust")


func _tutorial_reverse_held() -> bool:
	if _input_hint() == HINT_FULL_TILT:
		return _rocket != null and is_instance_valid(_rocket) and bool(_rocket.get("_fulltilt_reverse"))
	return Input.is_action_pressed("revthrust")


# --- Coach marks ---------------------------------------------------------------

func _apply_coach_marks() -> void:
	## Highlight the on-screen control the current step teaches — touch styles only.
	## KEYBOARD / GAMEPAD desktop styles have no on-screen control, so the text
	## carries the instruction and no highlight is applied.
	_clear_coach_marks()
	if not _tut_active:
		return
	var kind: int = STEP_ORDER[_step_i]
	var hint := _input_hint()
	match kind:
		Step.THRUST:
			if hint == HINT_TILT or hint == HINT_TOUCH_JOYSTICK:
				_set_coach("thrust")
			elif hint == HINT_FULL_TILT:
				_show_tilt_icon("forward")
		Step.REVERSE:
			if hint == HINT_TILT or hint == HINT_TOUCH_JOYSTICK:
				_set_coach("revthrust")
			elif hint == HINT_FULL_TILT:
				_show_tilt_icon("back")
		Step.ROTATE:
			if hint == HINT_TOUCH_JOYSTICK:
				_set_coach("joystick")
			elif hint == HINT_TILT or hint == HINT_FULL_TILT:
				_show_tilt_icon("side")


func _set_coach(btn: String) -> void:
	_coach_btn = btn
	if _ui and is_instance_valid(_ui) and _ui.has_method("highlight"):
		_ui.highlight(btn, true)


func _clear_coach_marks() -> void:
	if _coach_btn != "" and _ui and is_instance_valid(_ui) and _ui.has_method("highlight"):
		_ui.highlight(_coach_btn, false)
	_coach_btn = ""
	if _tilt_icon and is_instance_valid(_tilt_icon):
		_tilt_icon.queue_free()
	_tilt_icon = null


func _show_tilt_icon(motion := "side") -> void:
	## TILT rotate step has no button to pulse — show a small phone-tilt icon that
	## wobbles (rotation animated in _process) beneath the message.
	if _tilt_icon and is_instance_valid(_tilt_icon):
		return
	_tilt_icon = Label.new()
	match motion:
		"forward": _tilt_icon.text = "📱  ⇧"
		"back": _tilt_icon.text = "📱  ⇩"
		_: _tilt_icon.text = "📱  ↔"
	_tilt_icon.add_theme_font_size_override("font_size", 30)
	_tilt_icon.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_tilt_icon.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_tilt_icon.add_theme_constant_override("shadow_offset_x", 2)
	_tilt_icon.add_theme_constant_override("shadow_offset_y", 2)
	_label_host().add_child(_tilt_icon)
	_tilt_icon.reset_size()
	var vw := get_viewport().get_visible_rect().size.x
	_tilt_icon.position = Vector2(vw * 0.5 - _tilt_icon.size.x * 0.5, 194)
	_tilt_icon.pivot_offset = _tilt_icon.size * 0.5


# --- Rocket state helpers ------------------------------------------------------

func _near_moon() -> bool:
	if _rocket == null or not is_instance_valid(_rocket):
		return false
	var tgt = _rocket.get("target")
	if tgt == null or not is_instance_valid(tgt):
		return false
	return _rocket.global_position.distance_to(tgt.global_position) <= LAND_SHOW_DIST


func _landing_mode_on() -> bool:
	if _rocket == null or not is_instance_valid(_rocket):
		return false
	return bool(_rocket.get("_landing_mode_active"))
