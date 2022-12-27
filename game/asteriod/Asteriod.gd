extends KinematicBody2D

var movespeed = 1.01
var dir = Vector2(1,1)

func _ready():
	set_process(false)
	yield(get_tree().create_timer(1),"timeout")
	set_process(true)

func _physics_process(delta):
	$Sprite.rotation_degrees += 2
	dir.x *=  movespeed
	dir.y *= movespeed
	move_and_slide(dir)

func move_landR():
	randomize()
	if (randf()<0.5):
		global_position.x = -700
	if global_position.x < 0 :
		dir = Vector2(1,rand_range(-1,1))
	else:
		dir = Vector2(-1,rand_range(-1,1))

func move_tandB():
	randomize()
	if (randf()<0.5):
		global_position.y = -400
	if global_position.y < 0 :
		dir = Vector2(rand_range(-1,1),-1)
	else:
		dir = Vector2(rand_range(-1,1),1)
