extends Node
## Autoload singleton consolidating one-time hints + transient toasts into a single
## top-center banner. Styled like the Level 1 tutorial label (Level1.gd:36-46) and driven
## by a HOLD->FADE state machine. Hints queue and never overlap; it lives on its own
## high-index CanvasLayer so it renders in any scene.
##
## API:
##   HintService.show_hint(id, text, duration := 4.0)  # one-time, keyed on `id`
##   HintService.toast(text, duration := 3.0)          # always shows
##   HintService.was_shown(id) -> bool

# Banner pacing (seconds) — mirrors the Level1 tutorial state machine.
const HOLD_FADE := 1.0   # fade-out duration

enum BannerState { IDLE, HOLD, FADE }

var _layer: CanvasLayer = null
var _label: Label = null
var _queue: Array[Dictionary] = []
var _state: int = BannerState.IDLE
var _timer := 0.0
var _suppressed := false
var _save_pending := false


func _ready() -> void:
	# Suppress under automated capture/autopilot/sim runs (convention #2), unless the
	# SML_SHOW_HINTS=1 escape hatch is set (e.g. to record a hint-showcase video).
	var argv := OS.get_cmdline_args()
	var capture := "--capture" in argv or "--autopilot" in argv or "--sim" in argv
	_suppressed = capture and OS.get_environment("SML_SHOW_HINTS") != "1"

	# Own CanvasLayer at a high index so the banner draws above any scene's UI.
	_layer = CanvasLayer.new()
	_layer.layer = 128
	_layer.name = "HintLayer"
	add_child(_layer)

	# Banner label — styled exactly like the Level 1 tutorial label (Level1.gd:36-46).
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 80
	_label.offset_bottom = 120
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.modulate = Color(1, 1, 1, 0)
	_layer.add_child(_label)

	set_process(true)


func show_hint(id: String, text: String, duration := 4.0) -> void:
	## Enqueue a one-time hint keyed on `id`. No-op if it has already been shown.
	if _suppressed:
		return
	if was_shown(id):
		return
	# Mark seen immediately so rapid repeat calls don't double-queue it.
	globalvar.seen_hints.append(id)
	# Debounce persistence: several hints can be enqueued in one frame (e.g. a level
	# start firing multiple first-encounter banners); coalesce to a single save.
	_queue_save()
	_queue.append({"text": text, "duration": duration, "id": id})


func toast(text: String, duration := 3.0) -> void:
	## Enqueue a transient toast — always shows, never persisted.
	if _suppressed:
		return
	_queue.append({"text": text, "duration": duration, "id": ""})


func was_shown(id: String) -> bool:
	return id in globalvar.seen_hints


func _process(delta: float) -> void:
	if _state == BannerState.IDLE:
		if _queue.is_empty():
			return
		_present_next()
		return

	_timer -= delta
	if _timer > 0.0:
		if _state == BannerState.FADE:
			_label.modulate.a = clampf(_timer / HOLD_FADE, 0.0, 1.0)
		return

	# Timer expired — advance the state machine.
	match _state:
		BannerState.HOLD:
			_state = BannerState.FADE
			_timer = HOLD_FADE
		BannerState.FADE:
			_label.modulate.a = 0.0
			_state = BannerState.IDLE


func _present_next() -> void:
	var item: Dictionary = _queue.pop_front()
	_label.text = str(item.get("text", ""))
	_label.modulate = Color(1, 1, 1, 1)
	_state = BannerState.HOLD
	_timer = float(item.get("duration", 4.0))
	var id := str(item.get("id", ""))
	if id != "":
		_fire_analytics(id)


func _fire_analytics(id: String) -> void:
	# Route through the generic bucketed sink (convention #4); Analytics has no
	# hint-specific method, so use event() rather than inventing one.
	var node := get_node_or_null("/root/Analytics")
	if node and node.has_method("event"):
		node.call("event", "hint_shown", {"hint_id": id})


func _queue_save() -> void:
	# One coalesced save per frame regardless of how many hints were enqueued.
	if _save_pending:
		return
	_save_pending = true
	call_deferred("_flush_save")


func _flush_save() -> void:
	_save_pending = false
	globalvar.save_game()
