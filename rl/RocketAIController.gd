extends AIController2D
## RL agent for Such Moon Launch. Lives in the training scene beside a Sync node
## and an "Env" node. It instances a level under Env, reads the rocket, and drives
## the SAME inputs the heuristic autopilot uses, so rocket.gd is unchanged.
## Obs = the state the heuristic needed; reward reuses the harness's win/death
## detection (landattemptnow/flagplaced = win, SkullSprite/sendDeath = death).

@export var env_path: NodePath
@export var level_scene: PackedScene

var _rocket: RigidBody2D = null
var _target: Node2D = null
var _prev_dist := 0.0
var _min_dist := 1.0e9   # closest the rocket got to the pad this episode
var _best_min := 1.0e9   # closest ever achieved (learning-to-approach signal)
var _hazard_death := false
var _episodes := 0
var _wins := 0

# Reverse curriculum: start the rocket THIS far from the Moon. Begins close (learn
# the touchdown in isolation, where a random policy can actually stumble into a soft
# landing) and auto-grows toward the full Level-1 distance as the landing rate climbs.
var _spawn_dist := 150.0
const SPAWN_DIST_MAX := 650.0
const SPAWN_DIST_STEP := 60.0
const CURRICULUM_WINDOW := 50      # episodes per evaluation
const CURRICULUM_PROMOTE := 0.45   # land-rate over the window to move the start outward
var _last_ep_check := 0
var _last_win_check := 0
var _eval_mode := false   # RL_EVAL=1: spawn at the level's NATURAL start (no curriculum)

# Robust reset: free the old level one frame, spawn the new the next, then a short
# grace before detecting outcomes (so a freed dead rocket can't trigger an instant
# 1-frame "death", which collapses training).
var _pending_spawn := false
var _grace := 0


func _ready() -> void:
	super._ready()  # AIController2D._ready adds us to group "AGENT"
	_eval_mode = OS.get_environment("RL_EVAL") != ""
	if globalvar.has_signal("sendDeath"):
		globalvar.sendDeath.connect(func(): _hazard_death = true)
	_begin_respawn()


func _begin_respawn() -> void:
	var env := get_node_or_null(env_path)
	if env != null:
		for c in env.get_children():
			c.queue_free()  # deferred: actually gone next frame
	_rocket = null
	_target = null
	_prev_dist = 0.0
	_min_dist = 1.0e9
	_hazard_death = false
	_pending_spawn = true
	_grace = 0


func _do_spawn() -> void:
	var env := get_node_or_null(env_path)
	if env != null and level_scene != null:
		env.add_child(level_scene.instantiate())
	_grab()
	# Reverse-curriculum start: place the rocket _spawn_dist from the Moon, at rest,
	# oriented so thrust points away from it (ready to retro for a soft touchdown).
	# Skipped in eval mode -> the rocket spawns at the level's NATURAL Level-1 start.
	if not _eval_mode and _rocket != null and is_instance_valid(_rocket) and _target != null and is_instance_valid(_target):
		var ang := randf_range(-0.7, 0.7)
		var away := Vector2(sin(ang), -cos(ang))
		_rocket.global_position = _target.global_position + away * _spawn_dist
		_rocket.linear_velocity = Vector2.ZERO
		_rocket.angular_velocity = 0.0
		_rocket.rotation = ang
	_grace = 6  # frames to let the fresh level settle before scoring


func _grab() -> void:
	# Prefer a LIVE rocket (skull hidden); never latch onto a dead/freed one.
	var arr := get_tree().get_nodes_in_group("rocket")
	_rocket = null
	for r in arr:
		if not is_instance_valid(r):
			continue
		var sk = r.get_node_or_null("SkullSprite")
		if sk == null or not sk.visible:
			_rocket = r
			break
	if _rocket == null:
		for r in arr:
			if is_instance_valid(r):
				_rocket = r
				break
	if _rocket != null:
		_rocket.can_sleep = false
		_target = _rocket.get("target")


func get_action_space() -> Dictionary:
	return {
		"thrust": {"size": 2, "action_type": "discrete"},   # 0 off, 1 on
		"rotate": {"size": 3, "action_type": "discrete"},   # 0 left, 1 none, 2 right
	}


func set_action(action) -> void:
	if _rocket == null or not is_instance_valid(_rocket):
		return
	var thrust_a = action["thrust"]
	if thrust_a is Array:
		thrust_a = thrust_a[0]
	var rotate_a = action["rotate"]
	if rotate_a is Array:
		rotate_a = rotate_a[0]
	if int(thrust_a) == 1:
		Input.action_press("thrust")
	else:
		Input.action_release("thrust")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	var r := int(rotate_a)
	if r == 0:
		Input.action_press("ui_left")
	elif r == 2:
		Input.action_press("ui_right")


