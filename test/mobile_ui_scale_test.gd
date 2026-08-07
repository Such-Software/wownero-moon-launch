class_name MobileUiScaleTest
extends GdUnitTestSuite

## TestFlight b23 testers reported "Too small", "Make text bigger" and "a lot of
## TINY text". The 1024x600 base is a desktop-era canvas, so on an iPhone 16 Pro
## a 13-unit font rendered at ~8.2pt portrait / ~8.7pt landscape — both under
## Apple's ~11pt legibility floor. These lock in the readability target and the
## constraint that caps it.

const GV = preload("res://globalvar.gd")

const IPHONE_PORTRAIT := Vector2i(1206, 2622)
const IPHONE_LANDSCAPE := Vector2i(2622, 1206)
const DEVICE_SCALE := 3.0


## Points one UI unit occupies — the thing a reader actually perceives.
func _points_per_unit(window: Vector2i) -> float:
	var scale := GV.compute_ui_scale(window, true)
	var stretch := minf(window.x / 1024.0, window.y / 600.0)
	var canvas_short := minf(window.x / stretch, window.y / stretch) / scale
	return (minf(window.x, window.y) / canvas_short) / DEVICE_SCALE


func test_body_text_clears_the_legibility_floor_in_both_orientations() -> void:
	for window in [IPHONE_PORTRAIT, IPHONE_LANDSCAPE]:
		# 13 is the death-screen advice size, the smallest body copy shipped.
		assert_float(13.0 * _points_per_unit(window)).is_greater_equal(11.0)


func test_physical_text_size_is_the_same_in_portrait_and_landscape() -> void:
	# Rotating the device must not change how big the text reads.
	assert_float(_points_per_unit(IPHONE_PORTRAIT)).is_equal_approx(
		_points_per_unit(IPHONE_LANDSCAPE), 0.01
	)


func test_canvas_still_fits_the_widest_dialog_in_landscape() -> void:
	# Landscape is the binding constraint: only 600 base units tall. The death
	# panel is 340 wide with ~432 of stacked content, so the canvas short axis
	# may not drop below that. This is what caps the readability scale.
	var scale := GV.compute_ui_scale(IPHONE_LANDSCAPE, true)
	var stretch := minf(IPHONE_LANDSCAPE.x / 1024.0, IPHONE_LANDSCAPE.y / 600.0)
	var canvas_height := (IPHONE_LANDSCAPE.y / stretch) / scale
	assert_float(canvas_height).is_greater_equal(462.0)


func test_desktop_behaviour_is_unchanged() -> void:
	# Only phones were unreadable; desktop must not resize under players.
	assert_float(GV.compute_ui_scale(Vector2i(1280, 720), false)).is_equal_approx(1.0, 0.001)
	assert_float(GV.compute_ui_scale(Vector2i(720, 1280), false)).is_equal_approx(
		GV.PORTRAIT_UI_SCALE, 0.001
	)


func test_scale_never_shrinks_the_ui_below_its_previous_size() -> void:
	# A small or oddly-reported window must never scale the UI down.
	for window in [Vector2i(320, 240), Vector2i(1024, 600), Vector2i(800, 600)]:
		assert_float(GV.compute_ui_scale(window, true)).is_greater_equal(1.0)


func test_degenerate_window_is_handled_without_dividing_by_zero() -> void:
	for window in [Vector2i(0, 0), Vector2i(0, 720), Vector2i(1280, 0)]:
		assert_float(GV.compute_ui_scale(window, true)).is_equal_approx(1.0, 0.001)
