extends Node2D

var martian = load("res://game/martian/Martian.tscn")

func _ready():
	var space = get_world_2d().get_space()
	Physics2DServer.area_set_param(space, Physics2DServer.AREA_PARAM_GRAVITY, 0)
	Physics2DServer.area_set_param(space, Physics2DServer.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)
	add_martians()
	
func add_martians():
	var m = martian.instance()
	m.position = $Rocket.position + Vector2(1024,600)
