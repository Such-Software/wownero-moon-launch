extends Node2D

var gammaray = load("res://game/gammaray/GammeRay.tscn")

func _ready():
	globalvar.nowlevel = 3
	var space = get_world_2d().get_space()
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, 0)
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)

func add_laser():
	var g_ray = gammaray.instantiate()
	add_child(g_ray)
	if randf()<0.5:
		g_ray.global_position = $Rocket.global_position+ Vector2(0,randf_range(-400,400))
		g_ray.move_landR()
	else:
		g_ray.global_position = $Rocket.global_position+ Vector2(randf_range(-700,700),0)
		g_ray.move_tandB()

func _on_Timer_timeout():
	add_laser()
	$Timer.wait_time= randf_range(2,5)
