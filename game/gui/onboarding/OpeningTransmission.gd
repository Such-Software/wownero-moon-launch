class_name OpeningTransmission
extends Control
## Caption-first opening story. Pre-rendered procedural 3D visemes keep the
## character performance lightweight while captions remain in the upper safe area.

signal finished(skipped: bool)

const BS = preload("res://game/gui/ButtonStyles.gd")
const UI_FONT := preload("res://fonts/Computer Speak v0.3.ttf")
const STARFIELD := preload("res://art/backgrounds/starfield.jpg")
const DOGE_TEXTURE := preload("res://art/characters/dialogue/3d/spacedoge_X.png")
const DOGE_TALKING_TEXTURES := [
	preload("res://art/characters/dialogue/3d/spacedoge_A.png"),
	preload("res://art/characters/dialogue/3d/spacedoge_B.png"),
	preload("res://art/characters/dialogue/3d/spacedoge_F.png"),
	preload("res://art/characters/dialogue/3d/spacedoge_B.png"),
]
const ALIEN_TEXTURE := preload("res://art/characters/dialogue/3d/martian_X.png")
const ALIEN_TALKING_TEXTURES := [
	preload("res://art/characters/dialogue/3d/martian_A.png"),
	preload("res://art/characters/dialogue/3d/martian_B.png"),
	preload("res://art/characters/dialogue/3d/martian_F.png"),
	preload("res://art/characters/dialogue/3d/martian_B.png"),
]

const BEATS: Array[Dictionary] = [
	{
		"speaker": "MARTIAN",
		"actor": "alien",
		"text": "Ha! You could never land that rusty rocket on Mars, you dirty doge.",
		"duration": 5.2,
	},
	{
		"speaker": "SPACEDOGE",
		"actor": "doge",
		"text": "Imagine losing to a dog. Watch this.",
		"duration": 4.0,
	},
	{
		"speaker": "SPACEDOGE",
		"actor": "doge",
		"text": "Pilot, you're up. Learn the slingshot, land on the Moon, then we'll show Mars how it's done.",
		"duration": 5.8,
	},
]

var _beat_i := -1
var _elapsed := 0.0
var _ending := false
var _replay_only := false

var _speaker_label: Label = null
var _caption_label: Label = null
var _progress_label: Label = null
var _continue_button: Button = null
var _alien: TalkingPortrait = null
var _doge: TalkingPortrait = null


static func dialogue_beats() -> Array[Dictionary]:
	return BEATS.duplicate(true)


func setup(replay_only := false) -> void:
	_replay_only = replay_only


func _ready() -> void:
	name = "OpeningTransmission"
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_interface()
	_enter_beat(0)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)
	Analytics.event("opening_intro_started", {"replay": _replay_only})


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


