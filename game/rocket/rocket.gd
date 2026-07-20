extends RigidBody2D

## Emitted when the player completes a gravity slingshot (gains >= threshold speed
## swinging past a body). WP-B1's Level 1 tutorial listens for this to advance the
## slingshot step when it actually happens.
signal slingshot_achieved(speed_gain: float)

# Ship control variables — base values overridden by upgrades in _ready()
var thrust = Vector2(0, 350)
var reverse_thrust = Vector2(0, 350)
var torque = 5000
var shipoverlaps
var footoverlaps
var crashspeed = 100.0
var landingspeed = 40.0

# Decaying high-water-mark of recent speed. Used by the crash check so a
# very fast impact still fires death(); without this, the physics solver
# can damp velocity below crashspeed between the "incoming fast" frame
# and the first overlap-poll frame, letting tail-first high-speed crashes
# (notably into Earth) bounce off without dying.
var _recent_max_speed: float = 0.0
const _RECENT_SPEED_DECAY := 0.92  # per physics frame -> ~25% kept after 10 frames
# Fuel — base values overridden by upgrades in _ready()
var fuel: float = 100.0
var max_fuel: float = 100.0
var fuel_drain: float = 12.0  # fuel units per second while thrusting
# Shield
var shield_hits: int = 0  # remaining shield absorbs
# Magnet
var magnet_radius: float = 0.0
# Timer variables
var deathtimer 
var moontimer
var moontimerdefault = 3
var landattempttimer
# Mission variables
var landattemptnow = false
var flagplaced = false
var _landing_grace: float = 0.0  # grace period for orbiting planets
const LANDING_GRACE_TIME := 1.0  # seconds of no-contact before cancelling

var target = null
var _level_start_ms: int = 0            # death-forensics: time_into_level
var _initial_target_dist: float = -1.0  # death-forensics: pct_through baseline

# Screen shake state
var _shake_intensity: float = 0.0
var _shake_decay: float = 5.0

# Slow-motion landing state
var _in_slowmo: bool = false

# 3D Landing mode
var _landing_mode: CanvasLayer = null
var _landing_mode_active: bool = false
var _landing_active_target: Node2D = null   # the body landing-mode is bound to
var _landing_active_range: float = 0.0      # the trigger range used at activation
const LANDING_MODE_MIN_RANGE := 80.0   # minimum trigger distance (small bodies)
const LANDING_MODE_MARGIN := 60.0      # pixels above collision surface to trigger
const LANDING_MODE_EXIT_HYSTERESIS := 1.25  # multiplier on range for deactivation (anti-flicker)
var TILT_DEATH_ANGLE := 0.6109  # ~35 degrees (var, not const, so RL training can relax it under --capture)
# Easy-mode second-chance bounce
const BOUNCE_SPEED := 220.0  # px/s away from crash body
const BOUNCE_FUEL_PCT := 0.15  # max_fuel fraction restored on bounce
const BOUNCE_INVULN_TIME := 1.2  # seconds of hazard-immunity after a hazard bounce
var _bounce_invuln: float = 0.0  # counts down; while >0, hazards can't kill (post-bounce)

# Proximity beep state
var _beep_cooldown: float = 0.0
const BEEP_RANGE := 250.0  # start beeping at this distance from target

# Waypoint checkpoint tracking
var _visited_waypoints: Dictionary = {}  # node instance_id -> true
var _waypoint_bodies: Array = []  # bodies in "targets" group that aren't the final target
# Waypoint refueling bonus
const WAYPOINT_FUEL_BONUS := 0.10  # fraction of max_fuel restored on waypoint arrival

# Gravity slingshot tracking
var _slingshot_inside: Dictionary = {}   # body instance_id -> entry speed (float)
var _all_gravity_bodies: Array = []       # all bodies with Area2D gravity that we track
const SLINGSHOT_SPEED_THRESHOLD := 40.0  # must gain at least this much speed

# Landing countdown beep state
var _landing_beep_elapsed: float = 0.0
var _landing_beep_count: int = 0

# Cannon weapon state
var _has_cannon: bool = false
var _cannon_cooldown: float = 0.0
var _cannon_fire_rate: float = 0.4  # seconds between shots (overridden by upgrade level)
var _cannon_damage: int = 1
const BULLET_SCENE = preload("res://game/rocket/Bullet.tscn")
const AUTO_AIM_RANGE := 300.0  # auto-aim search radius
const AUTO_AIM_CONE := 1.2  # radians (~70 degrees each side of forward)

# Missile weapon state
var _has_missile: bool = false
var _missile_ammo: int = 0
var _missile_cooldown: float = 0.0
const MISSILE_SCENE = preload("res://game/rocket/Missile.tscn")
const MISSILE_COOLDOWN := 1.0  # seconds between launches
const MISSILE_AIM_RANGE := 500.0

# Laser beam state
var _has_laser: bool = false
var _laser_node: Node2D = null
var _laser_fuel_drain: float = 18.0

# EMP pulse state
var _has_emp: bool = false
var _emp_charges: int = 0
var _emp_radius: float = 150.0
const EMP_BASE_RADIUS := 150.0
const EMP_RADIUS_PER_LEVEL := 30.0
const EMPPulseScript = preload("res://game/rocket/EMPPulse.gd")
# Preload LandingMode so the script + 3D shader compile happen at level load,
# not at the moment we approach a planet (was a noticeable freeze).
const LANDING_MODE_SCRIPT = preload("res://game/rocket/LandingMode.gd")

# Tilt-mode calibration: the gravity vector captured shortly after level start.
# All tilt input is measured as a DELTA from this baseline so the player's
# natural hold position registers as zero (no drift).
var _tilt_baseline: Vector3 = Vector3.ZERO
# Low-pass-filtered raw gravity. Kills sensor jitter without eating slow
# intentional tilts (canonical mobile pattern — beats baseline drift).
var _tilt_filtered: Vector3 = Vector3.ZERO
var _tilt_calibrated: bool = false
# Screen orientation captured at calibration. With sensor_landscape the device
# can be in either landscape; when this changes we re-calibrate + flip the sign.
var _tilt_orientation: int = -1
# Full-tilt (portrait) inputs — computed each frame in _read_full_tilt().
var _fulltilt_turn := 0.0       # -1..1 roll -> steering
var _fulltilt_thrust := false   # pitch forward past deadzone
var _fulltilt_reverse := false  # pitch back past deadzone
# Self-destruct button — shown on the HUD when fuel is dangerously low so
# the player can bail out of an unrecoverable drift.
var _self_destruct_btn: Button = null
const SELF_DESTRUCT_FUEL_THRESHOLD := 0.05  # show when fuel ≤ 5% of max

# --- Thrust exhaust ramp (WP-D3) ---------------------------------------------
# Binary emitting=true/false makes the exhaust strobe when thrust is tapped
# rapidly. Instead we tween amount_ratio: a fast swell up and a slower decay
# down, keeping the emitter alive (emitting=true) until the ratio hits zero.
# Strictly visual/audio — physics (constant_force / fuel) is unchanged.
const _THRUST_RAMP_UP := 0.08        # seconds to swell to full
const _THRUST_RAMP_DOWN := 0.25      # seconds to decay to nothing
const _THRUST_SOUND_MIN_DB := -40.0  # effectively silent during the fade
var _rear_thrust_on := false
var _rev_thrust_on := false
var _thrust_sound_on := false
var _rear_thrust_tween: Tween
var _rev_thrust_tween: Tween
var _thrust_sound_tween: Tween


