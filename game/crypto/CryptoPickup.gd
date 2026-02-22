extends Area2D
## Reusable crypto pickup. Place in any level, configure type & amount in editor.
## Spins, bobs, detects Rocket contact, adds to globalvar wallet.
##
## Usage: instance CryptoPickup.tscn, set crypto_type and amount via editor or code.
## The pickup auto-removes itself on collection.

## Which crypto this pickup represents
@export_enum("WOW", "XMR", "BTC", "DOGE") var crypto_type: String = "WOW"
## How many WOW-equivalent this pickup is worth
@export var amount: int = 1

# Visual
var _elapsed: float = 0.0
var _start_y: float = 0.0
var _bob_amplitude: float = 6.0
var _bob_speed: float = 2.5
var _spin_speed: float = 90.0  # degrees/sec
var _collected: bool = false

# Color per crypto type
const TYPE_COLORS := {
	"WOW": Color(0.3, 0.8, 1.0),    # cyan
	"XMR": Color(0.7, 0.3, 1.0),    # purple
	"BTC": Color(1.0, 0.85, 0.2),   # gold
	"DOGE": Color(1.0, 0.7, 0.3),   # orange
}

# WOW multipliers
const TYPE_MULTIPLIERS := {
	"WOW": 1,
	"XMR": 10,
	"BTC": 50,
	"DOGE": 5,
}


func _ready() -> void:
	_start_y = position.y
	# Connect body_entered for Rocket detection
	body_entered.connect(_on_body_entered)
	# Set collision: detect layer 1 (rocket default)
	collision_layer = 0
	collision_mask = 1


func _process(delta: float) -> void:
	if _collected:
		return
	_elapsed += delta
	# Bob up and down
	position.y = _start_y + sin(_elapsed * _bob_speed) * _bob_amplitude
	queue_redraw()


func _draw() -> void:
	if _collected:
		return
	var color: Color = TYPE_COLORS.get(crypto_type, Color.WHITE)
	# Outer glow
	draw_circle(Vector2.ZERO, 14.0, Color(color.r, color.g, color.b, 0.2))
	# Coin body
	draw_circle(Vector2.ZERO, 10.0, color.darkened(0.3))
	draw_circle(Vector2.ZERO, 8.0, color)
	# Letter in center
	var letter := crypto_type[0]  # W, X, B, D
	var font := ThemeDB.fallback_font
	if font:
		var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		draw_string(font, Vector2(-text_size.x * 0.5, text_size.y * 0.25), letter,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.BLACK)
	# Spin ring
	var ring_angle := fmod(_elapsed * _spin_speed * 0.02, TAU)
	var ring_pt := Vector2(cos(ring_angle), sin(ring_angle)) * 12.0
	draw_circle(ring_pt, 2.0, Color(color.r, color.g, color.b, 0.6))


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if not body.is_in_group("rocket"):
		return
	_collected = true
	# Calculate value
	var value: int = amount * TYPE_MULTIPLIERS.get(crypto_type, 1)
	globalvar.add_crypto(value)
	# Popup text
	_spawn_popup(value)
	# Remove
	queue_free()


func _spawn_popup(value: int) -> void:
	var label := Label.new()
	label.text = "+" + str(value) + " WOW"
	label.add_theme_color_override("font_color", TYPE_COLORS.get(crypto_type, Color.WHITE))
	label.add_theme_font_size_override("font_size", 14)
	label.position = global_position - Vector2(20, 20)
	label.z_index = 100
	# Add to the level root so it persists after we queue_free
	get_parent().add_child(label)
	# Animate up and fade out
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)
