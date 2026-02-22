extends CharacterBody2D

@onready var p = get_node("../../Rocket")
var motion = Vector2.ZERO
@export var speed = 40
var follow = false

## How close the rocket must be to a landing target for martians to back off
const LANDING_SAFE_RADIUS := 120.0


func _physics_process(delta):
	if follow and not _rocket_near_target():
		$Ship/AnimatedSprite2D.show()
		motion = position.direction_to(p.position) * speed
		look_at(p.position)
	else:
		motion = Vector2.ZERO
		$Ship/AnimatedSprite2D.hide()
	set_velocity(motion)
	move_and_slide()
	motion = velocity
	# Kill the rocket on contact
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision.get_collider().name == "Rocket":
			globalvar.sendDeath.emit()
			return


func _rocket_near_target() -> bool:
	## Returns true if the rocket is close to any landing target ("targets" group).
	if not p or not is_instance_valid(p):
		return false
	var targets := get_tree().get_nodes_in_group("targets")
	for target in targets:
		if p.global_position.distance_to(target.global_position) < LANDING_SAFE_RADIUS:
			return true
	return false


func _on_detectArea_body_entered(body):
	if body.name == "Rocket":
		follow = true

func _on_detectArea_body_exited(body):
	if body.name == "Rocket":
		follow = false