func _ready():
	# Add to group so HUD widgets (FuelBar etc.) can find us
	add_to_group("rocket")
	# Hide menu banner ad during gameplay
	AdManager.hide_banner()
	# Reset per-level stats
	globalvar.reset_level_stats()
	Telemetry.log_event(Telemetry.EVENT_LEVEL_START, {
		"level": globalvar.nowlevel,
		"difficulty": globalvar.difficulty,
	})
	Analytics.launch_attempt(globalvar.nowlevel, str(globalvar.difficulty))
	_level_start_ms = Time.get_ticks_msec()
	call_deferred("_capture_initial_dist")
	# Apply upgrades from globalvar
	thrust = Vector2(0, globalvar.get_thrust_force())
	reverse_thrust = Vector2(0, globalvar.get_reverse_thrust_force())
	max_fuel = globalvar.get_max_fuel()
	# Start with a full tank — difficulty bonus is already baked into max_fuel.
	fuel = max_fuel
	fuel_drain = globalvar.get_fuel_drain() * globalvar.get_fuel_drain_mult()
	crashspeed = globalvar.get_crash_speed()
	landingspeed = globalvar.get_landing_speed()
	torque = int(globalvar.get_torque())
	shield_hits = globalvar.get_shield_hits()
	magnet_radius = globalvar.get_magnet_radius()
	# Cannon upgrade
	var cannon_level: int = globalvar.upgrades.get("cannon", 0)
	if cannon_level > 0:
		_has_cannon = true
		_cannon_fire_rate = maxf(0.4 - cannon_level * 0.06, 0.15)
		_cannon_damage = cannon_level
	# Missile upgrade
	var missile_level: int = globalvar.upgrades.get("missile", 0)
	if missile_level > 0:
		_has_missile = true
		_missile_ammo = missile_level * 2  # 2 missiles per upgrade level
	# Laser upgrade
	var laser_level: int = globalvar.upgrades.get("laser", 0)
	if laser_level > 0:
		_has_laser = true
		var laser_script = load("res://game/rocket/LaserBeam.gd")
		_laser_node = Node2D.new()
		_laser_node.set_script(laser_script)
		add_child(_laser_node)
		_laser_node.setup(laser_level)
	# EMP upgrade
	var emp_level: int = globalvar.upgrades.get("emp", 0)
	if emp_level > 0:
		_has_emp = true
		_emp_charges = emp_level
		_emp_radius = EMP_BASE_RADIUS + emp_level * EMP_RADIUS_PER_LEVEL
	# Turn on processes and monitors
	set_process(true)
	contact_monitor = true
	max_contacts_reported = 3
	# Setup sprites
	get_node("SkullSprite").hide()
	get_node("ExplosionSprite").hide()
	get_node("CosmonautSprite").hide()
	# Thrust exhaust starts idle — emitters swell in via _set_thrust_visuals().
	# ExhaustTrail is deliberately NOT reset here: it is authored always-on (a
	# constant motion trail behind the ship) and must keep emitting while coasting.
	for _emitter_name in ["RearThrust", "RevThrust"]:
		var _emitter := get_node(_emitter_name) as GPUParticles2D
		_emitter.amount_ratio = 0.0
		_emitter.emitting = false
	# Apply selected skin
	var skin_tex := load(globalvar.get_skin_texture_path())
	if skin_tex:
		$RocketSprite.texture = skin_tex
	# Initialize timers
	deathtimer = Timer.new()
	deathtimer.set_wait_time(3)
	deathtimer.set_one_shot(true)
	deathtimer.connect("timeout", _show_death_screen)
	add_child(deathtimer)
	moontimer = Timer.new()
	moontimer.set_wait_time(moontimerdefault)
	moontimer.set_one_shot(true)
	moontimer.connect("timeout", flagplanted)
	add_child(moontimer)
	globalvar.sendDeath.connect(_on_external_death)
	#print(get_node("../../MoonSpace").get_name())
	for i in get_parent().get_children():
		if i.is_in_group('targets'):
			if target != null:
				# Previous target becomes a waypoint
				_waypoint_bodies.append(target)
			target = i
	# Build list of all gravity bodies (planets with Area2D) for slingshot detection
	for i in get_parent().get_children():
		if i == self:
			continue
		if not (i is StaticBody2D):
			continue
		for child in i.get_children():
			if child is Area2D:
				_all_gravity_bodies.append(i)
				break

	# Restore from waypoint checkpoint if flagged
	if globalvar.restore_checkpoint and globalvar.has_checkpoint:
		globalvar.restore_checkpoint = false
		# Defer position/velocity restore to after physics init
		call_deferred("_apply_checkpoint")

	# Tilt calibration: capture player's natural hold as the "zero" baseline.
	# Wait a short moment for sensors to stabilize before sampling.
	if _is_tilt_mode() or _is_full_tilt():
		get_tree().create_timer(0.4).timeout.connect(_calibrate_tilt)
	_apply_portrait_view()


func _update_self_destruct_button() -> void:
	## Show a "Self Destruct" button on the HUD when fuel is critically low,
	## so the player can manually trigger death (and respawn) if drifting.
	var low_fuel: bool = (fuel / max_fuel) <= SELF_DESTRUCT_FUEL_THRESHOLD and not flagplaced
	if low_fuel and _self_destruct_btn == null:
		var hud := get_node_or_null("../CanvasLayer")
		if hud == null: return
		_self_destruct_btn = Button.new()
		_self_destruct_btn.text = "💥 Self Destruct"
		_self_destruct_btn.custom_minimum_size = Vector2(180, 44)
		_self_destruct_btn.add_theme_font_size_override("font_size", 16)
		_self_destruct_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		_self_destruct_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_self_destruct_btn.offset_left = -200
		_self_destruct_btn.offset_right = -20
		_self_destruct_btn.offset_top = 60
		_self_destruct_btn.offset_bottom = 104
		_self_destruct_btn.pressed.connect(func(): death(null))
		hud.add_child(_self_destruct_btn)
	elif (not low_fuel) and _self_destruct_btn:
		_self_destruct_btn.queue_free()
		_self_destruct_btn = null


# --- AI control (race opponent) ---
# When ai_controlled is true the rocket IGNORES global Input and is driven by
# these vars instead, so a second AutoPilot-flown rocket doesn't fight the
# player's input. Defaults false -> zero change for the player's rocket.
var ai_controlled := false
var ai_thrust := false
var ai_revthrust := false
var ai_left := false
var ai_right := false


func _thrust_held() -> bool:
	if _is_full_tilt():
		return _fulltilt_thrust  # pitch forward = thrust (no button in full-tilt)
	return ai_thrust if ai_controlled else Input.is_action_pressed("thrust")


func _revthrust_held() -> bool:
	if _is_full_tilt():
		return _fulltilt_reverse  # pitch back = reverse
	return ai_revthrust if ai_controlled else Input.is_action_pressed("revthrust")


# Ramp a GPUParticles2D emitter toward full (on) or off via amount_ratio, so
# rapid thrust taps swell/decay smoothly instead of strobing. Returns the live
# tween so the caller can kill it on the next state flip. See WP-D3.
func _ramp_emitter(node: GPUParticles2D, tween: Tween, on: bool) -> Tween:
	if tween and tween.is_valid():
		tween.kill()
	if on and not node.emitting:
		node.emitting = true
	var duration := _THRUST_RAMP_UP if on else _THRUST_RAMP_DOWN
	var ratio := 1.0 if on else 0.0
	var t := create_tween()
	t.tween_property(node, "amount_ratio", ratio, duration)
	if not on:
		# Stop emitting only once fully decayed so nothing lingers/strobes.
		t.tween_callback(func(): node.emitting = false)
	return t


