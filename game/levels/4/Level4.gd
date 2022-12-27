extends Node2D

var gammaray = load("res://game/gammaray/GammeRay.tscn")
var asteriod = load("res://game/asteriod/Asteriod.tscn")
var asteriod2 = load("res://game/asteriod/Asteriod2.tscn")

func _ready():
	globalvar.nowlevel = 4
	var space = get_world_2d().get_space()
	Physics2DServer.area_set_param(space, Physics2DServer.AREA_PARAM_GRAVITY, 0)
	Physics2DServer.area_set_param(space, Physics2DServer.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)

func add_laser():
	var g_ray = gammaray.instance()
	add_child(g_ray)
	set_position(g_ray)

func set_position(data):
	randomize()
	if randf()<0.5:
		data.global_position = $Rocket.global_position+ Vector2(700,rand_range(-400,400))
		data.move_landR()
	else:
		data.global_position = $Rocket.global_position+ Vector2(rand_range(-700,700),400)
		data.move_tandB()

func add_asteriod():
	var ast = asteriod.instance()
	randomize()
	if randf() < 0.5:ast = asteriod2.instance()
	add_child(ast)
	set_position(ast)

func _on_Timer_timeout():
	add_laser()
	$RayTimer.wait_time= rand_range(3,6)

func _on_AsteriodTimer_timeout():
	add_asteriod()
	$AsteriodTimer.wait_time = rand_range(1,3)
