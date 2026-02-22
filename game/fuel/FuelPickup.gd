extends Area2D
## Floating fuel canister pickup. Restores a percentage of max fuel on collection.
## Drawn entirely in code — green canister with glow effects.
##
## Usage: instance FuelPickup.tscn, optionally set fuel_percent in editor.

## Fraction of max_fuel restored (0.0 – 1.0). Default = 25%
@export var fuel_percent: float = 0.25

var _elapsed: float = 0.0
var _start_y: float = 0.0
var _collected: bool = false

const BOB_AMPLITUDE := 6.0
const BOB_SPEED := 2.2
const CANISTER_COLOR := Color(0.15, 0.85, 0.3)   # bright green
const GLOW_COLOR := Color(0.2, 1.0, 0.4)
const PULSE_SPEED := 3.5
const PULSE_AMP := 0.12
const SIZE := Vector2(12, 18)  # half-extents of the canister shape


func _ready() -> void:
	_start_y = position.y
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	collision_mask = 1  # detect Rocket (layer 1)
	queue_redraw()


func _process(delta: float) -> void:
	if _collected:
		return
	_elapsed += delta
	position.y = _start_y + sin(_elapsed * BOB_SPEED) * BOB_AMPLITUDE
	queue_redraw()


func _draw() -> void:
	if _collected:
		return
	var pulse := 0.5 + 0.5 * sin(_elapsed * PULSE_SPEED)
	var scale_f := 1.0 + sin(_elapsed * PULSE_SPEED) * PULSE_AMP

	# --- Glow layers ---
	var ga := lerpf(0.08, 0.22, pulse)
	draw_circle(Vector2.ZERO, 22.0, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, ga))
	draw_circle(Vector2.ZERO, 16.0, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, ga * 1.5))

	# --- Canister body (rounded rect) ---
	var half := SIZE * scale_f
	var rect := Rect2(-half.x, -half.y, half.x * 2, half.y * 2)
	draw_rect(rect, CANISTER_COLOR)
	# Dark border
	draw_rect(rect, Color(0.05, 0.3, 0.1), false, 1.5)

	# --- Cap / nozzle at top ---
	var cap_w := half.x * 0.5
	var cap_rect := Rect2(-cap_w, -half.y - 4 * scale_f, cap_w * 2, 4 * scale_f)
	draw_rect(cap_rect, Color(0.5, 0.5, 0.5))

	# --- "F" label ---
	var font := ThemeDB.fallback_font
	if font:
		var f_color := Color(1.0, 1.0, 1.0, lerpf(0.7, 1.0, pulse))
		draw_string(font, Vector2(-4 * scale_f, 5 * scale_f), "F",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * scale_f), f_color)

	# --- Specular highlight ---
	var spec_alpha := lerpf(0.15, 0.4, pulse)
	draw_circle(Vector2(-half.x * 0.35, -half.y * 0.4), 2.0, Color(1, 1, 1, spec_alpha))


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if not body.is_in_group("rocket"):
		return
	_collected = true
	visible = false

	# Restore fuel
	var restored: float = body.max_fuel * fuel_percent
	body.fuel = minf(body.fuel + restored, body.max_fuel)

	_spawn_popup(restored)
	queue_free()


func _spawn_popup(amount: float) -> void:
	var label := Label.new()
	label.text = "+%d FUEL" % int(amount)
	label.add_theme_color_override("font_color", CANISTER_COLOR)
	label.add_theme_font_size_override("font_size", 14)
	label.position = global_position - Vector2(28, 20)
	label.z_index = 100
	get_parent().add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)
