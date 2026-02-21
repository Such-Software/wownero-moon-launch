extends Node2D

const BS = preload("res://game/gui/ButtonStyles.gd")

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
	get_node("Label_Score").text = "Final Time: %.2f" % finaltime
	labeltimer = Timer.new()
	labeltimer.set_wait_time(2.5)
	labeltimer.set_one_shot(true)
	labeltimer.connect("timeout", astroanim)
	add_child(labeltimer)
	astrotimer = Timer.new()
	astrotimer.set_wait_time(2.5)
	astrotimer.set_one_shot(true)
	astrotimer.connect("timeout", colors)
	add_child(astrotimer)
	colortimer = Timer.new()
	colortimer.set_wait_time(1)
	colortimer.set_one_shot(true)
	colortimer.connect("timeout", presskey)
	add_child(colortimer)
	labelanim()
	set_process(true)
	set_process_input(true)
	save_game()


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
	for i in range(15):
		var new_x = randf()*800
		var new_y = randf()*600
		var new_pos = Vector2(new_x, new_y)
		var new_color1 = randf()
		var new_color2 = randf()
		var new_color3 = randf()
		var new_color = Color(new_color1, new_color2, new_color3, 1)
		var text = get_node("Label_Score").text
		templabels.append(Label.new())
		templabels[-1].set_name("templabel" + str(i))
		templabels[-1].text = text
		templabels[-1].set_position(Vector2(new_x, new_y))  #-- NOTE: Automatically converted by Godot 2 to 3 converter, please review
		templabels[-1].add_theme_color_override("font_color", new_color)
		get_node("ScoreNode").add_child(templabels[-1])
#	colortimer.set_active(true)
	colortimer.start()


func presskey():
	get_node("ButtonNode").show()
	get_node("ButtonNode").set_process(true)
	# Style the victory buttons
	BS.apply_space_style($ButtonNode/Label_Quit, Color.RED)
	BS.apply_space_style($ButtonNode/Label_NextLevel, Color.GREEN)
	done = true

func _process(delta):
	if done == true and Input.is_action_pressed("quit"):
		get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")

func _on_Label_Quit_pressed():
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")

func _on_Label_NextLevel_pressed():
	match(globalvar.nowlevel):
		1:get_tree().change_scene_to_file("res://game/levels/2/Level2.tscn")
		2:get_tree().change_scene_to_file("res://game/levels/3/Level3.tscn")
		3:get_tree().change_scene_to_file("res://game/levels/4/Level4.tscn")
		
func save():
	var save_dict = {
		'level':globalvar.nowlevel+1
	}
	return save_dict
	
func save_game():
	var save_game = FileAccess.open('user://savegame.json', FileAccess.WRITE)
	save_game.store_line(JSON.stringify(save()))
	print(save())
	save_game.close()
