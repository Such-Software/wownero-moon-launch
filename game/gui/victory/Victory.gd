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

# Count-up animation state
var _counting_up := false
var _count_elapsed: float = 0.0
var _count_duration: float = 1.5
var _fuel_pct: float = 0.0
var _crypto_collected: int = 0
var _stars_shown: int = 0
var _star_labels: Array[Label] = []
var _time_label: Label = null
var _fuel_label: Label = null
var _crypto_label: Label = null
var _best_label: Label = null
var _rewarded_btn: Button = null
var _share_btn: Button = null
var _rate_prompt_panel: PanelContainer = null


func _ready():
	# Center the 1024x600 layout within the actual viewport
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - 1024) / 2.0, (vp.y - 600) / 2.0)

	get_node("Sprite_Astronaut").hide()
	get_node("Label_Score").hide()
	get_node("ButtonNode").hide()
	finaltime = globalvar.finaltime
	nowlevel = globalvar.nowlevel
	_fuel_pct = globalvar.level_fuel_remaining
	_crypto_collected = globalvar.level_crypto_collected

	# Compute and record stars / best time
	stars = globalvar.record_level_result(nowlevel, finaltime, _fuel_pct, _crypto_collected)
	var prev_best: float = globalvar.get_best_time(nowlevel)
	is_new_best = (finaltime <= prev_best) or prev_best < 0
	Telemetry.log_event(Telemetry.EVENT_LEVEL_COMPLETE, {
		"level": nowlevel,
		"time_s": finaltime,
		"stars": stars,
		"moonrocks": _crypto_collected,
	})

	# Build the level complete header
	var level_name: String = globalvar.LEVEL_NAMES.get(nowlevel, str(nowlevel))
	$Label_Level.text = "Level " + str(nowlevel) + " — " + level_name + " Complete!"

	# Set score label to empty (will be filled by count-up)
	get_node("Label_Score").text = ""

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
	ScoreClient.submit_score(nowlevel, finaltime, _fuel_pct, _crypto_collected, stars)
	ScoreClient.score_submitted.connect(_on_score_submitted, CONNECT_ONE_SHOT)


func labelanim():
	# Build the count-up stats overlay using individual labels
	var score_node := get_node("Label_Score")
	score_node.show()
	score_node.text = ""  # clear the old label; we'll use child labels instead

	var base_pos: Vector2 = score_node.position
	var base_scale: Vector2 = score_node.scale

	# Time count-up label
	_time_label = Label.new()
	_time_label.text = "Time: 0.00 s"
	_time_label.add_theme_color_override("font_color", Color.WHITE)
	_time_label.add_theme_font_size_override("font_size", 16)
	_time_label.position = base_pos
	_time_label.scale = base_scale
	add_child(_time_label)

	# Star labels (pop in one-by-one after count-up)
	for i in 3:
		var sl := Label.new()
		sl.text = "☆"
		sl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		sl.add_theme_font_size_override("font_size", 20)
		sl.position = base_pos + Vector2((280 + i * 50) / base_scale.x, 0) * base_scale
		sl.scale = base_scale
		sl.modulate = Color(1, 1, 1, 0.3)
		add_child(sl)
		_star_labels.append(sl)

	# Fuel label (below time)
	_fuel_label = Label.new()
	_fuel_label.text = "Fuel: 0%"
	_fuel_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	_fuel_label.add_theme_font_size_override("font_size", 16)
	_fuel_label.position = base_pos + Vector2(0, 22) * base_scale
	_fuel_label.scale = base_scale
	_fuel_label.modulate = Color(1, 1, 1, 0)
	add_child(_fuel_label)

	# Crypto label (next to fuel)
	_crypto_label = Label.new()
	_crypto_label.text = "Crypto: +0 🪨"
	_crypto_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_crypto_label.add_theme_font_size_override("font_size", 16)
	_crypto_label.position = base_pos + Vector2(200 / base_scale.x, 22) * base_scale
	_crypto_label.scale = base_scale
	_crypto_label.modulate = Color(1, 1, 1, 0)
	add_child(_crypto_label)

	# NEW BEST flash label
	if is_new_best:
		_best_label = Label.new()
		_best_label.text = "NEW BEST!"
		_best_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.1))
		_best_label.add_theme_font_size_override("font_size", 18)
		_best_label.position = base_pos + Vector2(0, -25) * base_scale
		_best_label.scale = Vector2.ZERO
		add_child(_best_label)

	_counting_up = true
	_count_elapsed = 0.0
	labeltimer.start()

