class_name FirstFlightBriefing
extends Control
## One-time, pre-action mission briefing for the player's first Level 1 attempt.
## It pauses the simulation so the first control instruction cannot be missed.

signal ready_to_launch

const BS = preload("res://game/gui/ButtonStyles.gd")
const UI_FONT := preload("res://fonts/Computer Speak v0.3.ttf")
const DOGE_TEXTURE := preload("res://art/characters/dialogue/spacedoge.svg")

const COACH_LINE := "Pilot, follow my callouts. Use Earth's gravity, then touch down slow and upright."
const OBJECTIVE_LINES: Array[String] = [
	"Build momentum beside Earth",
	"Swing wide — gravity bends your path",
	"Brake with reverse thrust before touchdown",
]

var _dismissed := false
var _was_paused := false
var _pause_restored := false
var _talk_elapsed := 0.0
var _doge: TalkingPortrait = null


static func briefing_copy() -> Dictionary:
	return {
		"coach": COACH_LINE,
		"objectives": OBJECTIVE_LINES.duplicate(),
	}


func _ready() -> void:
	name = "FirstFlightBriefing"
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90
	_build_interface()
	_was_paused = get_tree().paused
	get_tree().paused = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	_doge.set_active(true, false)
	_doge.set_talking(true)
	Analytics.event("first_flight_briefing", {"state": "shown"})


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


func _build_interface() -> void:
	var portrait_layout := size.y > size.x

	var veil := ColorRect.new()
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.012, 0.01, 0.055, 0.88)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)

	var mission_tag := Label.new()
	mission_tag.text = "TRAINING FLIGHT 01  //  EARTH → MOON"
	mission_tag.add_theme_font_override("font", UI_FONT)
	mission_tag.add_theme_font_size_override("font_size", 17)
	mission_tag.add_theme_color_override("font_color", Color(0.55, 1.0, 0.68))
	mission_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_tag.custom_minimum_size.y = 32
	mission_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(mission_tag)

	var caption_panel := PanelContainer.new()
	caption_panel.custom_minimum_size.y = 112
	caption_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.48, 0.84, 1.0)))
	caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(caption_panel)

	var caption := Label.new()
	caption.text = COACH_LINE
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_panel.add_child(caption)

	var stage: BoxContainer
	if portrait_layout:
		stage = VBoxContainer.new()
	else:
		stage = HBoxContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 12 if portrait_layout else 26)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(stage)

	var objective_panel := PanelContainer.new()
	objective_panel.name = "MissionCard"
	objective_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if portrait_layout:
		objective_panel.custom_minimum_size.y = 350
	else:
		objective_panel.size_flags_stretch_ratio = 1.25
	objective_panel.add_theme_stylebox_override("panel", _panel_style(Color(1.0, 0.81, 0.31)))
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(objective_panel)

	var objective_margin := MarginContainer.new()
	objective_margin.add_theme_constant_override("margin_left", 24)
	objective_margin.add_theme_constant_override("margin_right", 24)
	objective_margin.add_theme_constant_override("margin_top", 18)
	objective_margin.add_theme_constant_override("margin_bottom", 18)
	objective_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_child(objective_margin)

	var objective_stack := VBoxContainer.new()
	objective_stack.add_theme_constant_override("separation", 12)
	objective_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_margin.add_child(objective_stack)

	var objective_title := Label.new()
	objective_title.text = "MISSION PLAN"
	objective_title.add_theme_font_override("font", UI_FONT)
	objective_title.add_theme_font_size_override("font_size", 16)
	objective_title.add_theme_color_override("font_color", Color(1.0, 0.81, 0.31))
	objective_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_stack.add_child(objective_title)

	for i in range(OBJECTIVE_LINES.size()):
		var row := Label.new()
		row.text = "%d.  %s" % [i + 1, OBJECTIVE_LINES[i]]
		row.add_theme_font_size_override("font_size", 17)
		row.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		objective_stack.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_stack.add_child(spacer)

	# Which scheme the player is about to fly with, and that it is a choice.
	#
	# Nothing in the intro said this. The opening transmission is story, and the
	# level-1 tutorial teaches whichever scheme happens to be active as though it
	# were the only one, so a player learned "the" controls and never found out
	# that tilt, joystick and full-tilt existed or that orientation was settable.
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		var controls_row := Label.new()
		controls_row.text = "CONTROLS:  %s.  %s" % [
			globalvar.CONTROL_SCHEME_NAMES.get(globalvar.control_scheme, "Tilt"),
			globalvar.control_scheme_hint(),
		]
		controls_row.add_theme_font_size_override("font_size", 12)
		controls_row.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92))
		controls_row.autowrap_mode = TextServer.AUTOWRAP_WORD
		controls_row.custom_minimum_size = Vector2(360, 0)
		objective_stack.add_child(controls_row)

		var change_row := Label.new()
		change_row.text = "Change controls or orientation any time: Settings, or Controls in the pause menu."
		change_row.add_theme_font_size_override("font_size", 11)
		change_row.add_theme_color_override("font_color", Color(0.58, 0.68, 0.8))
		change_row.autowrap_mode = TextServer.AUTOWRAP_WORD
		change_row.custom_minimum_size = Vector2(360, 0)
		objective_stack.add_child(change_row)

	var launch := Button.new()
	launch.name = "BeginFlightButton"
	launch.text = "BEGIN FLIGHT  ›"
	launch.custom_minimum_size = Vector2(220, 46)
	launch.add_theme_font_override("font", UI_FONT)
	launch.add_theme_font_size_override("font_size", 16)
	BS.apply_space_style(launch, Color(0.55, 1.0, 0.68))
	launch.pressed.connect(_dismiss)
	objective_stack.add_child(launch)

	var portrait_stage := Control.new()
	portrait_stage.custom_minimum_size = Vector2(0, 360) if portrait_layout else Vector2(330, 285)
	portrait_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(portrait_stage)

	_doge = TalkingPortrait.new()
	_doge.name = "SpaceDogeCoach"
	_doge.configure(
		DOGE_TEXTURE,
		Vector2(0.5, 0.653),
		0.155,
		0.08,
		Color(0.12, 0.065, 0.045),
		Color(0.48, 0.24, 0.15),
		1.0
	)
	portrait_stage.add_child(_doge)
	_doge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var identity := Label.new()
	identity.text = "SPACEDOGE  //  FLIGHT COACH"
	portrait_stage.add_child(identity)
	identity.z_index = 3
	identity.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	identity.offset_top = -34
	identity.offset_bottom = -4
	identity.add_theme_font_override("font", UI_FONT)
	identity.add_theme_font_size_override("font_size", 12)
	identity.add_theme_color_override("font_color", Color(1.0, 0.81, 0.31))
	identity.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	identity.add_theme_constant_override("shadow_offset_x", 2)
	identity.add_theme_constant_override("shadow_offset_y", 2)
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _panel_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.022, 0.09, 0.95)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.22)
	style.shadow_size = 10
	return style


func _process(delta: float) -> void:
	_talk_elapsed += delta
	if _talk_elapsed >= 2.8 and _doge != null:
		_doge.set_talking(false)


func _dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	_doge.set_talking(false)
	Analytics.event("first_flight_briefing", {"state": "completed"})
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.22)
	fade.tween_callback(func() -> void:
		_pause_restored = true
		get_tree().paused = _was_paused
		ready_to_launch.emit()
		queue_free()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _dismissed and event.is_action_pressed("ui_accept"):
		_dismiss()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if not _pause_restored and get_tree() != null:
		_pause_restored = true
		get_tree().paused = _was_paused
