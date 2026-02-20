extends Label

var velocity = 0.0

func _ready():
	set_process(true)

func _process(delta):
	velocity = get_node("../../Rocket").linear_velocity.length()
	text = "Velocity: %8.2f" % velocity
