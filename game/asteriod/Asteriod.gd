extends CharacterBody2D

var movespeed = 1.01
var dir = Vector2(1,1)

func _ready():
	set_process(false)
	await get_tree().create_timer(1).timeout
	set_process(true)

func _physics_process(delta):
	$Sprite2D.rotation_degrees += 2
	dir.x *=  movespeed
	dir.y *= movespeed
	set_velocity(dir)
	move_and_slide()

func move_landR():
	randomize()
	if (randf()<0.5):
		global_position.x -= 700
		dir = Vector2(1,randf_range(-1,1))
	else:
		global_position.y += 700
		dir = Vector2(-1,randf_range(-1,1))

func move_tandB():
	randomize()
	if (randf()<0.5):
		global_position.y -= 400
		dir = Vector2(randf_range(-1,1),1)
	else:
		global_position.y += 400
		dir = Vector2(randf_range(-1,1),-1)
