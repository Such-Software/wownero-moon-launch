extends Node
## Heuristic autopilot — play-tester + promo B-roll pilot.
##
## NOT machine learning: a PD-style controller that flies toward the landing
## target while RESPECTING gravity — it arcs around non-target bodies rather
## than charging straight in (a straight line into Earth is the #1 cause of
## death in the live telemetry, so the bot must slingshot like a human).
##
## Desktop only by design: it drives the same inputs a keyboard player uses
## (ui_left / ui_right / thrust / revthrust), so it reuses rocket.gd's real
## physics with ZERO changes to the rocket — mobile/production are untouched.
##
## Enable:
##   - press F8 in a debug build to toggle, or
##   - launch with  --autopilot  (for headless balance sims / Movie Maker capture)
##
## Status: v1 — flies toward target + avoids other gravity wells. Landing
## (tail-first, upright, under landing speed) still needs on-device tuning.

var active := false
var _rocket: RigidBody2D = null

# --- tuning knobs (iterate these while watching it fly) ---
const SEEK_SPEED := 170.0        # cruise speed toward target (px/s)
const APPROACH_RADIUS := 240.0   # begin easing down within this distance
const LAND_SPEED := 26.0         # desired speed once near the pad
const ANGLE_TOLERANCE := 0.18    # rad; only fire thrust when roughly aimed
const AVOID_RANGE := 140.0       # start avoiding a non-target body within this
const AVOID_STRENGTH := 2.2      # how hard to push away from non-target bodies
const ANGVEL_DAMP := 0.30        # lead the rotation by this * angular_velocity


func _ready() -> void:
	# Fully inert in production: only live in debug builds or with --autopilot.
	if not OS.is_debug_build() and not ("--autopilot" in OS.get_cmdline_args()):
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	if "--autopilot" in OS.get_cmdline_args():
		active = true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F8:
		active = not active
		if not active:
			_release_all()


func _physics_process(_dt: float) -> void:
	if not active:
		return
	var arr := get_tree().get_nodes_in_group("rocket")
	_rocket = arr[0] if arr.size() > 0 else null
	if _rocket == null or not is_instance_valid(_rocket):
		return
	var tgt = _rocket.get("target")
	if tgt == null or not is_instance_valid(tgt):
		_release_all()
		return
	_drive(tgt)


func _drive(tgt: Node2D) -> void:
	var pos: Vector2 = _rocket.global_position
	var vel: Vector2 = _rocket.linear_velocity
	var to_tgt: Vector2 = tgt.global_position - pos
	var dist := to_tgt.length()

	# 1) Desired velocity: cruise toward the target, ease down on approach.
	var speed := SEEK_SPEED
	if dist < APPROACH_RADIUS:
		speed = lerpf(LAND_SPEED, SEEK_SPEED, clampf(dist / APPROACH_RADIUS, 0.0, 1.0))
	var desired_vel := to_tgt.normalized() * speed

	# 2) Slingshot/avoid: push away from any close gravity body that ISN'T the
	#    target so we curve around it (e.g. Earth) instead of crashing in.
	var bodies = _rocket.get("_all_gravity_bodies")
	if bodies != null:
		for body in bodies:
			if body == tgt or not is_instance_valid(body):
				continue
			var off: Vector2 = pos - body.global_position
			var d := maxf(off.length(), 1.0)
			if d < AVOID_RANGE * 2.5:
				desired_vel += off.normalized() * (AVOID_RANGE * 2.5 - d) * AVOID_STRENGTH

	# 3) Accel we want = steer current velocity toward desired (the rocket's
	#    own gravity integration is left to push us; we correct against it).
	var desired_accel := desired_vel - vel
	if desired_accel.length() < 1.0:
		_release_all()
		return

	# 4) Orient the nose so thrust pushes ALONG desired_accel. rocket.gd applies
	#    thrust as accel direction (sin r, -cos r); invert to get target rotation.
	var want_rot := atan2(desired_accel.x, -desired_accel.y)
	var err := wrapf(want_rot - _rocket.rotation, -PI, PI)
	var lead := err - _rocket.angular_velocity * ANGVEL_DAMP

	if lead > 0.05:
		Input.action_press("ui_right"); Input.action_release("ui_left")
	elif lead < -0.05:
		Input.action_press("ui_left"); Input.action_release("ui_right")
	else:
		Input.action_release("ui_left"); Input.action_release("ui_right")

	# 5) Fire thrust only when roughly aimed (so we accelerate the right way).
	if absf(err) < ANGLE_TOLERANCE:
		Input.action_press("thrust")
	else:
		Input.action_release("thrust")


func _release_all() -> void:
	for a in ["thrust", "revthrust", "ui_left", "ui_right"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
