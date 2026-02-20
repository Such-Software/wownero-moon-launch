extends Area2D

func _process(delta):
	print(gravity_point)

func _ready():
	gravity_point = true
	gravity = 9.8
