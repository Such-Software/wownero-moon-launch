extends Area2D
## Reusable crypto pickup. Place in any level, configure type & amount in editor.
## Uses actual coin art from art/coins/. Bobs, glows, detects Rocket contact.
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
var _bob_amplitude: float = 8.0
var _bob_speed: float = 2.8
var _collected: bool = false
var _sprite: Sprite2D = null

# Color per crypto type (used for glow and popup)
const TYPE_COLORS := {
	"WOW": Color(0.3, 0.85, 1.0),   # bright cyan
	"XMR": Color(0.75, 0.35, 1.0),  # vivid purple
	"BTC": Color(1.0, 0.85, 0.15),  # bright gold
	"DOGE": Color(1.0, 0.65, 0.2),  # warm orange
}

# Texture paths per crypto type
const TYPE_TEXTURES := {
	"WOW": "res://art/coins/wow_small_simple.png",
	"XMR": "res://art/coins/monero.png",
	"BTC": "res://art/coins/bitcoin.png",
	"DOGE": "res://art/coins/grin.png",
}

# WOW multipliers
const TYPE_MULTIPLIERS := {
	"WOW": 1,
	"XMR": 10,
	"BTC": 50,
	"DOGE": 5,
}

# Target display size for coins
const COIN_SIZE := 30.0

# Glow & pulse tuning
const PULSE_SPEED := 4.0
const PULSE_AMPLITUDE := 0.18   # ±18% scale swing
const GLOW_OUTER_RADIUS := 28.0
const GLOW_MID_RADIUS := 20.0
const GLOW_INNER_RADIUS := 14.0


func _ready() -> void:
	_start_y = position.y
	add_to_group("crypto_pickup")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	collision_mask = 1
	_create_sprite()


func _create_sprite() -> void:
	var tex_path: String = TYPE_TEXTURES.get(crypto_type, TYPE_TEXTURES["WOW"])
	var tex = load(tex_path)
	if not tex:
		return

	# Coin sprite
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	var tex_size: Vector2 = tex.get_size()
	var scale_factor: float = COIN_SIZE / maxf(tex_size.x, tex_size.y)
	_sprite.scale = Vector2(scale_factor, scale_factor)
	add_child(_sprite)
	queue_redraw()


func _process(delta: float) -> void:
	if _collected:
		return
	_elapsed += delta
	# Bob up and down
	position.y = _start_y + sin(_elapsed * _bob_speed) * _bob_amplitude
	# Strong pulse on sprite
	if _sprite:
		var pulse := 1.0 + sin(_elapsed * PULSE_SPEED) * PULSE_AMPLITUDE
		var base_tex = _sprite.texture
		if base_tex:
			var tex_size: Vector2 = base_tex.get_size()
			var base_scale: float = COIN_SIZE / maxf(tex_size.x, tex_size.y)
			_sprite.scale = Vector2(base_scale * pulse, base_scale * pulse)
	queue_redraw()


