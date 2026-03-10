extends CharacterBody2D
## Pre-placed orbiting asteroid obstacle. Circles a fixed point (or planet node).
##
## Usage: instance OrbitingAsteroid.tscn or spawn from level script.
## Set orbit_center_pos and orbit_radius, or call setup() with a planet node.

## Center point of the orbit (world coords). Overridden by setup() if using a planet node.
@export var orbit_center_pos: Vector2 = Vector2.ZERO
## Orbit radius in pixels
@export var orbit_radius: float = 120.0
## Orbit speed in radians/second (positive = counter-clockwise)
@export var orbit_speed: float = 1.2
## Visual spin speed in degrees/frame
@export var spin_rate: float = 1.5

var _orbit_angle: float = 0.0
var _orbit_node: Node2D = null  # if orbiting a moving planet
var _rocket: Node2D = null

const TEXTURES := [
	preload("res://art/asteroids/a1.png"),
	preload("res://art/asteroids/a2.png"),
]


func _ready() -> void:
	# Randomize starting angle and spin direction
	_orbit_angle = randf() * TAU
	if randf() < 0.5:
		spin_rate = -spin_rate
	# Pick random asteroid texture
	$Sprite2D.texture = TEXTURES[randi() % TEXTURES.size()]
	# Random scale variation (0.7x – 1.2x)
	var s := randf_range(0.7, 1.2)
	$Sprite2D.scale = Vector2(s, s)
	# Cache rocket for despawn check
	_rocket = get_parent().get_node_or_null("Rocket")
	# Set initial position
	_update_orbit_position()


func setup(planet_node: Node2D, radius: float = 120.0, speed: float = 1.2) -> void:
	## Configure to orbit around a live planet node (follows its movement).
	_orbit_node = planet_node
	orbit_radius = radius
	orbit_speed = speed


func _physics_process(delta: float) -> void:
	_orbit_angle += orbit_speed * delta
	$Sprite2D.rotation_degrees += spin_rate
	_update_orbit_position()
	# Despawn if far from rocket (or origin if rocket is gone)
	var ref := _rocket.global_position if _rocket and is_instance_valid(_rocket) else Vector2.ZERO
	if global_position.distance_to(ref) > 2500.0:
		queue_free()


func _update_orbit_position() -> void:
	var center := orbit_center_pos
	if _orbit_node and is_instance_valid(_orbit_node):
		center = _orbit_node.global_position
	global_position = center + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * orbit_radius
