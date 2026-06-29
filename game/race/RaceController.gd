extends Node
## Race / opponent mode (autoload). On a race-enabled level it spawns a CPU rival
## rocket flown by the AutoPilot singleton (bound + direct-control), and decides
## the winner: first to successfully land. The player keeps normal input.

const RIVAL_TINT := Color(1.0, 0.5, 0.5)   # reddish, to tell the rival from the player

var active := false
var _player: Node = null
var _rival: Node = null
var _decided := false


## Called by a race-enabled level once its (player) rocket is in the tree.
func setup(level_root: Node) -> void:
	if not globalvar.race_mode:
		return
	var rockets := level_root.get_tree().get_nodes_in_group("rocket")
	if rockets.is_empty():
		return
	_player = rockets[0]   # only the player exists yet; the rival is spawned below
	_decided = false
	active = true

	# Spawn the rival just beside the player at the launch pad.
	var rival = preload("res://game/rocket/Rocket.tscn").instantiate()
	rival.ai_controlled = true
	level_root.add_child(rival)
	rival.global_position = _player.global_position + Vector2(56, 0)
	rival.modulate = RIVAL_TINT
	# Only the player's camera is active.
	var rcam = rival.get_node_or_null("Camera2D")
	if rcam:
		rcam.enabled = false
	var pcam = _player.get_node_or_null("Camera2D")
	if pcam:
		pcam.make_current()
	# The rival doesn't use weapons — no firing on the player's input, no laser drain.
	for f in ["_has_cannon", "_has_missile", "_has_laser", "_has_emp"]:
		if f in rival:
			rival.set(f, false)
	_rival = rival

	AutoPilot.start_race(rival, _personality())


## A rocket finished its landing (flag planted). First one wins.
func on_rocket_landed(who: Node) -> void:
	if not active or _decided:
		return
	_decided = true
	globalvar.race_won = (who == _player)
	print("[Race] %s landed first — player_won=%s" % ["player" if who == _player else "rival", str(globalvar.race_won)])
	AutoPilot.stop_race()
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://game/gui/race/RaceResult.tscn")


func teardown() -> void:
	active = false
	_decided = false
	_player = null
	_rival = null


## Rival skill scales with the game's difficulty setting.
func _personality() -> String:
	match globalvar.difficulty:
		globalvar.Difficulty.EASY:
			return "rookie"
		globalvar.Difficulty.HARD:
			return "ace"
		_:
			return "steady"
