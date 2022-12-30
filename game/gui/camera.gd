extends Camera2D



var player

func _ready():
	player= get_node("../Rocket")
	

func _process(delta):
	position.x=player.position.x
	position.y=player.position.y