func get_obs() -> Dictionary:
	if _rocket == null or not is_instance_valid(_rocket):
		_grab()
	if _rocket == null or _target == null or not is_instance_valid(_target):
		return {"obs": [0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]}
	var pos: Vector2 = _rocket.global_position
	var vel: Vector2 = _rocket.linear_velocity
	var to_t: Vector2 = _target.global_position - pos
	var dist := to_t.length()
	var dir := to_t / dist if dist > 1.0 else Vector2.RIGHT
	# pad-relative velocity: radial = descent rate (the finishing info the policy
	# was missing), tangential = sideways drift.
	var radial_vel := vel.dot(dir)
	var tangential_vel := vel.dot(Vector2(-dir.y, dir.x))
	# landing tilt: rotation RELATIVE to the Moon. 0 = upright for landing; the win
	# requires |tilt| < TILT_DEATH_ANGLE, so the policy MUST be able to see this.
	var landing_tilt := wrapf(_rocket.rotation - (to_t.angle() - PI / 2.0), -PI, PI)
	var fuel := float(_rocket.get("fuel")) / maxf(float(_rocket.get("max_fuel")), 1.0)
	return {"obs": [
		clampf(vel.x / 300.0, -3.0, 3.0), clampf(vel.y / 300.0, -3.0, 3.0),
		sin(_rocket.rotation), cos(_rocket.rotation),
		clampf(_rocket.angular_velocity / 5.0, -3.0, 3.0),
		fuel,
		clampf(to_t.x / 1800.0, -3.0, 3.0), clampf(to_t.y / 1800.0, -3.0, 3.0),
		clampf(dist / 1800.0, 0.0, 3.0),
		clampf(radial_vel / 300.0, -3.0, 3.0),       # descent rate toward the pad
		clampf(tangential_vel / 300.0, -3.0, 3.0),   # sideways drift
		sin(landing_tilt), cos(landing_tilt),        # orientation relative to the Moon
	]}


func get_reward() -> float:
	return reward


func reset() -> void:
	super.reset()  # n_steps = 0, needs_reset = false
	done = false
	_begin_respawn()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)  # n_steps++, sets needs_reset after reset_after
	# Re-assert the training time_scale every frame. The rocket's landing slow-mo
	# (0.7) and its death handler (1.0) reset Engine.time_scale, which would corrupt
	# the Sync's speedup and the physics dt -> breaks landing fidelity + transfer.
	Engine.time_scale = Engine.physics_ticks_per_second / 60.0
	if needs_reset:
		if not done:
			# timeout (hit reset_after with no win/death). Count it as a failure with
			# proximity credit, so HOVERING near the pad is not a free safe outcome.
			reward += -3.0 + (1.0 - clampf(_min_dist / 600.0, 0.0, 1.0)) * 4.0
			done = true
			_episodes += 1
			_best_min = minf(_best_min, _min_dist)
			_log_progress()
			return  # let the Sync read done=true; respawn next frame
		reset()
		return
	if _pending_spawn:
		_pending_spawn = false
		_do_spawn()
		return
	if _grace > 0:
		_grace -= 1
		_grab()
		return
	if done:
		return  # episode ended; wait for the Sync/Python reset
	if _rocket == null or not is_instance_valid(_rocket):
		_grab()
	if _rocket == null or _target == null or not is_instance_valid(_target):
		return
	var spd := _rocket.linear_velocity.length()
	var dist := (_target.global_position - _rocket.global_position).length()
	_min_dist = minf(_min_dist, dist)
	if _prev_dist > 0.0:
		reward += (_prev_dist - dist) * 0.01   # dense: progress toward the pad
	_prev_dist = dist
	reward -= 0.005                            # mild time pressure
	# NOTE: no per-step proximity-speed penalty here on purpose — that taught the
	# agent to AVOID the pad. Arriving slow is rewarded in the TERMINAL reward below.
	if _rocket.get("landattemptnow") == true or _rocket.get("flagplaced") == true:
		reward += 12.0 + float(_rocket.get("fuel")) / 100.0
		done = true
		needs_reset = true   # self-reset: respawn the level next frame
		_episodes += 1
		_wins += 1
		_best_min = minf(_best_min, _min_dist)
		_log_progress()
	else:
		var skull := _rocket.get_node_or_null("SkullSprite")
		if (skull != null and skull.visible) or _hazard_death:
			# Terminal-speed shaping: a crash that is BOTH close AND slow scores
			# almost like a landing -> rewards arriving slow for the descent without
			# any per-step proximity penalty (which caused pad-avoidance).
			var prox := 1.0 - clampf(_min_dist / 600.0, 0.0, 1.0)  # 1 = crashed on the pad
			var slow := 1.0 - clampf(spd / 150.0, 0.0, 1.0)        # 1 = very slow impact
			var tilt := wrapf(_rocket.rotation - ((_target.global_position - _rocket.global_position).angle() - PI / 2.0), -PI, PI)
			var upright := 1.0 - clampf(absf(tilt) / (PI / 2.0), 0.0, 1.0)  # 1 = upright for landing
			# win needs close + slow + UPRIGHT; reward how close the crash got to all three
			reward += -10.0 + prox * (slow * 5.0 + upright * 5.0)
			done = true
			needs_reset = true
			_episodes += 1
			_best_min = minf(_best_min, _min_dist)
			_log_progress()


func _log_progress() -> void:
	# Curriculum: every CURRICULUM_WINDOW episodes, if the landing rate over that
	# window is high enough, push the start farther from the Moon (harder).
	if _episodes - _last_ep_check >= CURRICULUM_WINDOW:
		var e := _episodes - _last_ep_check
		var w := _wins - _last_win_check
		if e > 0 and float(w) / float(e) >= CURRICULUM_PROMOTE:
			_spawn_dist = minf(_spawn_dist + SPAWN_DIST_STEP, SPAWN_DIST_MAX)
		_last_ep_check = _episodes
		_last_win_check = _wins
	if _episodes % 25 == 0:
		var recent := 100.0 * float(_wins - _last_win_check) / maxf(float(_episodes - _last_ep_check), 1.0)
		print("[RL] episodes=%d wins=%d closest_ever=%.0f spawn_dist=%.0f recent_land=%.0f%% ts=%.1f" % [
			_episodes, _wins, _best_min, _spawn_dist, recent, Engine.time_scale])