# Drive the exhaust particle ramps (and thrust audio fade) from thrust state.
# Edge-detected so it is safe to call every physics frame — a tween is only
# (re)started when a state actually flips. Purely visual/audio.
func _set_thrust_visuals(rear_on: bool, rev_on: bool) -> void:
	if rear_on != _rear_thrust_on:
		_rear_thrust_on = rear_on
		_rear_thrust_tween = _ramp_emitter(get_node("RearThrust"), _rear_thrust_tween, rear_on)
	if rev_on != _rev_thrust_on:
		_rev_thrust_on = rev_on
		_rev_thrust_tween = _ramp_emitter(get_node("RevThrust"), _rev_thrust_tween, rev_on)
	# ExhaustTrail is authored always-on (constant motion trail) — never gate it.
	_set_thrust_sound(rear_on or rev_on)


# Fade the thrust audio loop in/out over the same short windows so it doesn't
# hard-cut when thrust toggles. Matches the particle ramp durations.
func _set_thrust_sound(on: bool) -> void:
	# thrust.wav is non-looping (loop_mode=0), so re-trigger it while thrust is
	# held and the sample has finished — restores the pre-D3 every-frame replay.
	if on and _thrust_sound_on and not $ThrustSound.playing:
		$ThrustSound.play()
	if on == _thrust_sound_on:
		return
	_thrust_sound_on = on
	if _thrust_sound_tween and _thrust_sound_tween.is_valid():
		_thrust_sound_tween.kill()
	if on:
		if not $ThrustSound.playing:
			$ThrustSound.volume_db = _THRUST_SOUND_MIN_DB
			$ThrustSound.play()
		_thrust_sound_tween = create_tween()
		_thrust_sound_tween.tween_property($ThrustSound, "volume_db", 0.0, _THRUST_RAMP_UP)
	else:
		_thrust_sound_tween = create_tween()
		_thrust_sound_tween.tween_property($ThrustSound, "volume_db", _THRUST_SOUND_MIN_DB, _THRUST_RAMP_DOWN)
		_thrust_sound_tween.tween_callback(func(): $ThrustSound.stop())


