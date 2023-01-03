extends CanvasLayer

func _on_left_pressed():
	Input.action_press("ui_left")

func _on_right_pressed():
	Input.action_press("ui_right")

func _on_up_pressed():
	Input.action_press("thrust")

func _on_down_pressed():
	Input.action_press("revthrust")

func _on_left_released():
	Input.action_release("ui_left")

func _on_right_released():
	Input.action_release("ui_right")

func _on_up_released():
	Input.action_release("thrust")

func _on_down_released():
	Input.action_release("revthrust")

func _on_menu_pressed():
	get_tree().paused = true
	$popupMenu.show()

func _on_Resume_pressed():
	get_tree().paused = false
	$popupMenu.hide()

func _on_backtomenu_pressed():
	_on_Resume_pressed()
	get_tree().change_scene("res://game/gui/menu/Menu.tscn")
