extends Node
## Heuristic autopilot — automated play-tester + promo B-roll pilot.
##
## NOT machine learning. A phased PD / bang-bang controller:
##   ESCAPE   — climb radially OUT of the gravity well the rocket starts in
##              (the nearest non-target body, e.g. Earth) until clear of it. A
##              straight thrust into that body is the #1 death cause in the live
##              telemetry, so getting out cleanly first is the whole point.
##   TRANSFER — head for the landing target, bending the heading around any
##              intervening non-target body so we curve AROUND it, not through it.
##   APPROACH — folded into TRANSFER: as we near the target the cruise speed eases
##              toward land_speed and the nose swings RETROGRADE to brake, so we
##              touch down under the rocket's landingspeed instead of slamming in.
##
## It drives the SAME inputs a keyboard player uses (ui_left / ui_right / thrust),
## so it reuses rocket.gd's real physics with ZERO changes to the rocket. This
## node is fully inert unless it's a debug build or --autopilot is passed (see
## _ready), so mobile and production builds are completely untouched.
##
## Results (NORMAL difficulty, base upgrades, headless): wins the clean physics
## levels (1, 3). Levels 2+ all carry a Martian plus escalating hazards (wormhole,
## solar wind, black hole, mothership) that a non-reactive pilot can't dodge —
## that's the known ceiling, not a flight bug.
##
## Enable:  press F8 in a debug build, or launch with --autopilot.
## Tune:    every knob below is env-overridable (AP_*) so the headless harness
##          (SimHarness.gd, --sim) can sweep it without recompiling.
## Docs:    game/test/README.md  (architecture, how to run sims, capture video).

var active := false
var _rocket: RigidBody2D = null

# tuning knobs (defaults; override per-run via AP_* env vars for sweeps)
var seek_speed := 120.0     # transfer cruise speed (px/s); slow enough to brake on arrival
var approach_radius := 420.0  # start easing speed down this far from the target
var land_speed := 22.0      # desired touchdown speed (well under landingspeed=40)
var angle_tol := 0.22
var turn_gain := 4.0        # desired turn rate (rad/s) per rad of heading error
var max_turn_rate := 4.5    # cap on desired turn rate (rad/s)
var escape_radius := 320.0
var radial_bias := 1.0
var tangent_bias := 0.0   # 0 = pure-radial climb-out (stable); add tangent later for the arc
var avoid_range := 260.0  # transfer: bend heading away from non-target bodies within this
var avoid_gain := 1.6     # transfer: how hard to bend around them
var hazard_range := 210.0 # sidestep chasers/hazards (e.g. Martian) only within this
var hazard_gain := 1.5    # how hard to sidestep them
var flee_speed := 78.0    # while threatened (outside the pad safe zone), don't drop below this
var safe_zone := 130.0    # within this of the target the Martian backs off; brake normally
var evade_hazards := false # AP_EVADE=1 to enable chaser evasion (WIP; see README hazard notes)
var _hazards: Array = []  # cached CharacterBody2D hazards in the current level
var _haz_for: Object = null

# Hybrid handoff: inside HANDOFF_DIST of the pad, hand the touchdown to the RL lander
# (validated pure-GDScript inference of the SB3 policy -- no ONNX/native deps, runs on
# every export platform). The autopilot flies the transit OUTSIDE the bubble. This is
# the PLAN.md "Hybrid Handoff Model": heuristic transit + RL touchdown.
const HANDOFF_DIST := 220.0
const RL_POLICY_PATH := "res://game/ai/landing_policy.json"
var _policy = null
var _rl_land := false           # SML_RL_LAND=1 -> RL lander does the touchdown
var _rl_deterministic := false  # default stochastic = a varied opponent (different every run)


func _f(name: String, def: float) -> float:
	var v := OS.get_environment(name)
	return float(v) if v != "" else def