func _steer_axis() -> float:
	if ai_controlled:
		return float(int(ai_right) - int(ai_left))
	return float(int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left")))


func _is_tilt_mode() -> bool:
	if ai_controlled:
		return false
	# During a "Watch a demo" run (WP-B5) the heuristic pilot drives via global
	# Input (ui_left/ui_right); tilt mode would ignore those, so bypass it.
	if globalvar.demo_mode:
		return false
	if globalvar.control_scheme != globalvar.ControlScheme.TILT:
		return false
	var os := OS.get_name()
	return os == "Android" or os == "iOS"


# Portrait (full-tilt) is a narrower viewport — zoom the camera OUT so enough of the
# world stays visible; landscape keeps the default. (Godot4: zoom < 1 = zoom out.)
# Portrait ALSO boosts content_scale (globalvar.ui_scale) to enlarge the HUD, which
# would zoom the world too — so we DIVIDE the zoom-out by that boost, leaving the
# world view identical while only the UI grows. Driven off the live window aspect so
# desktop portrait renders match on-device. Called at _ready + on a live scheme swap.
# The 0.65 effective zoom-out is device-tunable.
func _apply_portrait_view() -> void:
	if not has_node("Camera2D"):
		return
	var ws := DisplayServer.window_get_size()
	if ws.y > ws.x:  # portrait
		var z := 0.65 / globalvar.ui_scale()
		$Camera2D.zoom = Vector2(z, z)
	else:
		$Camera2D.zoom = Vector2.ONE


func _is_full_tilt() -> bool:
	if ai_controlled or globalvar.demo_mode:
		return false
	if globalvar.control_scheme != globalvar.ControlScheme.FULL_TILT:
		return false
	var os := OS.get_name()
	return os == "Android" or os == "iOS"


# Full-tilt (portrait) input: the device is held UPRIGHT, so — unlike the landscape
# tilt path — roll (tilt L/R) reads on the device X axis and pitch (tilt the top
# away/toward you) reads on the device Z axis. Roll steers; pitch forward thrusts,
# pitch back reverses. The two axis choices + polarities are DEVICE-CALIBRATION
# values (see globalvar.FULLTILT_*): verify + flip on a real phone in portrait.
func _read_full_tilt() -> void:
	var raw := Input.get_gravity()
	_tilt_filtered = _tilt_filtered.lerp(raw, globalvar.TILT_FILTER_ALPHA)
	var delta := _tilt_filtered - _tilt_baseline
	var roll := globalvar.FULLTILT_TURN_POLARITY * delta.x / 9.81
	var pitch := globalvar.FULLTILT_THRUST_POLARITY * -delta.z / 9.81
	if absf(roll) < globalvar.TILT_DEADZONE:
		roll = 0.0
	_fulltilt_turn = clampf(roll * globalvar.tilt_sensitivity, -1.0, 1.0)
	_fulltilt_thrust = pitch > globalvar.FULLTILT_THRUST_DEADZONE
	_fulltilt_reverse = pitch < -globalvar.FULLTILT_THRUST_DEADZONE


func _calibrate_tilt() -> void:
	## Sample current gravity vector as the player's neutral hold position.
	## All tilt input is computed as a delta from this baseline.
	## Seed the low-pass filter with the baseline so the first frame doesn't
	## produce a spurious delta while the filter is converging.
	var raw := Input.get_gravity()
	_tilt_baseline = raw
	_tilt_filtered = raw
	_tilt_calibrated = true


func _integrate_forces(state):
	var dt = state.step
	var has_fuel = fuel > 0.0
	# Full-tilt reads BOTH thrust (pitch) and turn (roll) from the accelerometer,
	# so sample it before the thrust block below consults _thrust_held().
	if _is_full_tilt() and _tilt_calibrated:
		_read_full_tilt()
	# Track recent peak speed BEFORE the solver may have damped this frame.
	_recent_max_speed = maxf(_recent_max_speed * _RECENT_SPEED_DECAY, state.linear_velocity.length())

	if has_fuel and _thrust_held():
		constant_force = state.total_gravity - thrust.rotated(rotation)
		_set_thrust_visuals(true, false)
		fuel -= fuel_drain * dt
	elif has_fuel and _revthrust_held():
		constant_force = state.total_gravity + reverse_thrust.rotated(rotation)
		_set_thrust_visuals(false, true)
		fuel -= fuel_drain * dt
	else:
		constant_force = state.total_gravity
		_set_thrust_visuals(false, false)

	fuel = maxf(fuel, 0.0)

	# Self-destruct: emergency escape when stuck (e.g. drifting out of fuel
	# with no way to recover). Keyboard binding 'X' / on-screen button when
	# fuel is low. Triggers normal death flow → DeathScreen offers retry.
	if not ai_controlled and Input.is_action_just_pressed("self_destruct"):
		death(null)
	if not ai_controlled:
		_update_self_destruct_button()

	# Steering input — branches by control scheme.
	if _is_full_tilt() and _tilt_calibrated:
		# Portrait full-tilt: roll drives angular velocity directly (like tilt mode).
		state.angular_velocity = _fulltilt_turn * globalvar.TILT_MAX_ANGULAR_VELOCITY
		constant_torque = 0
	elif _is_tilt_mode() and _tilt_calibrated:
		# Canonical mobile tilt-to-steer pipeline:
		#   raw gravity → low-pass filter → delta from baseline → screen-X
		#   axis with correct sign → deadzone → sensitivity → clamp → output
		# No baseline drift: it eats slow input. Filter handles jitter.
		# Orientation is locked to LANDSCAPE in project.godot, so the
		# device-natural Y axis (top of device in portrait) reliably points
		# LEFT in screen space — therefore screen-right = -device.y.
		var raw := Input.get_gravity()
		_tilt_filtered = _tilt_filtered.lerp(raw, globalvar.TILT_FILTER_ALPHA)
		var delta := _tilt_filtered - _tilt_baseline
		# In landscape the device's long axis is horizontal; rolling left/right
		# is rotation about that long axis. On iOS that roll reads on delta.y;
		# on Android it reads on delta.x. The correct steering sign is ABSOLUTE —
		# tied to the physical landscape, the SAME rule for iPhone and iPad: one
		# landscape needs -delta.y, the 180°-flipped one needs +delta.y. (The old
		# per-device-class sign worked only because each device was locked to one
		# landscape; with sensor_landscape either device sits in either.)
		var tilt: float
		if OS.get_name() == "iOS":
			# iOS DisplayServer.screen_get_orientation() returns the sensor MODE
			# (SENSOR_LANDSCAPE) we set, NOT the resolved landscape, so it can't
			# tell the two 180°-apart landscapes apart. Read the landscape from
			# gravity instead: in landscape the device's in-plane "down" is
			# dominant on the X axis and its sign is opposite between the two
			# landscapes. Steering reads on delta.y, so gravity.x is the stable
			# discriminator (steering barely perturbs the ~±9.8 dominant axis).
			# Re-neutralize the baseline on a flip so a mid-game flip stays sane.
			var land := signf(_tilt_filtered.x)
			if int(land) != _tilt_orientation:
				_calibrate_tilt()
				delta = Vector3.ZERO
				_tilt_orientation = int(land)
			# IOS_TILT_POLARITY anchors which gravity.x sign maps to which steering
			# sign (single source of truth — flip it if BOTH landscapes invert).
			tilt = globalvar.IOS_TILT_POLARITY * land * delta.y / 9.81
		else:
			# Android's screen_get_orientation() ALSO returns the sensor MODE (not the
			# resolved landscape), so detect the landscape from gravity like iOS. The
			# Android sensor frame is transposed from iOS: roll/steer reads on delta.x
			# and the dominant in-plane "down" axis is gravity.y, so gravity.y's sign
			# is the stable discriminator. Re-neutralize the baseline on a flip.
			var land := signf(_tilt_filtered.y)
			if int(land) != _tilt_orientation:
				_calibrate_tilt()
				delta = Vector3.ZERO
				_tilt_orientation = int(land)
			tilt = globalvar.ANDROID_TILT_POLARITY * land * delta.x / 9.81
		if absf(tilt) < globalvar.TILT_DEADZONE:
			tilt = 0.0
		var ctrl := clampf(tilt * globalvar.tilt_sensitivity, -1.0, 1.0)
		if globalvar.TILT_USE_TORQUE:
			constant_torque = torque * ctrl
		else:
			state.angular_velocity = ctrl * globalvar.TILT_MAX_ANGULAR_VELOCITY
			constant_torque = 0
	else:
		# Keyboard / joystick / AI — torque-based (original behavior).
		var t := _steer_axis()
		constant_torque = torque * t

func _process(_delta):
	if _bounce_invuln > 0.0:
		_bounce_invuln -= _delta
	if target:
		$arrow.look_at(target.global_position)
	# Screen shake decay
	if _shake_intensity > 0.0:
		_shake_intensity = maxf(_shake_intensity - _shake_decay * _delta, 0.0)
		$Camera2D.offset = Vector2(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity)
		)
		if _shake_intensity <= 0.0:
			$Camera2D.offset = Vector2.ZERO
	# Slow-motion & proximity beeps near any landing target (waypoints + final).
	# Skipped for the AI rival: these are GLOBAL / player-facing (Engine.time_scale,
	# the 3D landing camera, beeps) and would hijack the player's race.
	if target and is_instance_valid(target) and flagplaced == false and not ai_controlled:
		# Find the nearest body in the targets group
		var nearest_target: Node2D = target
		var dist_to_target := global_position.distance_to(target.global_position)
		for wp in _waypoint_bodies:
			if not is_instance_valid(wp):
				continue
			var d := global_position.distance_to(wp.global_position)
			if d < dist_to_target:
				dist_to_target = d
				nearest_target = wp
		# Slow-mo approach
		var spd := linear_velocity.length()
		if dist_to_target < 80.0 and spd < 80.0 and spd > 5.0:
			if not _in_slowmo:
				_in_slowmo = true
				Engine.time_scale = 0.7
		else:
			if _in_slowmo:
				_in_slowmo = false
				Engine.time_scale = 1.0
		# 3D Landing mode — activate when close to any target
		# Trigger distance adapts to target size (collision radius + margin)
		var landing_range: float = LANDING_MODE_MIN_RANGE
		for child in nearest_target.get_children():
			if child is CollisionShape2D and child.shape is CircleShape2D:
				landing_range = maxf(child.shape.radius + LANDING_MODE_MARGIN, LANDING_MODE_MIN_RANGE)
				break
		if dist_to_target < landing_range and not _landing_mode_active and not flagplaced:
			_activate_landing_mode(nearest_target, landing_range)
		# Deactivate landing mode if we've drifted out of range, switched targets,
		# or the target became invalid. Hysteresis prevents flicker on borderline orbits.
		if _landing_mode_active:
			var should_deactivate := (
				not is_instance_valid(_landing_active_target)
				or nearest_target != _landing_active_target
				or dist_to_target > _landing_active_range * LANDING_MODE_EXIT_HYSTERESIS
			)
			if should_deactivate:
				_deactivate_landing_mode()
		# Proximity beeps — pitch increases as rocket approaches target
		if dist_to_target < BEEP_RANGE:
			_beep_cooldown -= _delta
			var closeness := 1.0 - (dist_to_target / BEEP_RANGE)
			var interval := lerpf(0.6, 0.1, closeness)
			if _beep_cooldown <= 0.0:
				$ProximityBeep.pitch_scale = lerpf(0.8, 2.0, closeness)
				$ProximityBeep.volume_db = lerpf(-18.0, -3.0, closeness)
				$ProximityBeep.play()
				_beep_cooldown = interval
		else:
			_beep_cooldown = 0.0
	# Magnet: attract nearby crypto pickups
	if magnet_radius > 0.0:
		_attract_crypto()
	# Waypoint checkpoint: save when entering a waypoint's gravity well
	if _waypoint_bodies.size() > 0 and not flagplaced:
		_check_waypoints()
	# Gravity slingshot detection
	if _all_gravity_bodies.size() > 0 and not flagplaced:
		_check_slingshot()
	# Cannon firing
	if _has_cannon:
		_cannon_cooldown = maxf(_cannon_cooldown - _delta, 0.0)
		if Input.is_action_pressed("fire") and _cannon_cooldown <= 0.0:
			_fire_cannon()
			_cannon_cooldown = _cannon_fire_rate
	# Missile firing
	if _has_missile and _missile_ammo > 0:
		_missile_cooldown = maxf(_missile_cooldown - _delta, 0.0)
		if Input.is_action_just_pressed("missile") and _missile_cooldown <= 0.0:
			_fire_missile()
			_missile_cooldown = MISSILE_COOLDOWN
	# Laser beam (hold to fire, drains fuel)
	if _has_laser:
		var laser_active := Input.is_action_pressed("laser") and fuel > 0.0
		_laser_node.set_active(laser_active)
		if laser_active:
			fuel -= _laser_fuel_drain * _delta
			fuel = maxf(fuel, 0.0)
	# EMP pulse
	if _has_emp and _emp_charges > 0:
		if Input.is_action_just_pressed("emp"):
			_fire_emp()
	shipoverlaps = get_node("ShipArea").get_overlapping_bodies()
	footoverlaps = get_node("FootArea").get_overlapping_bodies()
	if (shipoverlaps.size() > 0):
		get_node("RocketSprite").hide()
		if not _try_shield():
			death(shipoverlaps[0])
	else:
		get_node("SkullSprite").hide()
	for i in footoverlaps:
		# Use max(current, recent peak) so a fast crash that the solver damped
		# between frames still trips the threshold. Previously a tail-first
		# high-speed crash into Earth could bounce off without dying.
		var crash_speed: float = maxf(linear_velocity.length(), _recent_max_speed)
		if (crash_speed > crashspeed and i.get_name() != "Rocket"):
			if not _try_shield():
				death(i)
		if(i.is_in_group("targets") and i == target and linear_velocity.length() < landingspeed and flagplaced == false and landattemptnow == false):
			# Angle check — tipped too far = rollover crash
			# Compute tilt relative to target: 0 = tail pointing at target (correct)
			var target_pos: Vector2 = i.global_position
			var dir_to_target: float = (target_pos - global_position).angle()
			var ideal_rot: float = dir_to_target - PI / 2.0  # rocket nose away from target
			var tilt: float = wrapf(rotation - ideal_rot, -PI, PI)
			if absf(tilt) > TILT_DEATH_ANGLE:
				if not _try_shield():
					death(i)
			else:
				moonland()
	# Cancel landing timer only after a grace period of no foot contact
	# (orbiting planets briefly lose contact each frame)
	if !moontimer.is_stopped():
		# Landing countdown beeps — accelerating ticks during 3s landing timer
		_landing_beep_elapsed += _delta
		var progress: float = 1.0 - (moontimer.time_left / moontimerdefault)
		var interval := lerpf(0.5, 0.12, progress)
		var next_beep_time: float = _landing_beep_count * interval
		if _landing_beep_elapsed >= next_beep_time or _landing_beep_count == 0:
			$ProximityBeep.pitch_scale = lerpf(1.2, 2.5, progress)
			$ProximityBeep.volume_db = lerpf(-12.0, -2.0, progress)
			$ProximityBeep.play()
			_landing_beep_count += 1
		var foot_on_target := false
		for i in footoverlaps:
			if i.is_in_group("targets"):
				foot_on_target = true
				break
		if foot_on_target:
			_landing_grace = 0.0
		else:
			_landing_grace += _delta
			if _landing_grace >= LANDING_GRACE_TIME:
				moontimer.stop()
				moontimer.set_wait_time(moontimerdefault)
				landattemptnow = false
				_landing_grace = 0.0