func _draw() -> void:
	if _collected:
		return
	var c: Color = TYPE_COLORS.get(crypto_type, Color.WHITE)
	var glow_pulse := 0.5 + 0.5 * sin(_elapsed * PULSE_SPEED * 0.7)

	# --- Multi-layer pulsing glow (strong, color-matched) ---
	# Outermost halo
	var outer_alpha: float = lerpf(0.10, 0.25, glow_pulse)
	draw_circle(Vector2.ZERO, GLOW_OUTER_RADIUS, Color(c.r, c.g, c.b, outer_alpha))
	# Middle glow
	var mid_alpha: float = lerpf(0.18, 0.40, glow_pulse)
	draw_circle(Vector2.ZERO, GLOW_MID_RADIUS, Color(c.r, c.g, c.b, mid_alpha))
	# Inner core glow
	var inner_alpha: float = lerpf(0.25, 0.50, glow_pulse)
	draw_circle(Vector2.ZERO, GLOW_INNER_RADIUS, Color(c.r, c.g, c.b, inner_alpha))

	# --- 3D-style rim highlight (arc at top-left) ---
	var rim_color := Color(1.0, 1.0, 1.0, lerpf(0.15, 0.35, glow_pulse))
	var coin_r: float = COIN_SIZE * 0.5
	draw_arc(Vector2.ZERO, coin_r - 1.0, deg_to_rad(-140), deg_to_rad(-40), 16, rim_color, 1.5)

	# --- 3D shadow underneath ---
	var shadow_offset := Vector2(1.5, 3.0)
	draw_circle(shadow_offset, coin_r * 0.8, Color(0.0, 0.0, 0.0, 0.2))

	# --- Specular dot (top-left of coin) ---
	var spec_pos := Vector2(-coin_r * 0.3, -coin_r * 0.35)
	var spec_alpha: float = lerpf(0.2, 0.55, glow_pulse)
	draw_circle(spec_pos, 2.5, Color(1.0, 1.0, 1.0, spec_alpha))


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if not body.is_in_group("rocket"):
		return
	_collected = true
	visible = false
	var value: int = amount * TYPE_MULTIPLIERS.get(crypto_type, 1)
	globalvar.add_crypto(value)
	_spawn_popup(value)
	_spawn_sparkles()
	_play_coin_sound(value)
	# Light haptic on pickup
	Input.vibrate_handheld(30)
	queue_free()


func _spawn_popup(value: int) -> void:
	var label := Label.new()
	label.text = "+" + str(value) + " 🪨"
	label.add_theme_color_override("font_color", TYPE_COLORS.get(crypto_type, Color.WHITE))
	label.add_theme_font_size_override("font_size", 14)
	label.position = global_position - Vector2(20, 20)
	label.z_index = 100
	get_parent().add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)


func _spawn_sparkles() -> void:
	## Burst of colored sparkle dots radiating outward from the pickup location.
	var color: Color = TYPE_COLORS.get(crypto_type, Color.WHITE)
	var parent := get_parent()
	var origin := global_position
	var count := 8 + randi() % 5  # 8-12 sparkles
	for i in count:
		var dot := Label.new()
		dot.text = "✦"
		dot.add_theme_font_size_override("font_size", randi_range(10, 18))
		# Alternate between type color and white for variety
		var dot_color := color if i % 3 != 0 else Color(1.0, 1.0, 0.9)
		dot.add_theme_color_override("font_color", dot_color)
		dot.position = origin
		dot.z_index = 100
		parent.add_child(dot)
		# Random direction and speed
		var angle := TAU * float(i) / float(count) + randf() * 0.4
		var dist := randf_range(30.0, 65.0)
		var target_pos := origin + Vector2(cos(angle), sin(angle)) * dist
		var duration := randf_range(0.35, 0.6)
		var tw := dot.create_tween()
		tw.set_parallel(true)
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(dot, "position", target_pos, duration)
		tw.tween_property(dot, "modulate:a", 0.0, duration)
		tw.tween_property(dot, "scale", Vector2(0.3, 0.3), duration)
		tw.chain().tween_callback(dot.queue_free)


func _play_coin_sound(value: int) -> void:
	## Procedural coin ding — uses proximity_beep pitched up for a satisfying chime.
	## Higher-value pickups get a lower, richer tone.
	var player := AudioStreamPlayer.new()
	player.stream = load("res://art/audio/proximity_beep.ogg")
	# Pitch: WOW=high ding, DOGE=mid, XMR=lower, BTC=deep rich tone
	match crypto_type:
		"WOW": player.pitch_scale = randf_range(2.8, 3.2)
		"DOGE": player.pitch_scale = randf_range(2.2, 2.6)
		"XMR": player.pitch_scale = randf_range(1.8, 2.0)
		"BTC": player.pitch_scale = randf_range(1.4, 1.6)
		_: player.pitch_scale = 2.5
	player.volume_db = -6.0
	get_parent().add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