func astroanim():
	get_node("Sprite_Astronaut").get_node("AnimationPlayer").play("grow")
	get_node("Sprite_Astronaut").show()
	$VictorySound.play()
	astrotimer.start()

func colors():
	colortimer.start()


func presskey():
	get_node("ButtonNode").show()
	get_node("ButtonNode").set_process(true)
	# Style the victory buttons
	BS.apply_space_style($ButtonNode/Label_Quit, Color.RED)
	if globalvar.has_next_level():
		$ButtonNode/Label_NextLevel.text = "Upgrade Shop"
	else:
		$ButtonNode/Label_NextLevel.text = "Upgrades & Menu"
	BS.apply_space_style($ButtonNode/Label_NextLevel, Color.GREEN)

	# Insert opt-in rewarded + share buttons into ButtonNode (siblings of NextLevel/Quit).
	# Hidden from desktop builds (no ad SDK + no real ads to watch) by AdManager.is_ad_supported.
	_build_optional_buttons()

	# Slide buttons in from below with stagger
	var buttons: Array[Node] = []
	buttons.append($ButtonNode/Label_NextLevel)
	if _rewarded_btn: buttons.append(_rewarded_btn)
	if _share_btn: buttons.append(_share_btn)
	buttons.append($ButtonNode/Label_Quit)
	for i in buttons.size():
		var btn: Control = buttons[i]
		var final_pos := btn.position
		btn.position.y += 30
		btn.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_BACK)
		tw.set_parallel(true)
		# Stagger: 0.1s between each button
		var delay := i * 0.1
		tw.tween_property(btn, "position", final_pos, 0.25).set_delay(delay)
		tw.tween_property(btn, "modulate", Color.WHITE, 0.2).set_delay(delay)

	# Rate prompt fires once after the 3rd successful landing in the player's history
	# (and only once per save). Trigger after the button stagger completes.
	if globalvar.landings_since_install >= 3 and not globalvar.rate_prompt_shown:
		var rt_timer := get_tree().create_timer(1.2)
		rt_timer.timeout.connect(_show_rate_prompt)

	done = true


func _build_optional_buttons() -> void:
	## Lay out all four buttons (NextLevel, Rewarded, Share, Quit) as a clean
	## vertical stack. Overrides the .tscn-baked positions for NextLevel and
	## Quit because they were too close together (40px apart) for inserted
	## buttons to fit without overlap.
	var bn: Node = get_node("ButtonNode")
	if bn == null:
		return
	var next_btn: Control = $ButtonNode/Label_NextLevel
	var quit_btn: Control = $ButtonNode/Label_Quit

	# Keep horizontal position from the .tscn (200 left of viewport center).
	var x: float = next_btn.position.x
	var w: float = 420.0  # matches .tscn offset_right - offset_left
	var h: float = 44.0
	var spacing: float = 10.0
	var y: float = 410.0  # top of the button column

	# NextLevel (green, primary CTA)
	next_btn.position = Vector2(x, y)
	next_btn.size = Vector2(w, h)
	y += h + spacing

	# Rewarded "+N Moonrocks (Watch Ad)" — only if ad system can serve rewarded.
	if AdManager.is_rewarded_available() and not AdManager.is_ad_free():
		_rewarded_btn = Button.new()
		_rewarded_btn.text = "+%d Moonrocks (Watch Ad)" % AdManager.REWARDED_AD_MOONROCKS
		_rewarded_btn.custom_minimum_size = Vector2(w, h)
		_rewarded_btn.position = Vector2(x, y)
		_rewarded_btn.add_theme_font_size_override("font_size", 16)
		BS.apply_space_style(_rewarded_btn, Color(1.0, 0.85, 0.2))
		_rewarded_btn.pressed.connect(_on_rewarded_pressed)
		bn.add_child(_rewarded_btn)
		y += h + spacing

	# Share button — always available
	_share_btn = Button.new()
	_share_btn.text = "Share Score"
	_share_btn.custom_minimum_size = Vector2(w, h)
	_share_btn.position = Vector2(x, y)
	_share_btn.add_theme_font_size_override("font_size", 16)
	BS.apply_space_style(_share_btn, Color(0.5, 0.85, 1.0))
	_share_btn.pressed.connect(_on_share_pressed)
	bn.add_child(_share_btn)
	y += h + spacing

	# Quit at bottom
	quit_btn.position = Vector2(x, y)
	quit_btn.size = Vector2(w, h)


