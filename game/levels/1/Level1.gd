extends Node2D

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func _process(delta):
	pass

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	var space = get_world_2d().get_space()
	Physics2DServer.area_set_param(space, Physics2DServer.AREA_PARAM_GRAVITY, 0)
	Physics2DServer.area_set_param(space, Physics2DServer.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)
