extends Control



func _on_Button_pressed():
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")


func _on_LinkButton_pressed():
	OS.shell_open("https://tabbylabs.com/mml_privacy.html")
