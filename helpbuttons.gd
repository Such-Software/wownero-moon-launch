extends VBoxContainer

func _ready():
	pass

func _on_MenuButton_pressed():
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")
