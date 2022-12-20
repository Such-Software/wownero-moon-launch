extends Label

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

var time = 0

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	set_process(true)

func _process(delta):
	time += delta
	set_text("Time: %8.2f" % time)