func _build_interface() -> void:
	var background := TextureRect.new()
	background.name = "Starfield"
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = STARFIELD
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.34, 0.34, 0.52, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var veil := ColorRect.new()
	add_child(veil)
	veil.name = "Veil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.018, 0.012, 0.07, 0.72)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	add_child(margin)
	margin.name = "SafeMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 10)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 38
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(header)

	var status := Label.new()
	status.text = "●  INCOMING TRANSMISSION  //  MARS ORBIT"
	status.add_theme_font_override("font", UI_FONT)
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color(0.54, 1.0, 0.67))
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(status)

	var skip := Button.new()
	skip.name = "SkipStoryButton"
	skip.text = "SKIP STORY"
	skip.custom_minimum_size = Vector2(128, 34)
	skip.add_theme_font_override("font", UI_FONT)
	skip.add_theme_font_size_override("font_size", 12)
	BS.apply_space_style(skip, Color(0.58, 0.66, 0.82))
	skip.pressed.connect(_skip_story)
	header.add_child(skip)

	var caption_panel := PanelContainer.new()
	caption_panel.name = "CaptionPanel"
	caption_panel.custom_minimum_size.y = 170
	caption_panel.add_theme_stylebox_override("panel", _panel_style())
	caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(caption_panel)

	var caption_margin := MarginContainer.new()
	caption_margin.add_theme_constant_override("margin_left", 22)
	caption_margin.add_theme_constant_override("margin_right", 22)
	caption_margin.add_theme_constant_override("margin_top", 14)
	caption_margin.add_theme_constant_override("margin_bottom", 14)
	caption_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_panel.add_child(caption_margin)

	var caption_stack := VBoxContainer.new()
	caption_stack.add_theme_constant_override("separation", 10)
	caption_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_margin.add_child(caption_stack)

	_speaker_label = Label.new()
	_speaker_label.name = "Speaker"
	_speaker_label.add_theme_font_override("font", UI_FONT)
	_speaker_label.add_theme_font_size_override("font_size", 14)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.81, 0.31))
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_stack.add_child(_speaker_label)

	_caption_label = Label.new()
	_caption_label.name = "Caption"
	_caption_label.add_theme_font_size_override("font_size", 25)
	_caption_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_stack.add_child(_caption_label)

	var stage := Control.new()
	stage.name = "CharacterStage"
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 260
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	layout.add_child(stage)
	var portrait_layout := size.y > size.x

	_alien = _make_portrait(
		"MartianPortrait",
		ALIEN_TEXTURE,
		Vector2(0.5, 0.633),
		0.15,
		0.075,
		Color(0.025, 0.035, 0.025),
		Color(0.13, 0.32, 0.1),
		-0.45
	)
	stage.add_child(_alien)
	_alien.configure_visemes(ALIEN_TEXTURE, ALIEN_TALKING_TEXTURES)
	_alien.set_bottom_aligned(true)
	_alien.anchor_left = 0.02
	_alien.anchor_right = 0.60 if portrait_layout else 0.48
	_alien.anchor_top = 0.0
	_alien.anchor_bottom = 1.0

	_doge = _make_portrait(
		"SpaceDogePortrait",
		DOGE_TEXTURE,
		Vector2(0.5, 0.653),
		0.155,
		0.08,
		Color(0.12, 0.065, 0.045),
		Color(0.48, 0.24, 0.15),
		1.0
	)
	stage.add_child(_doge)
	_doge.configure_visemes(DOGE_TEXTURE, DOGE_TALKING_TEXTURES)
	_doge.set_bottom_aligned(true)
	_doge.anchor_left = 0.40 if portrait_layout else 0.52
	_doge.anchor_right = 0.98
	_doge.anchor_top = 0.0
	_doge.anchor_bottom = 1.0

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 42
	footer.add_theme_constant_override("separation", 12)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(footer)

	_progress_label = Label.new()
	_progress_label.name = "Progress"
	_progress_label.add_theme_font_override("font", UI_FONT)
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.82))
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(_progress_label)

	var tap_hint := Label.new()
	tap_hint.text = "TAP / ENTER TO CONTINUE"
	tap_hint.add_theme_font_override("font", UI_FONT)
	tap_hint.add_theme_font_size_override("font_size", 11)
	tap_hint.add_theme_color_override("font_color", Color(0.54, 0.6, 0.73))
	tap_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tap_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(tap_hint)

	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = "NEXT  ›"
	_continue_button.custom_minimum_size = Vector2(126, 38)
	_continue_button.add_theme_font_override("font", UI_FONT)
	_continue_button.add_theme_font_size_override("font_size", 13)
	BS.apply_space_style(_continue_button, Color(0.54, 1.0, 0.67))
	_continue_button.pressed.connect(_advance)
	footer.add_child(_continue_button)

	gui_input.connect(_on_gui_input)


func _make_portrait(node_name: String, texture: Texture2D, anchor: Vector2,
		width: float, height: float, fill: Color, lip: Color,
		curve: float) -> TalkingPortrait:
	var portrait := TalkingPortrait.new()
	portrait.name = node_name
	portrait.configure(texture, anchor, width, height, fill, lip, curve)
	return portrait


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.022, 0.09, 0.94)
	style.border_color = Color(0.48, 0.84, 1.0, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.3, 0.72, 1.0, 0.25)
	style.shadow_size = 12
	return style


func _enter_beat(index: int) -> void:
	_beat_i = index
	_elapsed = 0.0
	var beat: Dictionary = BEATS[index]
	_speaker_label.text = "%s  //  LIVE" % beat["speaker"]
	_caption_label.text = str(beat["text"])
	_progress_label.text = "TRANSMISSION  %02d / %02d" % [index + 1, BEATS.size()]
	_continue_button.text = "CONTINUE  ›" if index == BEATS.size() - 1 else "NEXT  ›"

	var alien_active := str(beat["actor"]) == "alien"
	_alien.set_active(alien_active)
	_alien.set_talking(alien_active)
	_doge.set_active(not alien_active)
	_doge.set_talking(not alien_active)
	Analytics.event("opening_intro_beat", {"beat": index + 1, "speaker": beat["actor"]})

	_caption_label.modulate.a = 0.0
	create_tween().tween_property(_caption_label, "modulate:a", 1.0, 0.22)


func _process(delta: float) -> void:
	if _ending or _beat_i < 0:
		return
	_elapsed += delta
	if _elapsed >= float(BEATS[_beat_i]["duration"]):
		_advance()


func _advance() -> void:
	if _ending:
		return
	if _beat_i + 1 < BEATS.size():
		_enter_beat(_beat_i + 1)
	else:
		_finish(false)


func _skip_story() -> void:
	if not _ending:
		_finish(true)


func _finish(skipped: bool) -> void:
	_ending = true
	set_process(false)
	_alien.set_talking(false)
	_doge.set_talking(false)
	Analytics.event("opening_intro_finished", {"skipped": skipped, "beat": _beat_i + 1})
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.24)
	fade.tween_callback(func() -> void:
		finished.emit(skipped)
		queue_free()
	)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_advance()
	elif event is InputEventScreenTouch and event.pressed:
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if _ending or not event.is_pressed():
		return
	if event.is_action("ui_accept") or event is InputEventKey and event.keycode == KEY_SPACE:
		_advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_ESCAPE:
		_skip_story()
		get_viewport().set_input_as_handled()
