extends KinematicBody2D

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func _physics_process(delta):
	move_and_slide(Vector2(0.8,0.8))

