extends Control
## HUD wallet display — shows current Moonrocks balance from globalvar.
## Standalone widget: create with Control.new(), set_script(), add_child().

var _display_amount: int = 0  # animated counter
var _target_amount: int = 0


func _ready() -> void:
	_target_amount = globalvar.wallet
	_display_amount = _target_amount
	globalvar.wallet_changed.connect(_on_wallet_changed)


func _on_wallet_changed(new_total: int) -> void:
	_target_amount = new_total


func _process(delta: float) -> void:
	# Animate the counter toward the target
	if _display_amount < _target_amount:
		_display_amount = mini(_display_amount + maxi(1, int((_target_amount - _display_amount) * 8 * delta)), _target_amount)
	elif _display_amount > _target_amount:
		_display_amount = _target_amount
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if not font:
		return
	var text := str(_display_amount) + " 🪨"
	var color := Color(1.0, 0.85, 0.2, 0.9)  # gold
	draw_string(font, Vector2(0, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
