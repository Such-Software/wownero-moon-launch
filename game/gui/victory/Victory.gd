extends Node2D

const BS = preload("res://game/gui/ButtonStyles.gd")

var finaltime: float
var nowlevel: int
var stars: int = 1
var is_new_best: bool = false
var timerflag = false
var labeltimer
var astrotimer
var colortimer
var finishtimer
var templabels = []
var done = false
var _nick_row: HBoxContainer = null
var _nick_edit: LineEdit = null
var _editing_nick := false


func _ready():
	get_node("Sprite_Astronaut").hide()
	get_node("Label_Score").hide()
	get_node("ButtonNode").hide()
	finaltime = globalvar.finaltime
	nowlevel = globalvar.nowlevel
	var fuel_pct: float = globalvar.level_fuel_remaining
	var crypto: int = globalvar.level_crypto_collected

	# Compute and record stars / best time
	stars = globalvar.record_level_result(nowlevel, finaltime, fuel_pct, crypto)
	var prev_best: float = globalvar.get_best_time(nowlevel)
	is_new_best = (finaltime <= prev_best) or prev_best < 0

	# Build the level complete header
	var level_name: String = globalvar.LEVEL_NAMES.get(nowlevel, str(nowlevel))
	$Label_Level.text = "Level " + str(nowlevel) + " — " + level_name + " Complete!"

	# Build the score text with stars and stats
	var star_str := ""
	for i in range(3):
		star_str += "★" if i < stars else "☆"
	var score_text := "Time: %.2f s   %s" % [finaltime, star_str]
	if is_new_best:
		score_text += "   NEW BEST!"
	score_text += "\nFuel: %.0f%%   Crypto: +%d WOW" % [fuel_pct, crypto]
	get_node("Label_Score").text = score_text

	# Build the nickname row (visible after presskey phase)
	_build_nickname_row()

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
	globalvar.save_game()

	# Submit score to the leaderboard (fire and forget)
	ScoreClient.submit_score(nowlevel, finaltime, fuel_pct, crypto, stars)
	ScoreClient.score_submitted.connect(_on_score_submitted, CONNECT_ONE_SHOT)


func labelanim():
	get_node("Label_Score").get_node("AnimationPlayer").seek(0)
	get_node("Label_Score").show()
	get_node("Label_Score").get_node("AnimationPlayer").play("scroll")
	labeltimer.start()

func astroanim():
	get_node("Sprite_Astronaut").get_node("AnimationPlayer").play("grow")
	get_node("Sprite_Astronaut").show()
	$VictorySound.play()
	astrotimer.start()

func colors():
#	get_node("Sample_victory").stop_all()
	for i in range(15):
		var new_x = randf()*800
		var new_y = randf()*600
		var _new_pos = Vector2(new_x, new_y)
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
	# Show nickname row
	if _nick_row:
		_nick_row.visible = true
	# Style the victory buttons
	BS.apply_space_style($ButtonNode/Label_Quit, Color.RED)
	if globalvar.has_next_level():
		$ButtonNode/Label_NextLevel.text = "Upgrade Shop"
	else:
		$ButtonNode/Label_NextLevel.text = "Upgrades & Menu"
	BS.apply_space_style($ButtonNode/Label_NextLevel, Color.GREEN)
	done = true


