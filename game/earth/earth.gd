extends CharacterBody2D

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func _process(delta):
	set_velocity(Vector2(0.1,0.2))
	move_and_slide()
	#pass