func _ready() -> void:
	if not OS.is_debug_build() and not ("--autopilot" in OS.get_cmdline_args()):
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	# env overrides (used by the headless tuning harness)
	seek_speed = _f("AP_SEEK_SPEED", seek_speed)
	approach_radius = _f("AP_APPROACH_RADIUS", approach_radius)
	land_speed = _f("AP_LAND_SPEED", land_speed)
	angle_tol = _f("AP_ANGLE_TOL", angle_tol)
	turn_gain = _f("AP_TURN_GAIN", turn_gain)
	max_turn_rate = _f("AP_MAX_TURN_RATE", max_turn_rate)
	escape_radius = _f("AP_ESCAPE_RADIUS", escape_radius)
	radial_bias = _f("AP_RADIAL_BIAS", radial_bias)
	tangent_bias = _f("AP_TANGENT_BIAS", tangent_bias)
	avoid_range = _f("AP_AVOID_RANGE", avoid_range)
	avoid_gain = _f("AP_AVOID_GAIN", avoid_gain)
	hazard_range = _f("AP_HAZARD_RANGE", hazard_range)
	hazard_gain = _f("AP_HAZARD_GAIN", hazard_gain)
	flee_speed = _f("AP_FLEE_SPEED", flee_speed)
	safe_zone = _f("AP_SAFE_ZONE", safe_zone)
	var ev := OS.get_environment("AP_EVADE")
	evade_hazards = ev != "" and ev != "0"
	# Hybrid RL landing (opt-in). load() the class directly so it works even when the
	# global class cache isn't registered (headless --capture/--autopilot runs).
	_rl_land = OS.get_environment("SML_RL_LAND") not in ["", "0"]
	_rl_deterministic = OS.get_environment("SML_RL_DETERMINISTIC") not in ["", "0"]
	if _rl_land:
		var p = load("res://game/ai/RLPolicy.gd").new()
		if p.load_json(RL_POLICY_PATH):
			_policy = p
			print("[AutoPilot] RL landing ENABLED (handoff < %dpx, %s)" % [int(HANDOFF_DIST), "deterministic" if _rl_deterministic else "stochastic"])
		else:
			push_warning("AutoPilot: RL landing requested but policy failed to load; heuristic landing")
			_rl_land = false
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
	# Keep the body awake: a sleeping RigidBody2D stops calling _integrate_forces,
	# so our torque/thrust inputs would silently do nothing if it ever rests.
	_rocket.can_sleep = false
	_rocket.sleeping = false
	# (re)scan the level for chaser hazards when the rocket instance changes
	if _rocket != _haz_for:
		_haz_for = _rocket
		_refresh_hazards()
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
	var dir_tgt := to_tgt.normalized()

	# HYBRID HANDOFF: inside the pad bubble, the RL lander sticks the upright touchdown.
	if _rl_land and _policy != null and dist < HANDOFF_DIST:
		_rl_drive(tgt)
		return

	# Dominant non-target gravity body we must climb out of / arc around.
	var dominant: Node2D = null
	var dom_d := INF
	var bodies = _rocket.get("_all_gravity_bodies")
	if bodies != null:
		for body in bodies:
			if body == tgt or not is_instance_valid(body):
				continue
			var d := pos.distance_to(body.global_position)
			if d < dom_d:
				dom_d = d
				dominant = body

	# Phased desired HEADING:
	#   ESCAPE  (dom_d < escape_radius): point radially OUT of the dominant well
	#           and climb. tangent_bias would add a sideways lead for a prettier
	#           slingshot arc, but defaults to 0 (pure radial) because a STABLE
	#           heading is what reliably climbs out — a swinging heading made the
	#           controller chase its tail and fall back. Raise it for looks only.
	#   TRANSFER (clear of the well): aim at the target, bending the heading away
	#           from any close non-target body (avoid_*) so we go around, not in.
	var desired_dir := dir_tgt
	var phase := "XFER"
	if dominant != null and dom_d < escape_radius:
		phase = "ESC"
		var radial_n: Vector2 = (pos - dominant.global_position).normalized()
		var tang := Vector2(-radial_n.y, radial_n.x)
		if tang.dot(dir_tgt) < 0.0:
			tang = -tang
		desired_dir = (radial_n * radial_bias + tang * tangent_bias).normalized()
	elif bodies != null:
		# TRANSFER: aim at the target, but bend the heading away from any close
		# non-target body so we curve AROUND intervening planets/moons instead of
		# flying straight through them (the cause of the far-map deaths in 5-11).
		var avoid := Vector2.ZERO
		for body in bodies:
			if body == tgt or not is_instance_valid(body):
				continue
			var off: Vector2 = pos - body.global_position
			var d := maxf(off.length(), 1.0)
			if d < avoid_range:
				avoid += off.normalized() * ((avoid_range - d) / avoid_range)
		desired_dir = (dir_tgt + avoid * avoid_gain).normalized()

	# Evade chasers (Martian: CharacterBody2D that follows + kills on contact).
	# Only when one is genuinely close, and dodge SIDEWAYS (perpendicular) toward
	# the target side, so we keep making progress instead of fleeing backward and
	# derailing. We outrun it (120 vs 40) and it backs off within 120px of a pad.
	# Chaser evasion (WIP, opt-in via AP_EVADE). Beats the Martian's chase in open
	# space but does not yet robustly clear the hazard levels, and a blunt version
	# can derail clean levels, so it is OFF by default. See README hazard notes.
	var near_hazard := false
	if evade_hazards:
		for h in _hazards:
			if not is_instance_valid(h):
				continue
			var hoff: Vector2 = pos - h.global_position   # away from the hazard
			var hd := hoff.length()
			if hd < hazard_range and hd > 0.5:
				near_hazard = true
				var side := Vector2(-hoff.y, hoff.x).normalized()  # perpendicular
				if side.dot(dir_tgt) < 0.0:
					side = -side                                    # toward-target side
				var w := (hazard_range - hd) / hazard_range
				desired_dir = (desired_dir + side * w * hazard_gain).normalized()
	# Threatened only OUTSIDE the pad safe zone; within it the Martian backs off.
	var threatened := near_hazard and dist > safe_zone

	# Target speed: cruise, easing to land on final approach. While threatened,
	# floor at flee_speed (above the Martian's 40 so we still evade, but low enough
	# to brake once we reach the safe zone) instead of blitzing in too fast to stop.
	var tgt_speed := seek_speed
	if dist < approach_radius:
		var eased := lerpf(land_speed, seek_speed, clampf(dist / approach_radius, 0.0, 1.0))
		tgt_speed = maxf(eased, flee_speed) if threatened else eased

	# Steering target:
	#   ESCAPE  -> the radial heading; just point out of the well and climb.
	#   else    -> the ACCELERATION that drives our velocity toward desired_vel,
	#              so the nose swings RETROGRADE to brake when we're closing on
	#              the target too fast (otherwise we blow past it and orbit
	#              forever, which is exactly what the trace showed).
	var steer_dir := desired_dir
	var dv := Vector2.ZERO
	if phase != "ESC":
		dv = (desired_dir * tgt_speed) - vel
		if dv.length() > 1.0:
			steer_dir = dv.normalized()

	# CASCADED orientation controller: outer loop turns heading error into a
	# desired turn rate (-> 0 near the heading), inner loop bang-bangs torque to
	# track it. Robust to the rocket's huge torque/inertia ratio (torque 5000,
	# mass 5), which a plain proportional controller always overshoots.
	var want_rot := atan2(steer_dir.x, -steer_dir.y)
	var err := wrapf(want_rot - _rocket.rotation, -PI, PI)
	var desired_w := clampf(err * turn_gain, -max_turn_rate, max_turn_rate)
	var w_err := desired_w - _rocket.angular_velocity
	if w_err > 0.05:
		Input.action_press("ui_right"); Input.action_release("ui_left")
	elif w_err < -0.05:
		Input.action_press("ui_left"); Input.action_release("ui_right")
	else:
		Input.action_release("ui_left"); Input.action_release("ui_right")

	if Engine.get_physics_frames() % 30 == 0:
		print("AP %s r_dom=%.0f dist=%.0f spd=%.0f rot=%.2f want=%.2f err=%.2f w=%.2f fuel=%.0f"
			% [phase, dom_d, dist, vel.length(), _rocket.rotation, want_rot, err,
				_rocket.angular_velocity, float(_rocket.get("fuel"))])

	# Thrust: climb during escape; otherwise fire along the correction (which is
	# accelerate-toward OR brake-retrograde) whenever it's meaningful.
	var fire := absf(err) < angle_tol and (phase == "ESC" or dv.length() > 6.0)
	if fire:
		Input.action_press("thrust")
	else:
		Input.action_release("thrust")