func _capture_initial_dist() -> void:
	# Baseline distance to the pad at level start, for death-forensics pct_through.
	if target and is_instance_valid(target):
		_initial_target_dist = (target.global_position - global_position).length()


func _canonical_hazard(n: String) -> String:
	## Normalize a hazard node name to the canonical key DeathScreen.HAZARD_ADVICE uses:
	## strip trailing instance digits (Martian2 -> Martian) and fold known aliases.
	var s := n
	while s.length() > 0 and s.substr(s.length() - 1, 1).is_valid_int():
		s = s.substr(0, s.length() - 1)
	match s:
		"GammeRay", "GammaRay": return "GammaRay"
		"OrbitingAsteroid", "Asteroid": return "Asteroid"
		"Hull", "Mothership": return "Mothership"
		_: return s


func death(crash_body: Node2D = null):
	# Second-chance bounce: if the player is about to crash into a planet/moon/
	# asteroid and they have a bounce left this attempt, kick them away instead of
	# dying. Allowance is difficulty-scaled (Easy 2, Normal 1, Hard 0).
	if globalvar.level_bounces_used < globalvar.get_bounce_allowance() \
			and crash_body and is_instance_valid(crash_body):
		globalvar.level_bounces_used += 1
		_do_bounce(crash_body)
		return
	# Death forensics (the dimensions the AI play-tester validated as load-bearing).
	var _spd: float = linear_velocity.length()
	var _fuel_frac: float = fuel / maxf(max_fuel, 1.0)
	var _dist: float = -1.0
	if target and is_instance_valid(target):
		_dist = (target.global_position - global_position).length()
	var _t_into: float = (float(Time.get_ticks_msec() - _level_start_ms) / 1000.0) if _level_start_ms > 0 else 0.0
	var _hazard_name: String = ""
	var _cause_type: String = ""
	if crash_body and is_instance_valid(crash_body):
		var _bn: String = crash_body.get_name()
		if crash_body.is_in_group("hazard") or _bn in ["Martian", "BlackHole", "Wormhole", "SolarWind", "Mothership"]:
			_cause_type = "hazard"; _hazard_name = _canonical_hazard(_bn)
		else:
			_cause_type = "crash"
	elif globalvar.pending_hazard_name != "":
		# Killed by a hazard that fired sendDeath (no crash_body on that path).
		_cause_type = "hazard"; _hazard_name = _canonical_hazard(globalvar.pending_hazard_name)
	elif fuel <= 0.0:
		_cause_type = "out_of_fuel"
	else:
		# No crash body, no hazard signal, tank not empty -> deliberate self-destruct.
		_cause_type = "self_destruct"
	globalvar.pending_hazard_name = ""
	var _pct: float = 0.0
	if _initial_target_dist > 0.0 and _dist >= 0.0:
		_pct = clampf(1.0 - _dist / _initial_target_dist, 0.0, 1.0)
	# Raw, full-resolution row -> our own /v1/events backend (no cardinality limits).
	Telemetry.log_event(Telemetry.EVENT_LEVEL_DEATH, {
		"level": globalvar.nowlevel,
		"cause": crash_body.get_name() if (crash_body and is_instance_valid(crash_body)) else "hazard",
		"cause_type": _cause_type,
		"hazard_name": _hazard_name,
		"speed": _spd,
		"fuel_frac": _fuel_frac,
		"dist_to_target": _dist,
		"time_into_level": _t_into,
		"attempt": globalvar.level_attempt,
		"pct_through": _pct,
	})
	# Bucketed funnel row -> Firebase/GA4.
	Analytics.level_death(globalvar.nowlevel, _cause_type, _hazard_name, _pct,
		maxf(_dist, 0.0), _spd, _fuel_frac, _t_into, globalvar.level_attempt)
	# Transient forensics for the death screen advice (NOT persisted). Same fields.
	globalvar.last_death = {
		"level": globalvar.nowlevel,
		"cause": crash_body.get_name() if (crash_body and is_instance_valid(crash_body)) else "hazard",
		"cause_type": _cause_type,
		"hazard_name": _hazard_name,
		"speed": _spd,
		"fuel_frac": _fuel_frac,
		"dist_to_target": _dist,
		"time_into_level": _t_into,
		"attempt": globalvar.level_attempt,
		"pct_through": _pct,
	}
	# Restore normal time if in slow-mo
	if _in_slowmo:
		_in_slowmo = false
		Engine.time_scale = 1.0
	#Stops the timer after death
	var time_labels = get_tree().get_nodes_in_group("time_label")
	if time_labels.size() > 0:
		time_labels[0].stop()
	#Stops the velocity calculator after death
	var velocity_labels = get_tree().get_nodes_in_group("velocity_label")
	if velocity_labels.size() > 0:
		velocity_labels[0].stop()
	# Clean up 3D landing mode
	_deactivate_landing_mode()
	# Haptic feedback on death
	Input.vibrate_handheld(200)
	# Screen shake
	_shake_intensity = 12.0
	if globalvar.sendDeath.is_connected(_on_external_death):
		globalvar.sendDeath.disconnect(_on_external_death)
	if moontimer.timeout.is_connected(flagplanted):
		moontimer.timeout.disconnect(flagplanted)
	# Sprite sheet explosion (legacy)
	get_node("ExplosionSprite").show()
	get_node("RocketSprite").hide()
	get_node("ExplosionSprite").get_node("AnimationPlayer").play("explode")
	# Particle explosion burst
	$ExplosionParticles.restart()
	$ExplosionParticles.emitting = true
	# Layered explosion audio
	$ExplosionSound.play()
	$ExplosionCrunch.play()
	$ExplosionBass.play()
	# Stop proximity beeping
	$ProximityBeep.stop()
	# Track death for achievements
	globalvar.increment_deaths()
	# Skull
	var skull: Sprite2D = get_node("SkullSprite")
	skull.show()
	_animate_skull(skull)
	set_process(false)
	deathtimer.start()