func _on_rewarded_pressed() -> void:
	if _rewarded_btn == null: return
	_rewarded_btn.disabled = true
	_rewarded_btn.text = "Loading ad..."
	AdManager.show_rewarded(_on_rewarded_complete)


func _on_rewarded_complete(success: bool) -> void:
	if _rewarded_btn == null: return
	if success:
		Telemetry.log_event(Telemetry.EVENT_REWARDED_WATCHED, {"surface": "victory"})
		globalvar.add_crypto(AdManager.REWARDED_AD_MOONROCKS)
		_rewarded_btn.text = "+%d Moonrocks!" % AdManager.REWARDED_AD_MOONROCKS
		# Hide after a beat — single-use per Victory screen.
		var t := get_tree().create_timer(1.2)
		t.timeout.connect(func(): if _rewarded_btn: _rewarded_btn.visible = false)
	else:
		_rewarded_btn.disabled = false
		_rewarded_btn.text = "+%d Moonrocks (Watch Ad)" % AdManager.REWARDED_AD_MOONROCKS


func _on_share_pressed() -> void:
	if not Engine.has_singleton("ShareService") and not has_node("/root/ShareService"):
		return  # Autoload not present; defensive
	var level_name: String = globalvar.LEVEL_NAMES.get(nowlevel, str(nowlevel))
	ShareService.share_score(level_name, stars, finaltime)


func _on_score_submitted(success: bool, rank: int) -> void:
	if success and rank > 0:
		# Show rank in the gap between the stats row and the button column.
		# (Was previously at y=395 which overlapped the new dynamic Share
		# button on mobile.)
		var rank_label := Label.new()
		rank_label.text = "Leaderboard Rank: #%d" % rank
		rank_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		rank_label.add_theme_font_size_override("font_size", 18)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		rank_label.offset_top = 380
		rank_label.offset_bottom = 405
		add_child(rank_label)

func _process(delta):
	# Drive count-up animation
	if _counting_up:
		_count_elapsed += delta
		var t := clampf(_count_elapsed / _count_duration, 0.0, 1.0)
		# Ease-out for satisfying deceleration
		var eased := 1.0 - pow(1.0 - t, 3.0)

		# Time counts up
		var displayed_time := lerpf(0.0, finaltime, eased)
		_time_label.text = "Time: %.2f s" % displayed_time

		# Fuel fades in at 30% progress and counts up
		if t > 0.3:
			var fuel_t := clampf((t - 0.3) / 0.5, 0.0, 1.0)
			_fuel_label.modulate = Color(1, 1, 1, fuel_t)
			_fuel_label.text = "Fuel: %.0f%%" % lerpf(0.0, _fuel_pct, fuel_t)

		# Crypto fades in at 50% progress and counts up
		if t > 0.5:
			var crypto_t := clampf((t - 0.5) / 0.4, 0.0, 1.0)
			_crypto_label.modulate = Color(1, 1, 1, crypto_t)
			_crypto_label.text = "Crypto: +%d 🪨" % roundi(lerpf(0.0, float(_crypto_collected), crypto_t))

		# Stars pop in after count-up finishes
		if t >= 1.0:
			var star_time := _count_elapsed - _count_duration
			var new_stars := mini(floori(star_time / 0.3) + 1, stars)
			while _stars_shown < new_stars:
				_pop_star(_stars_shown)
				_stars_shown += 1

			# NEW BEST flash after all stars
			if _best_label and star_time > stars * 0.3 + 0.2 and _best_label.scale == Vector2.ZERO:
				var tw := create_tween()
				tw.set_ease(Tween.EASE_OUT)
				tw.set_trans(Tween.TRANS_BACK)
				tw.tween_property(_best_label, "scale", _time_label.scale * 1.2, 0.3)
				tw.tween_property(_best_label, "scale", _time_label.scale, 0.15)

			# Stop counting after all animations are done
			if star_time > stars * 0.3 + 0.8:
				_counting_up = false

	if done == true and Input.is_action_pressed("quit"):
		get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")


