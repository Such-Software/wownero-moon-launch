extends KinematicBody2D

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func _process(delta):
	move_and_slide(Vector2(0.1,0.2))
	#pass
