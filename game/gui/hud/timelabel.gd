extends Label

var time = 0

func _ready():
	set_process(true)

func _process(delta):
	time += delta
	text = "Time: %8.2f" % time
