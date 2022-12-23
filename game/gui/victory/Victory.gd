extends Node2D

var finaltime
var nowlevel  
var timerflag = false
var labeltimer
var astrotimer
var colortimer
var finishtimer
var templabels = []
var done = false


func _ready():
#	set_process(true)
	get_node("Sprite_Astronaut").hide()
	get_node("Label_Score").hide()
	get_node("ButtonNode").hide()
	finaltime = globalvar.finaltime
	nowlevel = globalvar.nowlevel
	$Label_Level.text = "Level " + str(nowlevel) + " Complete!"
	get_node("Label_Score").set_text("Final Time: " + str(finaltime))
	labeltimer = Timer.new()
	labeltimer.set_wait_time(2.5)
	labeltimer.set_one_shot(true)
	labeltimer.connect("timeout", self, "astroanim")
	add_child(labeltimer)
	astrotimer = Timer.new()
	astrotimer.set_wait_time(2.5)
	astrotimer.set_one_shot(true)
	astrotimer.connect("timeout", self, "colors")
	add_child(astrotimer)
	colortimer = Timer.new()
	colortimer.set_wait_time(1)
	colortimer.set_one_shot(true)
	colortimer.connect("timeout", self, "presskey")
	add_child(colortimer)
	labelanim()
	set_process(true)
	set_process_input(true)


func labelanim():
	print("label anim started")
	get_node("Label_Score").get_node("AnimationPlayer").seek(0)
	get_node("Label_Score").show()
	get_node("Label_Score").get_node("AnimationPlayer").play("scroll")
	labeltimer.start()
	print("label anim started")

func astroanim():
	print("astro anim started")
	get_node("Sprite_Astronaut").get_node("AnimationPlayer").play("grow")
	get_node("Sprite_Astronaut").show()
	$VictorySound.play()
	astrotimer.start()

func colors():
#	get_node("Sample_victory").stop_all()
	for i in range(77):
		var new_x = randf()*800
		var new_y = randf()*600
		var new_pos = Vector2(new_x, new_y)
		var new_color1 = randf()
		var new_color2 = randf()
		var new_color3 = randf()
		var new_color = Color(new_color1, new_color2, new_color3, 1)
		var text = get_node("Label_Score").get_text()
		templabels.append(Label.new())
		templabels[-1].set_name("templabel"+String(i))
		templabels[-1].set_text(text)
		templabels[-1].set_position(Vector2(new_x, new_y))  #-- NOTE: Automatically converted by Godot 2 to 3 converter, please review
		templabels[-1].add_color_override("font_color", new_color)
		get_node("ScoreNode").add_child(templabels[-1])
#	colortimer.set_active(true)
	colortimer.start()


func presskey():
	#get_node("ButtonNode").set_z(0)
	get_node("ButtonNode").show()
	get_node("ButtonNode").set_process(true)
	#get_node("ButtonNode/QuitArray/Label_Quit").set_as_toplevel(true)
	done = true

func _process(delta):
	if done == true and Input.is_action_pressed("quit"):
		get_tree().change_scene("res://game/gui/menu/Menu.tscn")

func _on_Label_Quit_pressed():
	get_tree().change_scene("res://game/gui/menu/Menu.tscn")

func _on_Label_NextLevel_pressed():
	get_tree().change_scene("res://game/levels/2/Level2.tscn")