func _pop_star(index: int) -> void:
	if index >= _star_labels.size():
		return
	var sl: Label = _star_labels[index]
	sl.text = "★"
	sl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	# Pop-in tween
	var orig_scale: Vector2 = sl.scale
	sl.scale = orig_scale * 2.0
	sl.modulate = Color(2, 2, 0.5, 1)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_ELASTIC)
	tw.set_parallel(true)
	tw.tween_property(sl, "scale", orig_scale, 0.4)
	tw.tween_property(sl, "modulate", Color(1, 1, 1, 1), 0.3)

func _on_Label_Quit_pressed():
	get_tree().change_scene_to_file("res://game/gui/menu/Menu.tscn")

func _on_Label_NextLevel_pressed():
	# Direct navigation — no forced ads in this game.
	get_tree().change_scene_to_file("res://game/gui/shop/UpgradeShop.tscn")


func _show_rate_prompt() -> void:
	## One-time "rate this game" popup after the 3rd successful landing.
	if globalvar.rate_prompt_shown:
		return
	globalvar.rate_prompt_shown = true
	globalvar.save_game()
	Telemetry.log_event(Telemetry.EVENT_RATE_PROMPT_SHOWN, {})

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.1, 0.97)
	style.border_color = Color(1.0, 0.85, 0.2, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(1.0, 0.85, 0.2, 0.25)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	panel.z_index = 25
	# Anchor in CanvasLayer-style center (Victory is a Node2D so we add a CanvasLayer).
	var cl := CanvasLayer.new()
	cl.layer = 12
	add_child(cl)
	cl.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -130
	panel.offset_bottom = 130
	_rate_prompt_panel = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "🚀  Enjoying Such Moon Launch?"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var body := Label.new()
	body.text = "A quick rating helps us reach more pilots. It takes 10 seconds and means a lot."
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(body)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var rate_btn := Button.new()
	rate_btn.text = "Rate Now"
	rate_btn.custom_minimum_size = Vector2(150, 36)
	BS.apply_space_style(rate_btn, Color.GREEN)
	rate_btn.pressed.connect(func():
		OS.shell_open(_get_store_url())
		_close_rate_prompt()
	)
	btn_row.add_child(rate_btn)

	var later_btn := Button.new()
	later_btn.text = "Maybe Later"
	later_btn.custom_minimum_size = Vector2(150, 36)
	BS.apply_space_style(later_btn, Color(0.5, 0.6, 0.7))
	later_btn.pressed.connect(_close_rate_prompt)
	btn_row.add_child(later_btn)


func _close_rate_prompt() -> void:
	if _rate_prompt_panel == null:
		return
	# Free the parent CanvasLayer too so we don't leak.
	var cl := _rate_prompt_panel.get_parent()
	_rate_prompt_panel = null
	if cl and is_instance_valid(cl):
		cl.queue_free()


func _get_store_url() -> String:
	match OS.get_name():
		"Android": return "https://play.google.com/store/apps/details?id=com.suchsoftware.suchmoonlaunch"
		"iOS": return "https://apps.apple.com/app/such-moon-launch"
		_: return "https://suchsoftware.itch.io/such-moon-launch"
