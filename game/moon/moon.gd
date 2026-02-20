extends CharacterBody2D

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func _physics_process(delta):
	set_velocity(Vector2(0.8,0.8))
	move_and_slide()

