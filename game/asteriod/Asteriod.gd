extends CharacterBody2D

var movespeed = 1.005
var max_speed = 300.0
var dir = Vector2(1,1)
var _rocket: Node2D = null

func _ready():
	set_process(false)
	await get_tree().create_timer(1).timeout
	set_process(true)
	# Cache rocket reference for despawn distance check
	_rocket = get_parent().get_node_or_null("Rocket")

func _physics_process(_delta):
	$Sprite2D.rotation_degrees += 2
	dir.x *= movespeed
	dir.y *= movespeed
	# Cap speed so asteroids don't accelerate to infinity
	if dir.length() > max_speed:
		dir = dir.normalized() * max_speed
	set_velocity(dir)
	move_and_slide()
	# Despawn when far from rocket (or far from origin if rocket is gone)
	var ref_pos = _rocket.global_position if _rocket and is_instance_valid(_rocket) else Vector2.ZERO
	if global_position.distance_to(ref_pos) > 2000.0:
		queue_free()

func move_landR():
	if (randf()<0.5):
		global_position.x -= 700
		dir = Vector2(1,randf_range(-1,1))
	else:
		global_position.y += 700
		dir = Vector2(-1,randf_range(-1,1))

func move_tandB():
	if (randf()<0.5):
		global_position.y -= 400
		dir = Vector2(randf_range(-1,1),1)
	else:
		global_position.y += 400
		dir = Vector2(randf_range(-1,1),-1)
