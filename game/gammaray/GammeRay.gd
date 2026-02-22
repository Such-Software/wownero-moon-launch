extends RayCast2D

var is_casting = false: set = set_is_casting

var growing_value = 1

func _ready():
	set_is_casting(true)
	await get_tree().create_timer(4.0).timeout
	_fade_out()

func move_landR():
	if (randf()<0.5):
		global_position.x -= 700
		rotation_degrees = randf_range(-45,45)
	else:
		global_position.x += 700
		rotation_degrees = randf_range(135,225)

func move_tandB():
	if (randf()<0.5):
		global_position.y -= 400
		rotation_degrees = randf_range(45,135)
	else:
		global_position.y += 400
		rotation_degrees = randf_range(-45,-135)

func _physics_process(_delta):
	var cast_point := target_position
	force_raycast_update()
	$CollisionParticles2D.emitting = is_colliding()
	
	if is_colliding():
		cast_point = to_local(get_collision_point())
		$CollisionParticles2D.global_rotation = get_collision_normal().angle()
		$CollisionParticles2D.position = cast_point
		var collider = get_collider()
		if collider and collider.name == 'Rocket':
			globalvar.sendDeath.emit()
	target_position.x += 4*growing_value
#	$Line2D.points[0].x += 1*growing_value
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
	var tween = create_tween()
	tween.tween_property($Line2D, "width", 10, 1.0).from(0)

func disappear():
	var tween = create_tween()
	tween.tween_property($Line2D, "width", 0, 0.1).from(10)


func _fade_out() -> void:
	# Stop extending the beam
	set_physics_process(false)
	# Flicker the beam then fade it out
	var line: Line2D = $Line2D
	var fade := create_tween()
	fade.set_ease(Tween.EASE_IN)
	fade.set_trans(Tween.TRANS_SINE)
	# Quick flicker
	fade.tween_property(line, "default_color:a", 0.3, 0.06)
	fade.tween_property(line, "default_color:a", 1.0, 0.06)
	fade.tween_property(line, "default_color:a", 0.15, 0.06)
	fade.tween_property(line, "default_color:a", 0.8, 0.06)
	# Fade width and alpha to 0
	fade.set_parallel(true)
	fade.tween_property(line, "width", 0.0, 0.4)
	fade.tween_property(line, "default_color:a", 0.0, 0.4)
	# Stop all particles and remove
	fade.set_parallel(false)
	fade.tween_callback(func():
		$BeamParticles2D.emitting = false
		$CollisionParticles2D.emitting = false
	)
	fade.tween_interval(0.3)
	fade.tween_callback(queue_free)
