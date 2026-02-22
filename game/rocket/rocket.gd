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

func _ready():
	# Add to group so HUD widgets (FuelBar etc.) can find us
	add_to_group("rocket")
	# Apply upgrades from globalvar
	thrust = Vector2(0, globalvar.get_thrust_force())
	reverse_thrust = Vector2(0, globalvar.get_reverse_thrust_force())
	max_fuel = globalvar.get_max_fuel()
	fuel = max_fuel
	fuel_drain = globalvar.get_fuel_drain()
	crashspeed = globalvar.get_crash_speed()
	landingspeed = globalvar.get_landing_speed()
	torque = int(globalvar.get_torque())
	shield_hits = globalvar.get_shield_hits()
	magnet_radius = globalvar.get_magnet_radius()
	# Turn on processes and monitors
	set_process(true)
	contact_monitor = true
	max_contacts_reported = 3
	# Setup sprites
	get_node("SkullSprite").hide()
	get_node("ExplosionSprite").hide()
	get_node("CosmonautSprite").hide()
	# Initialize timers
	deathtimer = Timer.new()
	deathtimer.set_wait_time(3)
	deathtimer.set_one_shot(true)
	deathtimer.connect("timeout", switchtomenu)
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
			target = i

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
	# Magnet: attract nearby crypto pickups
	if magnet_radius > 0.0:
		_attract_crypto()
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
		if(i.is_in_group("targets") and linear_velocity.length() < landingspeed and flagplaced == false and landattemptnow == false):
			moonland()
	# Cancel landing timer only after a grace period of no foot contact
	# (orbiting planets briefly lose contact each frame)
	if !moontimer.is_stopped():
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
	if globalvar.sendDeath.is_connected(_on_external_death):
		globalvar.sendDeath.disconnect(_on_external_death)
	if moontimer.timeout.is_connected(flagplanted):
		moontimer.timeout.disconnect(flagplanted)
	get_node("ExplosionSprite").show()
	get_node("RocketSprite").hide()
	get_node("ExplosionSprite").get_node("AnimationPlayer").play("explode")
	$ExplosionSound.play()
	var skull: Sprite2D = get_node("SkullSprite")
	skull.show()
	_animate_skull(skull)
	set_process(false)
	deathtimer.start()


func _animate_skull(skull: Sprite2D) -> void:
	# The scene sets scale to (0.08,0.08) — that's our base size
	const BASE := Vector2(0.08, 0.08)
	# Dramatic entrance: scale up from 0 with slight overshoot
	skull.scale = Vector2.ZERO
	skull.modulate = Color(1, 0.2, 0.2, 0.0)
	var intro := create_tween()
	intro.set_ease(Tween.EASE_OUT)
	intro.set_trans(Tween.TRANS_BACK)
	intro.set_parallel(true)
	intro.tween_property(skull, "scale", BASE, 0.4)
	intro.tween_property(skull, "modulate", Color(1, 0.3, 0.3, 1.0), 0.3)
	# After intro, start looping glow pulse
	intro.chain().tween_callback(_start_skull_pulse.bind(skull))


func _start_skull_pulse(skull: Sprite2D) -> void:
	# Looping pulse: subtle scale + red glow shift around the base 0.08
	const BASE := Vector2(0.08, 0.08)
	var pulse := create_tween()
	pulse.set_loops(6)
	pulse.set_ease(Tween.EASE_IN_OUT)
	pulse.set_trans(Tween.TRANS_SINE)
	pulse.tween_property(skull, "scale", BASE * 1.15, 0.35)
	pulse.parallel().tween_property(skull, "modulate", Color(1.0, 0.15, 0.1, 1.0), 0.35)
	pulse.tween_property(skull, "scale", BASE * 0.9, 0.35)
	pulse.parallel().tween_property(skull, "modulate", Color(0.8, 0.25, 0.2, 0.7), 0.35)

func moonland():

	#set_process(false)
	landattemptnow = true
#	moontimer.set_active(true)
	#get_tree().get_root().set_disable_input(true)
	moontimer.start()

func flagplanted():
	globalvar.finaltime = get_node("../CanvasLayer").get_node("TimeLabel").time
	flagplaced = true

	#get_tree().get_root().set_disable_input(false)
	$CosmonautSprite.show()
	get_tree().change_scene_to_file("res://game/gui/victory/Victory.tscn")

func switchtomenu():
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")


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