func _build_nickname_row() -> void:
	## Build a nickname display row: "🧑‍🚀 NickName  [🎲] [✏️]"
	_nick_row = HBoxContainer.new()
	_nick_row.name = "NicknameRow"
	_nick_row.visible = false  # shown in presskey() phase
	_nick_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_nick_row.position = Vector2(340, 520)
	_nick_row.add_theme_constant_override("separation", 8)
	add_child(_nick_row)

	var nick_label := Label.new()
	nick_label.name = "NickLabel"
	nick_label.text = globalvar.nickname
	nick_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	nick_label.add_theme_font_size_override("font_size", 16)
	_nick_row.add_child(nick_label)

	# Dice button — reroll random name
	var dice_btn := Button.new()
	dice_btn.text = "Reroll"
	dice_btn.custom_minimum_size = Vector2(70, 28)
	BS.apply_space_style(dice_btn, Color(1.0, 0.7, 0.1))
	dice_btn.pressed.connect(_on_reroll_nickname)
	_nick_row.add_child(dice_btn)

	# Edit button — toggle inline text edit
	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.custom_minimum_size = Vector2(55, 28)
	BS.apply_space_style(edit_btn, Color(0.5, 0.8, 1.0))
	edit_btn.pressed.connect(_on_edit_nickname)
	_nick_row.add_child(edit_btn)

	# Hidden LineEdit for custom entry
	_nick_edit = LineEdit.new()
	_nick_edit.name = "NickEdit"
	_nick_edit.visible = false
	_nick_edit.custom_minimum_size = Vector2(180, 30)
	_nick_edit.max_length = 20
	_nick_edit.placeholder_text = "Enter nickname..."
	_nick_edit.text = globalvar.nickname
	_nick_edit.add_theme_color_override("font_color", Color.WHITE)
	_nick_edit.add_theme_color_override("caret_color", Color.CYAN)
	var edit_style := StyleBoxFlat.new()
	edit_style.bg_color = Color(0.06, 0.06, 0.14, 0.95)
	edit_style.border_color = Color.CYAN
	edit_style.set_border_width_all(1)
	edit_style.set_corner_radius_all(4)
	edit_style.content_margin_left = 6
	edit_style.content_margin_right = 6
	_nick_edit.add_theme_stylebox_override("normal", edit_style)
	_nick_edit.text_submitted.connect(_on_nickname_submitted)
	_nick_row.add_child(_nick_edit)


func _on_reroll_nickname() -> void:
	globalvar.nickname = globalvar.generate_random_nickname()
	globalvar.save_game()
	_nick_row.get_node("NickLabel").text = globalvar.nickname
	_nick_edit.text = globalvar.nickname


func _on_edit_nickname() -> void:
	_editing_nick = !_editing_nick
	var nick_label: Label = _nick_row.get_node("NickLabel")
	if _editing_nick:
		nick_label.visible = false
		_nick_edit.visible = true
		_nick_edit.text = globalvar.nickname
		_nick_edit.grab_focus()
		_nick_edit.caret_column = _nick_edit.text.length()
	else:
		_apply_nickname(_nick_edit.text)


func _on_nickname_submitted(new_text: String) -> void:
	_apply_nickname(new_text)


func _apply_nickname(raw: String) -> void:
	var cleaned := raw.strip_edges().left(20)
	if cleaned == "":
		cleaned = globalvar.generate_random_nickname()
	globalvar.nickname = cleaned
	globalvar.save_game()
	_editing_nick = false
	var nick_label: Label = _nick_row.get_node("NickLabel")
	nick_label.text = globalvar.nickname
	nick_label.visible = true
	_nick_edit.visible = false


func _on_score_submitted(success: bool, rank: int) -> void:
	if success and rank > 0:
		# Briefly show rank after confetti settles
		var rank_label := Label.new()
		rank_label.text = "Leaderboard Rank: #%d" % rank
		rank_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		rank_label.position = Vector2(512, 560)
		add_child(rank_label)

func _process(_delta):
	if done == true and Input.is_action_pressed("quit"):
		get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")

func _on_Label_Quit_pressed():
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")

func _on_Label_NextLevel_pressed():
	# Show interstitial ad before going to shop (no-op if ad-free)
	AdManager.interstitial_closed.connect(_go_to_shop, CONNECT_ONE_SHOT)
	AdManager.show_interstitial()


func _go_to_shop() -> void:
	get_tree().change_scene_to_file("res://game/gui/shop/UpgradeShop.tscn")
