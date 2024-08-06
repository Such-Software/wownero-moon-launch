extends Area2D

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func _process(delta):
	#pass
	print(is_gravity_a_point())

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
#	set_fixed_process(true)
	set_gravity_is_point(true)
	set_gravity(9.8)
