extends Control

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func _ready():
	$RocketSprite/AnimationPlayer.play("move")
	globalvar.load_game()

func _on_QuitButton_pressed():
	get_tree().quit()

func _on_PlayButton_pressed():
	match(globalvar.nowlevel):
		1:get_tree().change_scene_to_file("res://game/levels/1/Level1.tscn")
		2:get_tree().change_scene_to_file("res://game/levels/2/Level2.tscn")
		3:get_tree().change_scene_to_file("res://game/levels/3/Level3.tscn")
		4:get_tree().change_scene_to_file("res://game/levels/4/Level4.tscn")

func _on_HelpButton_pressed():
	get_tree().change_scene_to_file("res://game/gui/help/Help.tscn")
