extends RefCounted
## Static utility for applying consistent space-themed button styles.
## Usage: const BS = preload("res://game/gui/ButtonStyles.gd")
##        BS.apply_space_style(button, color)


## Apply a glowing space-themed style to a Button node.
## color: the accent/border color (e.g. Color.CYAN, Color.GREEN, Color.RED)
static func apply_space_style(btn: Button, accent: Color = Color.CYAN) -> void:
	btn.flat = false

	# Normal state
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.06, 0.14, 0.9)
	normal.border_color = accent * 0.8
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	# Glow via shadow
	normal.shadow_color = Color(accent.r, accent.g, accent.b, 0.3)
	normal.shadow_size = 6
	btn.add_theme_stylebox_override("normal", normal)

	# Hover state — brighter border + lighter bg
	var hover := normal.duplicate()
	hover.bg_color = Color(0.1, 0.1, 0.22, 0.95)
	hover.border_color = accent
	hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.5)
	hover.shadow_size = 10
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed state — inverted feel
	var pressed := normal.duplicate()
	pressed.bg_color = Color(accent.r * 0.2, accent.g * 0.2, accent.b * 0.2, 0.95)
	pressed.border_color = Color.WHITE
	pressed.shadow_color = Color(accent.r, accent.g, accent.b, 0.6)
	pressed.shadow_size = 12
	btn.add_theme_stylebox_override("pressed", pressed)

	# Focus state
	var focus := hover.duplicate()
	btn.add_theme_stylebox_override("focus", focus)

	# Text color
	btn.add_theme_color_override("font_color", accent)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", accent.lightened(0.3))
	btn.add_theme_color_override("font_focus_color", accent)


## Convenience: apply to all Button children in a container
static func style_all_buttons(container: Node, accent: Color = Color.CYAN) -> void:
	for child in container.get_children():
		if child is Button:
			apply_space_style(child, accent)
