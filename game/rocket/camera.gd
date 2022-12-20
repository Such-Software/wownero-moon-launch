extends Camera2D

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func _process(delta):
	var current_pos = position
	position = Vector2(current_pos.x - 200*delta, current_pos.y - delta)

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	pass