func _animate_skull(skull: Sprite2D) -> void:
	# The scene sets scale to (0.08,0.08) — that's our base size
	const BASE := Vector2(0.08, 0.08)
	# Start from zero — dramatic slam-in
	skull.scale = Vector2.ZERO
	skull.modulate = Color(1, 1, 1, 0.0)
	skull.rotation = -0.5  # start tilted
	# Phase 1: slam in with overshoot + spin
	var intro := create_tween()
	intro.set_ease(Tween.EASE_OUT)
	intro.set_trans(Tween.TRANS_BACK)
	intro.set_parallel(true)
	intro.tween_property(skull, "scale", BASE * 1.3, 0.25)  # overshoot big
	intro.tween_property(skull, "modulate", Color(3, 3, 3, 1.0), 0.15)  # white flash
	intro.tween_property(skull, "rotation", 0.15, 0.25)  # spin to slight tilt
	# Phase 2: settle to base size + color
	var settle := intro.chain()
	settle.set_ease(Tween.EASE_IN_OUT)
	settle.set_trans(Tween.TRANS_ELASTIC)
	settle.set_parallel(true)
	settle.tween_property(skull, "scale", BASE, 0.4)
	settle.tween_property(skull, "modulate", Color(1.0, 0.3, 0.5, 1.0), 0.3)  # hot pink
	settle.tween_property(skull, "rotation", 0.0, 0.3)
	# Phase 3: looping menace pulse
	settle.chain().tween_callback(_start_skull_pulse.bind(skull))


func _start_skull_pulse(skull: Sprite2D) -> void:
	const BASE := Vector2(0.08, 0.08)
	var pulse := create_tween()
	pulse.set_loops(6)
	pulse.set_ease(Tween.EASE_IN_OUT)
	pulse.set_trans(Tween.TRANS_SINE)
	# Grow + glow hot
	pulse.tween_property(skull, "scale", BASE * 1.2, 0.3)
	pulse.parallel().tween_property(skull, "modulate", Color(1.2, 0.1, 0.4, 1.0), 0.3)
	pulse.parallel().tween_property(skull, "rotation", 0.08, 0.3)
	# Shrink + dim + tilt other way
	pulse.tween_property(skull, "scale", BASE * 0.85, 0.3)
	pulse.parallel().tween_property(skull, "modulate", Color(0.7, 0.2, 0.6, 0.75), 0.3)
	pulse.parallel().tween_property(skull, "rotation", -0.08, 0.3)

func moonland():
	landattemptnow = true
	_landing_beep_elapsed = 0.0
	_landing_beep_count = 0
	moontimer.start()


func _activate_landing_mode(landing_target: Node2D = null, trigger_range: float = 150.0) -> void:
	# Skip the cosmetic 3D landing overlay during automated runs (RL training /
	# Movie Maker capture, which pass --capture). It's visual-only — the 2D physics
	# stays the source of truth — but it rebuilds a SubViewport + 3D scene every
	# episode, adding render overhead and per-frame timing jitter right at the
	# critical descent. Production/mobile never pass --capture, so they're unaffected.
	if "--capture" in OS.get_cmdline_args():
		return
	if _landing_mode_active:
		return
	if landing_target == null:
		landing_target = target
	if not landing_target:
		return
	_landing_mode_active = true
	_landing_active_target = landing_target
	_landing_active_range = trigger_range
	_landing_mode = CanvasLayer.new()
	_landing_mode.set_script(LANDING_MODE_SCRIPT)
	_landing_mode.setup(self, landing_target, trigger_range)
	# Add to the scene tree root so it overlays everything
	get_tree().current_scene.add_child(_landing_mode)


func _deactivate_landing_mode() -> void:
	if not _landing_mode_active:
		return
	_landing_mode_active = false
	_landing_active_target = null
	_landing_active_range = 0.0
	if is_instance_valid(_landing_mode):
		_landing_mode.deactivate()
		_landing_mode = null


func _do_bounce(body: Node2D) -> void:
	## Second-chance: bounce the rocket away from `body` instead of dying.
	# Direction away from the crashing body. Fall back to "straight up in world
	# space" if the rocket and body are at exactly the same position.
	var diff := global_position - body.global_position
	var dir := diff.normalized() if diff.length_squared() > 0.0001 else Vector2.UP
	_do_bounce_dir(dir)


func _do_bounce_dir(dir: Vector2) -> void:
	## Shared bounce core — kick the rocket along `dir` and refuel a little.
	# Cancel any in-progress slow-mo or landing countdown so the player resumes
	# normal flight cleanly.
	if _in_slowmo:
		_in_slowmo = false
		Engine.time_scale = 1.0
	if moontimer and not moontimer.is_stopped():
		moontimer.stop()
		landattemptnow = false
	linear_velocity = dir * BOUNCE_SPEED
	angular_velocity *= 0.3
	# Restore some fuel so the player can actually retry
	fuel = minf(fuel + max_fuel * BOUNCE_FUEL_PCT, max_fuel)
	# Subtle haptic + toast
	Input.vibrate_handheld(40)
	_show_bounce_toast()


func _show_bounce_toast() -> void:
	## Yellow "SECOND CHANCE!" label that fades + scales out over ~1.5s.
	var hud := get_node_or_null("../CanvasLayer")
	if hud == null:
		return
	var lbl := Label.new()
	lbl.text = "SECOND CHANCE!"
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_top = 140
	lbl.offset_bottom = 180
	lbl.pivot_offset = Vector2(lbl.size.x * 0.5, lbl.size.y * 0.5)
	lbl.scale = Vector2(0.6, 0.6)
	lbl.modulate = Color(1, 1, 1, 0)
	hud.add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.15)
	tw.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fade := create_tween()
	fade.tween_interval(1.0)
	fade.tween_property(lbl, "modulate:a", 0.0, 0.4)
	fade.tween_callback(lbl.queue_free)

