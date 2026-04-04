extends Label

var velocity = 0.0
var running = true

func _ready():
	set_process(true)
	add_to_group("velocity_label")

func _process(delta):
	if not running:
		return
	velocity = get_node("../../Rocket").linear_velocity.length()
	text = "Velocity: %8.2f" % velocity
func stop():
	running = false
