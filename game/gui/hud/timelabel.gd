extends Label

var time = 0
var running = true

func _ready():
	set_process(true)
	add_to_group("time_label")

func _process(delta):
	if not running:
		return
	time += delta
	text = "Time: %8.2f" % time
	
func stop():
	running = false
