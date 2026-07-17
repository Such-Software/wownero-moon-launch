extends Node2D

# --- Action-gated Level 1 tutorial + coach marks (WP-B1) -----------------------
# Each step WAITS for the thing it teaches (thrust held, rotation turned, reverse
# tapped, slingshot achieved, Moon approached) instead of a fixed 4s timer. Message
# text adapts to globalvar.active_input_hint() across FOUR styles — KEYBOARD,
# GAMEPAD, TILT, TOUCH_JOYSTICK. Coach marks pulse the matching on-screen control
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

var _tut_active := false
var _tut_label: Label = null
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
		_start_tutorial()


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

	_tut_label = Label.new()
	_tut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tut_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tut_label.add_theme_font_size_override("font_size", 24)
	_tut_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_tut_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_tut_label.add_theme_constant_override("shadow_offset_x", 2)
	_tut_label.add_theme_constant_override("shadow_offset_y", 2)
	_tut_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tut_label.offset_top = 80
	_tut_label.offset_bottom = 120
	_label_host().add_child(_tut_label)

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
	if _rocket and is_instance_valid(_rocket):
		_prev_rot = _rocket.rotation
	var kind: int = STEP_ORDER[i]
	# The LAND message stays hidden until the Moon is close; keep it blank so it
	# doesn't linger on screen during the whole transit.
	if kind == Step.LAND and not _near_moon():
		_tut_label.text = ""
		_tut_label.modulate = Color(1, 1, 1, 0)
	else:
		_refresh_step_text()
		_tut_label.modulate = Color(1, 1, 1, 1)
		_apply_coach_marks()
	# Funnel: one event each time a step becomes active (i.e. on every advance).
	Analytics.event("tutorial_step", {"i": STEP_IDS[kind]})


func _advance() -> void:
	_enter_step(_step_i + 1)


func _process(delta):
	if not _tut_active:
		return
	if _tut_label == null or not is_instance_valid(_tut_label):
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
			if Input.is_action_pressed("thrust"):
				_hold_accum += delta
				progressed = true
				if _hold_accum >= THRUST_HOLD:
					_advance()
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
					_advance()
					return
			elif _step_elapsed >= SLINGSHOT_FALLBACK:
				# No rocket to measure turn against — bail out so we never lock.
				_advance()
				return
		Step.REVERSE:
			if Input.is_action_pressed("revthrust"):
				_hold_accum += delta
				progressed = true
				if _hold_accum >= REVERSE_HOLD:
					_advance()
					return
			else:
				_hold_accum = 0.0
		Step.SLINGSHOT:
			if _slingshot_hit or _step_elapsed >= SLINGSHOT_FALLBACK:
				_advance()
				return
		Step.LAND:
			# Reveal only once the Moon is close; then hold until landing mode.
			if _tut_label.text == "" and _near_moon():
				_refresh_step_text()
				_tut_label.modulate = Color(1, 1, 1, 1)
			if _landing_mode_on():
				_finish_tutorial()
				return

	# --- Waiting-step visuals (everything but the title beat) ---
	if kind != Step.TITLE and _tut_label.text != "":
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
	if _tut_label == null or not is_instance_valid(_tut_label):
		return
	_pulse_t = 0.0
	_tut_label.modulate.a = 1.0
	# Subtle horizontal shake to re-catch the eye.
	var base_x := _tut_label.position.x
	var t := create_tween()
	t.tween_property(_tut_label, "position:x", base_x + 6.0, 0.05)
	t.tween_property(_tut_label, "position:x", base_x - 6.0, 0.05)
	t.tween_property(_tut_label, "position:x", base_x, 0.05)


func _finish_tutorial() -> void:
	_tut_active = false
	_clear_coach_marks()
	if globalvar.control_scheme_changed.is_connected(_on_input_style_changed):
		globalvar.control_scheme_changed.disconnect(_on_input_style_changed)
	if Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.disconnect(_on_joy_changed)
	if _tut_label and is_instance_valid(_tut_label):
		var t := create_tween()
		t.tween_property(_tut_label, "modulate:a", 0.0, 0.6)
		t.tween_callback(_tut_label.queue_free)
	_tut_label = null


# --- Message text (input-style adaptive) ---------------------------------------

func _input_hint() -> int:
	## Active control-hint style. Prefer the shared WP-A1 helper; fall back to a
	## local derivation (platform + control_scheme) if it isn't present yet.
	if globalvar.has_method("active_input_hint"):
		return globalvar.active_input_hint()
	var os := OS.get_name()
	if os == "Android" or os == "iOS":
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
			return "Welcome, Pilot!"
		Step.THRUST:
			match hint:
				HINT_KEYBOARD: return "Press UP to thrust"
				HINT_GAMEPAD: return "Press Ⓐ / right trigger to thrust"
				_: return "Hold THRUST to fly up"   # TILT + TOUCH_JOYSTICK
		Step.ROTATE:
			match hint:
				HINT_KEYBOARD: return "LEFT / RIGHT to rotate"
				HINT_GAMEPAD: return "Left stick to rotate"
				HINT_TILT: return "Tilt phone LEFT / RIGHT to turn"
				_: return "Use the joystick to rotate"   # TOUCH_JOYSTICK
		Step.REVERSE:
			match hint:
				HINT_KEYBOARD: return "Press DOWN for reverse thrust"
				HINT_GAMEPAD: return "Press Ⓑ / left trigger for reverse"
				_: return "Tap REVERSE to slow your descent"   # TILT + TOUCH_JOYSTICK
		Step.SLINGSHOT:
			return "Slingshot! Swing around Earth — don't fly straight at the Moon"
		Step.LAND:
			return "Land slowly and upright on the Moon!"
	return ""


func _refresh_step_text() -> void:
	if _tut_label == null or not is_instance_valid(_tut_label):
		return
	_tut_label.text = _step_message(STEP_ORDER[_step_i])


func _rebuild_text() -> void:
	## Control style changed mid-tutorial — refresh copy + coach marks in place.
	if not _tut_active or _tut_label == null or not is_instance_valid(_tut_label):
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
		Step.REVERSE:
			if hint == HINT_TILT or hint == HINT_TOUCH_JOYSTICK:
				_set_coach("revthrust")
		Step.ROTATE:
			if hint == HINT_TOUCH_JOYSTICK:
				_set_coach("joystick")
			elif hint == HINT_TILT:
				_show_tilt_icon()


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


func _show_tilt_icon() -> void:
	## TILT rotate step has no button to pulse — show a small phone-tilt icon that
	## wobbles (rotation animated in _process) beneath the message.
	if _tilt_icon and is_instance_valid(_tilt_icon):
		return
	_tilt_icon = Label.new()
	_tilt_icon.text = "📱 ↔"
	_tilt_icon.add_theme_font_size_override("font_size", 30)
	_tilt_icon.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_tilt_icon.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_tilt_icon.add_theme_constant_override("shadow_offset_x", 2)
	_tilt_icon.add_theme_constant_override("shadow_offset_y", 2)
	_label_host().add_child(_tilt_icon)
	_tilt_icon.reset_size()
	var vw := get_viewport().get_visible_rect().size.x
	_tilt_icon.position = Vector2(vw * 0.5 - _tilt_icon.size.x * 0.5, 128)
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
