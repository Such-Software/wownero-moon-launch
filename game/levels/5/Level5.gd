extends Node2D

var gammaray = load("res://game/gammaray/GammeRay.tscn")
var asteriod = load("res://game/asteriod/Asteriod.tscn")
var asteriod2 = load("res://game/asteriod/Asteriod2.tscn")
var orbiting_ast = load("res://game/asteriod/OrbitingAsteroid.tscn")

func _ready():
	globalvar.nowlevel = 5
	# Orbiting asteroid obstacles around waypoint planets
	_spawn_orbiting($Moon, 2, 100.0, 1.0)
	_spawn_orbiting($Jupiter, 3, 140.0, 0.8)
	var space = get_world_2d().get_space()
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, 0)
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR, Vector2(0,1))
	set_process(true)

func add_laser():
	var g_ray = gammaray.instantiate()
	add_child(g_ray)
	randomize_spawn_position(g_ray)

func randomize_spawn_position(data):
	if randf() < 0.5:
		data.global_position = $Rocket.global_position + Vector2(0, randf_range(-400, 400))
		data.move_landR()
	else:
		data.global_position = $Rocket.global_position + Vector2(randf_range(-700, 700), 0)
		data.move_tandB()

func add_asteriod():
	var ast = asteriod.instantiate()
	if randf() < 0.5:
		ast = asteriod2.instantiate()
	add_child(ast)
	randomize_spawn_position(ast)

func _on_RayTimer_timeout():
	add_laser()
	$RayTimer.wait_time = randf_range(3, 6) * globalvar.get_spawn_interval_mult()

func _on_AsteriodTimer_timeout():
	add_asteriod()
	$AsteriodTimer.wait_time = randf_range(3, 5) * globalvar.get_spawn_interval_mult()

func _spawn_orbiting(planet: Node2D, count: int, radius: float, speed: float) -> void:
	for i in range(count):
		var ast = orbiting_ast.instantiate()
		add_child(ast)
		ast.setup(planet, radius + randf_range(-20, 30), speed * randf_range(0.8, 1.3))