func flagplanted():
	Engine.time_scale = 1.0
	# Clean up 3D landing mode
	_deactivate_landing_mode()
	# Race mode: first to land wins. The controller decides the winner + shows the
	# result; skip the normal level-completion (finaltime / analytics / Victory).
	if globalvar.race_mode and RaceController.active:
		flagplaced = true
		_spawn_landing_dust()
		$CosmonautSprite.show()
		if not ai_controlled:
			globalvar.finaltime = get_node("../CanvasLayer").get_node("TimeLabel").time
			globalvar.level_fuel_remaining = (fuel / max_fuel) * 100.0
		RaceController.on_rocket_landed(self)
		return
	globalvar.finaltime = get_node("../CanvasLayer").get_node("TimeLabel").time
	# Capture fuel remaining as a percentage
	globalvar.level_fuel_remaining = (fuel / max_fuel) * 100.0
	flagplaced = true
	Analytics.launch_complete(globalvar.nowlevel, int(globalvar.finaltime * 1000.0), 0, "win")
	Analytics.activation("first_launch")  # one-time (deduped): first successful launch = activation
	# Landing dust burst
	_spawn_landing_dust()
	# Haptic feedback on successful landing
	Input.vibrate_handheld(100)
	$CosmonautSprite.show()

	if globalvar.endless_mode:
		# Endless: advance wave and reload the endless level
		globalvar.endless_wave += 1
		if globalvar.endless_wave > globalvar.endless_best_wave:
			globalvar.endless_best_wave = globalvar.endless_wave
			PlayGamesManager.on_endless_wave(globalvar.endless_wave)
			GameCenterManager.on_endless_wave(globalvar.endless_wave)
		globalvar.save_game()
		get_tree().change_scene_to_file("res://game/levels/12/EndlessMode.tscn")
	else:
		get_tree().change_scene_to_file("res://game/gui/victory/Victory.tscn")

func switchtomenu():
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")


func _show_death_screen() -> void:
	## Show the DeathScreen overlay instead of jumping straight to menu.
	# Submit endless mode score on death (wave + moonrocks)
	if globalvar.endless_mode and globalvar.endless_wave > 0:
		var elapsed: float = get_node("../CanvasLayer").get_node("TimeLabel").time
		var pct_fuel: float = (fuel / max_fuel) * 100.0
		var moonrocks: int = globalvar.level_crypto_collected
		var wave: int = globalvar.endless_wave
		# Stars based on waves survived: 1-3 = 1★, 4-7 = 2★, 8+ = 3★
		var stars: int = 1
		if wave >= 8:
			stars = 3
		elif wave >= 4:
			stars = 2
		ScoreClient.submit_score(12, elapsed, pct_fuel, moonrocks, stars, wave)
	var death_scene := preload("res://game/gui/death/DeathScreen.tscn")
	get_tree().current_scene.add_child(death_scene.instantiate())


func _on_external_death() -> void:
	## Called by Martian/GammaRay/BlackHole via globalvar.sendDeath signal.
	# Hazards can't kill while in landing mode — would be unfair given the player
	# can't easily evade with the 3D overlay up and the camera locked to target.
	if _landing_mode_active:
		return
	# Brief invulnerability right after a hazard bounce so the same chaser can't
	# instantly re-kill before the player flies clear.
	if _bounce_invuln > 0.0:
		return
	if _try_shield():
		return
	# Second-chance bounce ALSO catches hazard hits (rebalance): bounce away from
	# the nearest hazard and grant a short invuln window instead of dying.
	if globalvar.level_bounces_used < globalvar.get_bounce_allowance():
		globalvar.level_bounces_used += 1
		var hz := _nearest_hazard()
		if hz != null:
			_do_bounce(hz)   # grouped hazards (e.g. black hole) — bounce away from it
		else:
			# Ungrouped chaser (Martian/gamma): reverse out of whatever we flew into.
			var away := (-linear_velocity.normalized()) if linear_velocity.length_squared() > 1.0 else Vector2.UP
			_do_bounce_dir(away)
		_bounce_invuln = BOUNCE_INVULN_TIME
		return
	death()


