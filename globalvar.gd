extends Node

signal sendDeath

var nowlevel = 1
var finaltime = 0

func _ready():
	load_game()

func load_game():
	if not FileAccess.file_exists('user://savegame.json'):
		return
	var save_game = FileAccess.open('user://savegame.json', FileAccess.READ)
	var json = JSON.new()
	var result = json.parse(save_game.get_as_text())
	if result == OK:
		var data = json.get_data()
		if data is Dictionary and data.has('level'):
			nowlevel = int(data['level'])
			print(data['level'])
	save_game.close()
	
