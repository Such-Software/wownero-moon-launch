extends Label

# class member variables go here, for example:
# var a = 2
# var b = "textvar"
var velocity = 0.0

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	set_process(true)

func _process(delta):
	# velocity = get_node("res://game/rocket/Rocket.tscn").get_linear_velocity()
	velocity = get_node("../../Rocket").get_linear_velocity().length()
	#print(velocity)
	set_text("Velocity: %8.2f" % velocity)