func _nearest_hazard() -> Node2D:
	## Closest node in the "hazard" group (Martian/gamma/black hole/…), or null.
	var best: Node2D = null
	var best_d := INF
	for h in get_tree().get_nodes_in_group("hazard"):
		if h is Node2D and is_instance_valid(h):
			var d: float = global_position.distance_squared_to((h as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = h
	return best


func _try_shield() -> bool:
	## If shield hits remain, absorb the impact and return true.
	if shield_hits > 0:
		shield_hits -= 1
		# Visual flash — brief white flash then back to normal
		var sprite: Sprite2D = get_node("RocketSprite")
		sprite.show()
		var flash := create_tween()
		flash.tween_property(sprite, "modulate", Color(2, 2, 4, 1), 0.05)
		flash.tween_property(sprite, "modulate", Color.WHITE, 0.2)
		return true
	return false


func _attract_crypto() -> void:
	## Pull nearby crypto pickups toward the rocket.
	var pickups := get_tree().get_nodes_in_group("crypto_pickup")
	for pickup in pickups:
		if not is_instance_valid(pickup):
			continue
		var dist := global_position.distance_to(pickup.global_position)
		if dist < magnet_radius and dist > 5.0:
			var dir: Vector2 = (global_position - pickup.global_position).normalized()
			var strength := 200.0 * (1.0 - dist / magnet_radius)
			pickup.position += dir * strength * get_process_delta_time()


func _check_waypoints() -> void:
	## Detect entering a waypoint planet's gravity well and save checkpoint.
	for body in _waypoint_bodies:
		if not is_instance_valid(body):
			continue
		var iid: int = body.get_instance_id()
		if iid in _visited_waypoints:
			continue
		# Find the gravity Area2D child and check its radius
		var gravity_area: Area2D = null
		for child in body.get_children():
			if child is Area2D:
				gravity_area = child
				break
		if not gravity_area:
			continue
		# Get the collision radius from the Area2D's CollisionShape2D
		var radius := 200.0  # fallback
		for child in gravity_area.get_children():
			if child is CollisionShape2D and child.shape is CircleShape2D:
				radius = child.shape.radius
				break
		var dist := global_position.distance_to(body.global_position)
		if dist < radius:
			_visited_waypoints[iid] = true
			globalvar.save_checkpoint(global_position, linear_velocity, fuel, body.name)
			# Waypoint refueling station — restore fuel on first visit
			var restored := max_fuel * WAYPOINT_FUEL_BONUS
			fuel = minf(fuel + restored, max_fuel)
			_spawn_waypoint_popup(body.global_position, restored, body.name)


func _spawn_waypoint_popup(pos: Vector2, fuel_amount: float, planet_name: String) -> void:
	## Show "+N FUEL — [Planet] Station" popup at the waypoint.
	var label := Label.new()
	label.text = "+%d FUEL — %s Station" % [int(fuel_amount), planet_name]
	label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos - Vector2(80, 30)
	label.z_index = 100
	get_parent().add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 50, 1.2)
	tween.tween_property(label, "modulate:a", 0.0, 1.2)
	tween.chain().tween_callback(label.queue_free)


func _check_slingshot() -> void:
	## Track entry/exit from gravity wells. Award "SLINGSHOT!" on speed gain.
	for body in _all_gravity_bodies:
		if not is_instance_valid(body):
			continue
		var iid: int = body.get_instance_id()
		var radius := _get_gravity_radius(body)
		var dist := global_position.distance_to(body.global_position)
		var current_speed := linear_velocity.length()
		if dist < radius:
			# Inside gravity well — record entry speed if not already tracked
			if iid not in _slingshot_inside:
				_slingshot_inside[iid] = current_speed
		else:
			# Outside gravity well — check if we just exited
			if iid in _slingshot_inside:
				var entry_speed: float = _slingshot_inside[iid]
				_slingshot_inside.erase(iid)
				var speed_gain := current_speed - entry_speed
				if speed_gain >= SLINGSHOT_SPEED_THRESHOLD:
					_spawn_slingshot_effect(body.global_position, speed_gain)


func _get_gravity_radius(body: Node2D) -> float:
	## Find the gravity Area2D collision radius on a planet body.
	for child in body.get_children():
		if child is Area2D:
			for shape_node in child.get_children():
				if shape_node is CollisionShape2D and shape_node.shape is CircleShape2D:
					return shape_node.shape.radius
	return 200.0


func _spawn_slingshot_effect(_planet_pos: Vector2, speed_gain: float) -> void:
	## Visual + audio feedback for a successful gravity slingshot.
	slingshot_achieved.emit(speed_gain)
	# Haptic feedback
	Input.vibrate_handheld(50)
	# Floating "SLINGSHOT!" label
	var label := Label.new()
	label.text = "SLINGSHOT! +%d" % int(speed_gain)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = global_position - Vector2(60, 40)
	label.z_index = 100
	get_parent().add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 60, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_property(label, "scale", Vector2(1.3, 1.3), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_callback(label.queue_free)
	# Speed streak particles — brief trail burst
	var streaks := GPUParticles2D.new()
	streaks.emitting = true
	streaks.one_shot = true
	streaks.amount = 16
	streaks.lifetime = 0.5
	streaks.explosiveness = 0.8
	streaks.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 5.0
	mat.particle_flag_disable_z = true
	# Particles shoot in the direction of travel
	var vel_dir := linear_velocity.normalized()
	mat.direction = Vector3(vel_dir.x, vel_dir.y, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 60.0
	mat.initial_velocity_max = 120.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 30.0
	mat.damping_max = 60.0
	mat.scale_min = 1.5
	mat.scale_max = 3.0
	# Yellow-gold gradient
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.9, 0.3, 0.9),
		Color(1.0, 0.7, 0.1, 0.6),
		Color(1.0, 0.5, 0.0, 0.0),
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	streaks.process_material = mat
	var tex = load("res://art/effects/star.png")
	if tex:
		streaks.texture = tex
	add_child(streaks)
	# Audio — quick ascending ding using proximity beep pitched high
	$ProximityBeep.pitch_scale = 2.5
	$ProximityBeep.volume_db = -4.0
	$ProximityBeep.play()
	# Cleanup
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(streaks):
			streaks.queue_free()
	)


func _apply_checkpoint() -> void:
	## Restore rocket state from a saved waypoint checkpoint.
	global_position = globalvar.checkpoint_position
	linear_velocity = globalvar.checkpoint_velocity
	fuel = globalvar.checkpoint_fuel
	# Mark waypoints up to the checkpoint as already visited
	for body in _waypoint_bodies:
		if is_instance_valid(body):
			_visited_waypoints[body.get_instance_id()] = true
			if body.name == globalvar.checkpoint_planet_name:
				break


func _spawn_landing_dust() -> void:
	## Burst of dust particles from the rocket's feet on successful landing.
	var dust := GPUParticles2D.new()
	dust.emitting = true
	dust.one_shot = true
	dust.amount = 24
	dust.lifetime = 0.6
	dust.explosiveness = 0.9
	dust.local_coords = false
	dust.position = Vector2(0, 20)  # below feet
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 8.0
	mat.particle_flag_disable_z = true
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 80.0
	mat.gravity = Vector3(0, 30, 0)
	mat.damping_min = 20.0
	mat.damping_max = 40.0
	mat.scale_min = 1.0
	mat.scale_max = 3.0
	# Dust color: warm tan fading to transparent
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0.85, 0.75, 0.55, 0.8),
		Color(0.7, 0.6, 0.4, 0.5),
		Color(0.5, 0.4, 0.3, 0.0),
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	dust.process_material = mat
	# Use the glow circle texture for soft dust blobs
	var tex = load("res://art/effects/glowingCircle.png")
	if tex:
		dust.texture = tex
	add_child(dust)
	# Auto-cleanup after particles finish
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(dust):
			dust.queue_free()
	)


func _fire_cannon() -> void:
	## Spawn a bullet from the rocket's nose. Auto-aims at nearest enemy on mobile.
	var forward_dir := -Vector2.from_angle(rotation - PI / 2.0)
	# Auto-aim: find closest enemy in front of the ship
	var aim_target := _find_auto_aim_target()
	var fire_dir: Vector2
	if aim_target:
		fire_dir = (aim_target.global_position - global_position).normalized()
	else:
		fire_dir = forward_dir
	var bullet: Area2D = BULLET_SCENE.instantiate()
	get_parent().add_child(bullet)
	bullet.setup(global_position + fire_dir * 25.0, fire_dir)
	# Light haptic on fire
	Input.vibrate_handheld(20)


func _find_auto_aim_target() -> Node2D:
	## Find the nearest enemy within auto-aim cone in front of the ship.
	var forward_dir := -Vector2.from_angle(rotation - PI / 2.0)
	var best_node: Node2D = null
	var best_dist := AUTO_AIM_RANGE
	# Search CharacterBody2D children of the level (martians + asteroids)
	for node in get_parent().get_children():
		if node == self:
			continue
		if not (node is CharacterBody2D):
			continue
		if not is_instance_valid(node):
			continue
		var to_enemy: Vector2 = node.global_position - global_position
		var dist := to_enemy.length()
		if dist > AUTO_AIM_RANGE or dist < 10.0:
			continue
		# Check if within aiming cone
		var angle_diff := absf(forward_dir.angle_to(to_enemy.normalized()))
		if angle_diff > AUTO_AIM_CONE:
			continue
		if dist < best_dist:
			best_dist = dist
			best_node = node
	return best_node


func _fire_missile() -> void:
	## Launch a homing missile at the nearest enemy.
	var forward_dir := -Vector2.from_angle(rotation - PI / 2.0)
	var target_node := _find_missile_target()
	var fire_dir: Vector2
	if target_node:
		fire_dir = (target_node.global_position - global_position).normalized()
	else:
		fire_dir = forward_dir
	var missile: Area2D = MISSILE_SCENE.instantiate()
	get_parent().add_child(missile)
	missile.setup(global_position + fire_dir * 30.0, fire_dir, target_node)
	_missile_ammo -= 1
	Input.vibrate_handheld(40)


func _find_missile_target() -> Node2D:
	## Find the nearest enemy within missile lock range (any direction).
	var best_node: Node2D = null
	var best_dist := MISSILE_AIM_RANGE
	for node in get_parent().get_children():
		if node == self:
			continue
		if not (node is CharacterBody2D):
			continue
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist > MISSILE_AIM_RANGE or dist < 10.0:
			continue
		if dist < best_dist:
			best_dist = dist
			best_node = node
	return best_node


func _fire_emp() -> void:
	## Fire an EMP pulse that destroys all enemies in radius.
	var pulse := Node2D.new()
	pulse.set_script(EMPPulseScript)
	get_parent().add_child(pulse)
	pulse.fire(global_position, _emp_radius)
	_emp_charges -= 1
	# Screen shake + haptic
	_shake_intensity = 8.0
	Input.vibrate_handheld(80)
