extends RayCast2D

var is_casting = false setget set_is_casting

var growing_value = 1

func _ready():
	set_is_casting(true)
	yield(get_tree().create_timer(10),"timeout")
	set_is_casting(false)
	queue_free()

func _physics_process(delta):
	var cast_point := cast_to
	force_raycast_update()
	$CollisionParticles2D.emitting = is_colliding()
	
	if is_colliding():
		cast_point = to_local(get_collision_point())
		$CollisionParticles2D.global_rotation = get_collision_normal().angle()
		$CollisionParticles2D.position = cast_point
		if get_collider().name == 'Rocket':
			globalvar.emit_signal("sendDeath")
	cast_to.x += 4*growing_value
	$Line2D.points[0].x += 1*growing_value
	$Line2D.points[1] = cast_point
	$BeamParticles2D.position = cast_point*0.5
	$BeamParticles2D.process_material.emission_box_extents.x = cast_point.length() *0.5
	
func set_is_casting(cast):
	is_casting=cast
#	$BeamParticles2D.emitting = is_casting
#	$CastingParticles2D.emitting = is_casting
	if is_casting:
		appear()
	else:
		$CollisionParticles2D.emitting = false
		disappear()
	set_physics_process(is_casting)
	
func appear():
	$Tween.stop_all()
	$Tween.interpolate_property($Line2D,"width",0,10,1)
	$Tween.start()
	
func disappear():
	$Tween.stop_all()
	$Tween.interpolate_property($Line2D,"width",10,0,0.1)
	$Tween.start()
