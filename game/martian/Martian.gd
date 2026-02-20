extends CharacterBody2D

@onready var p = get_node("../../Rocket")
var motion = Vector2.ZERO
@export var speed = 40
var follow = false

func _physics_process(delta):
	if follow == true:
		$Ship/AnimatedSprite2D.show()
		motion = position.direction_to(p.position) * speed
		look_at(p.position)
	else:
		motion = Vector2.ZERO
		$Ship/AnimatedSprite2D.hide()
	set_velocity(motion)
	move_and_slide()
	motion = velocity
	
func _on_detectArea_body_entered(body):
	if body.name == "Rocket":
		follow = true

func _on_detectArea_body_exited(body):
	if body.name == "Rocket":
		follow = false
