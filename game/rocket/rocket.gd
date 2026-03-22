extends RigidBody2D

# Ship control variables — base values overridden by upgrades in _ready()
var thrust = Vector2(0, 350)
var reverse_thrust = Vector2(0, 350)
var torque = 5000
var shipoverlaps
var footoverlaps
var crashspeed = 100.0
var landingspeed = 40.0
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

# Screen shake state
var _shake_intensity: float = 0.0
var _shake_decay: float = 5.0

# Slow-motion landing state
var _in_slowmo: bool = false

# 3D Landing mode
var _landing_mode: CanvasLayer = null
var _landing_mode_active: bool = false
const LANDING_MODE_MIN_RANGE := 80.0   # minimum trigger distance (small bodies)
const LANDING_MODE_MARGIN := 60.0      # pixels above collision surface to trigger
const TILT_DEATH_ANGLE := 0.6109  # ~35 degrees

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

func _ready():
	# Add to group so HUD widgets (FuelBar etc.) can find us
	add_to_group("rocket")
	# Hide menu banner ad during gameplay
	AdManager.hide_banner()
	# Reset per-level stats
	globalvar.reset_level_stats()
	# Apply upgrades from globalvar
	thrust = Vector2(0, globalvar.get_thrust_force())
	reverse_thrust = Vector2(0, globalvar.get_reverse_thrust_force())
	max_fuel = globalvar.get_max_fuel()
	fuel = max_fuel * globalvar.get_starting_fuel_mult()
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

func _integrate_forces(state):
	var dt = state.step
	var has_fuel = fuel > 0.0

	if has_fuel and Input.is_action_pressed("thrust"):
		constant_force = state.total_gravity - thrust.rotated(rotation)
		get_node("RearThrust").show()
		get_node("RevThrust").hide()
		fuel -= fuel_drain * dt
		if not $ThrustSound.playing:
			$ThrustSound.play()
	elif has_fuel and Input.is_action_pressed("revthrust"):
		constant_force = state.total_gravity + reverse_thrust.rotated(rotation)
		get_node("RearThrust").hide()
		get_node("RevThrust").show()
		fuel -= fuel_drain * dt
		if not $ThrustSound.playing:
			$ThrustSound.play()
	else:
		constant_force = state.total_gravity
		get_node("RearThrust").hide()
		get_node("RevThrust").hide()
		$ThrustSound.stop()

	fuel = maxf(fuel, 0.0)

	var t = int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left"))
	constant_torque = torque * t

func _process(_delta):
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
	# Slow-motion & proximity beeps near any landing target (waypoints + final)
	if target and flagplaced == false:
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
			death()
	else:
		get_node("SkullSprite").hide()
	for i in footoverlaps:
		if (linear_velocity.length() > crashspeed and i.get_name() != "Rocket"):
			if not _try_shield():
				death()
		if(i.is_in_group("targets") and i == target and linear_velocity.length() < landingspeed and flagplaced == false and landattemptnow == false):
			# Angle check — tipped too far = rollover crash
			# Compute tilt relative to target: 0 = tail pointing at target (correct)
			var target_pos: Vector2 = i.global_position
			var dir_to_target: float = (target_pos - global_position).angle()
			var ideal_rot: float = dir_to_target - PI / 2.0  # rocket nose away from target
			var tilt: float = wrapf(rotation - ideal_rot, -PI, PI)
			if absf(tilt) > TILT_DEATH_ANGLE:
				if not _try_shield():
					death()
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

func death():
	# Restore normal time if in slow-mo
	if _in_slowmo:
		_in_slowmo = false
		Engine.time_scale = 1.0
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
	if _landing_mode_active:
		return
	if landing_target == null:
		landing_target = target
	if not landing_target:
		return
	_landing_mode_active = true
	var LandingModeScript = load("res://game/rocket/LandingMode.gd")
	_landing_mode = CanvasLayer.new()
	_landing_mode.set_script(LandingModeScript)
	_landing_mode.setup(self, landing_target, trigger_range)
	# Add to the scene tree root so it overlays everything
	get_tree().current_scene.add_child(_landing_mode)


func _deactivate_landing_mode() -> void:
	if not _landing_mode_active:
		return
	_landing_mode_active = false
	if is_instance_valid(_landing_mode):
		_landing_mode.deactivate()
		_landing_mode = null

func flagplanted():
	Engine.time_scale = 1.0
	# Clean up 3D landing mode
	_deactivate_landing_mode()
	globalvar.finaltime = get_node("../CanvasLayer").get_node("TimeLabel").time
	# Capture fuel remaining as a percentage
	globalvar.level_fuel_remaining = (fuel / max_fuel) * 100.0
	flagplaced = true
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
	var death_scene := preload("res://game/gui/death/DeathScreen.tscn")
	get_tree().current_scene.add_child(death_scene.instantiate())


func _on_external_death() -> void:
	## Called by Martian/GammaRay via globalvar.sendDeath signal.
	if not _try_shield():
		death()


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
