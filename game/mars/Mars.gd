extends CharacterBody2D

func _physics_process(delta):
	set_velocity(Vector2(0.8,0.8))
	move_and_slide()

