extends Node

# class member variables go here, for example:
# var a = 2
# var b = "textvar"
signal sendDeath

var nowlevel = 1 

var finaltime = 0

func _ready():
	load_game()

func load_game():
	var save_game = File.new()
	if not save_game.file_exists('user://savegame.json'):
		return
	save_game.open('user://savegame.json',File.READ)
	nowlevel = int(parse_json(save_game.get_as_text())['level'])
	print(parse_json(save_game.get_as_text())['level'])
	save_game.close()
	
