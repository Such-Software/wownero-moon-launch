extends Control

const BS = preload("res://game/gui/ButtonStyles.gd")


func _ready() -> void:
	BS.apply_space_style($Button, Color.CYAN)


func _on_Button_pressed():
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")


func _on_LinkButton_pressed():
	OS.shell_open("https://git.wownero.com/wownero/wownero-moon-launch")
