extends Node2D

var gammaray = load("res://game/gammaray/GammeRay.tscn")

func _ready():
	globalvar.nowlevel = 3
	var space = get_world_2d().get_space()
	Physics2DServer.area_set_param(space, Physics2DServer.AREA_PARAM_GRAVITY, 0)
	Physics2DServer.area_set_param(space, Physics2DServer.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)

func add_laser():
	randomize()
	var g_ray = gammaray.instance()
	add_child(g_ray)
	g_ray.global_position = $Rocket.global_position+ Vector2(700,rand_range(-400,400))
	if (randf()<0.5):
		g_ray.global_position.x = -700
	if g_ray.global_position.x < 0 :
		g_ray.rotation_degrees = rand_range(-45,45)
	else:
#		g_ray.growing_value = -1
		g_ray.rotation_degrees = rand_range(135,225)

func _on_Timer_timeout():
	add_laser()
	$Timer.wait_time= rand_range(2,5)
