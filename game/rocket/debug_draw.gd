# adapted with thanks from code by GDQuest
# http://gdquest.com/

extends Node2D

var colors = {
	'BLUE': Color(.216, .474, .702),
	'RED': Color(1.0, .329, .298),
	'YELLOW': Color(.867, .91, .247),
	'GREEN': Color(.054, .718, .247)
}

var WIDTH = 5
var parent = null

func _ready():
	parent = get_parent()
	set_process(true)
	set_process_input(true)
	hide()

func _input(event):
	#if event.is_action_pressed("ui_focus_next"):
	#	set_hidden(not is_hidden())
	pass

func _process(delta):
	global_rotation = 0
	queue_redraw()

func _draw():
	draw_arrow(parent.linear_velocity, Vector2(), 1.0, 'YELLOW')
	draw_arrow(parent.constant_force, Vector2(), 0.5, 'RED')

func draw_arrow(vector, pos, scale, color):
	color = colors[color]
	if vector.length() == 0:
		return
	draw_line(pos * scale, vector * scale, color, WIDTH)
	var dir = vector.normalized()
	draw_triangle(vector * scale, dir, 10, color)
	draw_circle(pos, 5, color)

func draw_triangle(pos, dir, size, color):
	var a = pos + dir * size
	var b = pos + dir.rotated(2*PI/3) * size
	var c = pos + dir.rotated(4*PI/3) * size
	var points = PackedVector2Array([a, b, c])
	draw_polygon(points, PackedColorArray([color]))