# EXACT 13-dim observation the lander was trained on (mirrors RocketAIController.get_obs).
# Any drift here makes the policy see a different world than it trained in.
func _rl_obs(tgt: Node2D) -> Array:
	var pos: Vector2 = _rocket.global_position
	var vel: Vector2 = _rocket.linear_velocity
	var to_t: Vector2 = tgt.global_position - pos
	var dist := to_t.length()
	var dir := (to_t / dist) if dist > 1.0 else Vector2.RIGHT
	var radial_vel := vel.dot(dir)
	var tangential_vel := vel.dot(Vector2(-dir.y, dir.x))
	var landing_tilt := wrapf(_rocket.rotation - (to_t.angle() - PI / 2.0), -PI, PI)
	var fuel := float(_rocket.get("fuel")) / maxf(float(_rocket.get("max_fuel")), 1.0)
	return [
		clampf(vel.x / 300.0, -3.0, 3.0), clampf(vel.y / 300.0, -3.0, 3.0),
		sin(_rocket.rotation), cos(_rocket.rotation),
		clampf(_rocket.angular_velocity / 5.0, -3.0, 3.0),
		fuel,
		clampf(to_t.x / 1800.0, -3.0, 3.0), clampf(to_t.y / 1800.0, -3.0, 3.0),
		clampf(dist / 1800.0, 0.0, 3.0),
		clampf(radial_vel / 300.0, -3.0, 3.0),
		clampf(tangential_vel / 300.0, -3.0, 3.0),
		sin(landing_tilt), cos(landing_tilt),
	]


# Drive the rocket from the RL policy. Action mapping mirrors RocketAIController.set_action:
# act[0]=rotate (0=left,1=none,2=right), act[1]=thrust (0=off,1=on).
func _rl_drive(tgt: Node2D) -> void:
	var act = _policy.predict(_rl_obs(tgt), _rl_deterministic)
	Input.action_release("ui_left"); Input.action_release("ui_right")
	if int(act[0]) == 0:
		Input.action_press("ui_left")
	elif int(act[0]) == 2:
		Input.action_press("ui_right")
	if int(act[1]) == 1:
		Input.action_press("thrust")
	else:
		Input.action_release("thrust")


func _release_all() -> void:
	for a in ["thrust", "revthrust", "ui_left", "ui_right"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _refresh_hazards() -> void:
	# Chaser hazards (the Martian) are CharacterBody2D nodes; find them by scanning
	# the level so we never have to touch game code. Cached per level.
	_hazards.clear()
	var root := get_tree().current_scene
	if root != null:
		_collect_hazards(root)


func _collect_hazards(n: Node) -> void:
	if n is CharacterBody2D:
		_hazards.append(n)
	for c in n.get_children():
		_collect_hazards(c)
