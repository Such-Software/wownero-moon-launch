extends RigidBody2D

# Ship control variables
var thrust = Vector2(0, 350)
var torque = 5000
var shipoverlaps
var footoverlaps
var crashspeed = 100
var landingspeed = 40
# Timer variables
var deathtimer 
var moontimer
var moontimerdefault = 3
var landattempttimer
# Mission variables
var landattemptnow = false
var flagplaced = false

func _ready():
	# Turn on processes and monitors
	set_process(true)
	set_contact_monitor(true)
	set_max_contacts_reported(3)
	# Setup sprites
	get_node("SkullSprite").hide()
	get_node("ExplosionSprite").hide()
	get_node("CosmonautSprite").hide()
	# Initialize timers
	deathtimer = Timer.new()
	deathtimer.set_wait_time(3)
	deathtimer.set_one_shot(true)
	deathtimer.connect("timeout", self, "switchtomenu")
	add_child(deathtimer)
	moontimer = Timer.new()
	moontimer.set_wait_time(moontimerdefault)
	moontimer.set_one_shot(true)
	moontimer.connect("timeout", self, "flagplanted")
	add_child(moontimer)
	globalvar.connect("sendDeath",self,'death')
	#print(get_node("../../MoonSpace").get_name())

func _integrate_forces(state):
	if Input.is_action_pressed("thrust"):
		set_applied_force(state.get_total_gravity() - thrust.rotated(rotation))
		get_node("RearThrust").show()
		get_node("RevThrust").hide()
		if not $ThrustSound.playing:
			$ThrustSound.play()
	elif Input.is_action_pressed("revthrust"):
		set_applied_force(state.get_total_gravity() + thrust.rotated(rotation))
		get_node("RearThrust").hide()
		get_node("RevThrust").show()
		if not $ThrustSound.playing:
			$ThrustSound.play()
	else:
		set_applied_force(state.get_total_gravity() + Vector2())
		get_node("RearThrust").hide()
		get_node("RevThrust").hide()
		$ThrustSound.stop()
#		$RevThrustSound.stop()

	var t = int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left"))
	set_applied_torque(torque * t)


func _process(delta):
	shipoverlaps = get_node("ShipArea").get_overlapping_bodies()
	footoverlaps = get_node("FootArea").get_overlapping_bodies()
	if (shipoverlaps.size() > 1):
		get_node("RocketSprite").hide()
		death()
	else:
		get_node("SkullSprite").hide()
	for i in footoverlaps:
		if (get_linear_velocity().length() > crashspeed and i.get_name() != "Rocket"):
			death()
		if((i.get_name() == "Moon" or i.get_name() == "Mars" or i.get_name() == "Venus" or i.get_name() == "IO")  and get_linear_velocity().length() < landingspeed and flagplaced == false and landattemptnow == false):
			moonland()
	if !moontimer.is_stopped() and footoverlaps.size() < 2:
		moontimer.stop()
		moontimer.set_wait_time(moontimerdefault)
		landattemptnow = false


func death():
	globalvar.disconnect("sendDeath",self,'death')
	moontimer.disconnect("timeout", self, "flagplanted")
	get_node("ExplosionSprite").show()
	get_node("RocketSprite").hide()
	get_node("ExplosionSprite").get_node("AnimationPlayer").play("explode")
	$ExplosionSound.play()
	get_node("SkullSprite").show()
	set_process(false)
	deathtimer.start()

func moonland():
	print("START MOONLAND")
	#set_process(false)
	landattemptnow = true
#	moontimer.set_active(true)
	#get_tree().get_root().set_disable_input(true)
	moontimer.start()

func flagplanted():
	globalvar.finaltime = get_node("../CanvasLayer").get_node("TimeLabel").get('time')
	flagplaced = true
	print("FLAG PLACED")
	#get_tree().get_root().set_disable_input(false)
	$CosmonautSprite.show()
	get_tree().change_scene("res://game/gui/victory/Victory.tscn")

func switchtomenu():
	get_tree().change_scene("res://game/gui/menu/Menu.tscn")
