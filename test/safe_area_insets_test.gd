class_name SafeAreaInsetsTest
extends GdUnitTestSuite

## The iPhone camera cutout ("Dynamic Island") and home indicator sit on top of a
## full-screen framebuffer, so a screenshot looks correct while the UI underneath
## is physically covered. TestFlight b22/b23 testers reported exactly that: a
## hidden pause button and bottom buttons that "aren't showing".

const GV = preload("res://globalvar.gd")


func test_no_cutout_reports_zero_so_desktop_layout_is_unchanged() -> void:
	# Full-screen safe rect: every inset must be zero, not "the whole screen".
	var insets := GV.compute_safe_area_insets(
		Vector2i(1280, 720), Rect2i(0, 0, 1280, 720), Vector2(1280, 720)
	)
	assert_float(insets["left"]).is_equal_approx(0.0, 0.001)
	assert_float(insets["top"]).is_equal_approx(0.0, 0.001)
	assert_float(insets["right"]).is_equal_approx(0.0, 0.001)
	assert_float(insets["bottom"]).is_equal_approx(0.0, 0.001)


func test_degenerate_safe_rect_never_pushes_controls_off_screen() -> void:
	# An unreported safe area must fail SAFE (zero inset), never consume the view.
	for safe in [Rect2i(0, 0, 0, 0), Rect2i(0, 0, 1280, 0), Rect2i(0, 0, 0, 720)]:
		var insets := GV.compute_safe_area_insets(
			Vector2i(1280, 720), safe, Vector2(1280, 720)
		)
		assert_float(insets["top"]).is_equal_approx(0.0, 0.001)
		assert_float(insets["bottom"]).is_equal_approx(0.0, 0.001)


func test_portrait_cutout_is_converted_into_view_units() -> void:
	# iPhone 16 Pro portrait: 1206x2622 px, 59pt island + 34pt home indicator at
	# 3x = 177px top and 102px bottom. The view is the post-content-scale size.
	var insets := GV.compute_safe_area_insets(
		Vector2i(1206, 2622),
		Rect2i(0, 177, 1206, 2622 - 177 - 102),
		Vector2(603, 1311)  # exactly half, so 1px screen == 0.5 view units
	)
	assert_float(insets["top"]).is_equal_approx(88.5, 0.01)
	assert_float(insets["bottom"]).is_equal_approx(51.0, 0.01)
	assert_float(insets["left"]).is_equal_approx(0.0, 0.01)
	assert_float(insets["right"]).is_equal_approx(0.0, 0.01)


func test_landscape_cutout_insets_the_side_the_camera_is_on() -> void:
	# Rotated, the island eats a horizontal strip instead of a vertical one.
	var insets := GV.compute_safe_area_insets(
		Vector2i(2622, 1206), Rect2i(177, 0, 2622 - 177 - 102, 1206), Vector2(2622, 1206)
	)
	assert_float(insets["left"]).is_equal_approx(177.0, 0.01)
	assert_float(insets["right"]).is_equal_approx(102.0, 0.01)
	assert_float(insets["top"]).is_equal_approx(0.0, 0.01)


func test_zero_sized_window_or_view_is_handled_without_dividing_by_zero() -> void:
	for window in [Vector2i(0, 0), Vector2i(1280, 0)]:
		var insets := GV.compute_safe_area_insets(window, Rect2i(0, 0, 10, 10), Vector2(1280, 720))
		assert_float(insets["top"]).is_equal_approx(0.0, 0.001)
	var no_view := GV.compute_safe_area_insets(
		Vector2i(1280, 720), Rect2i(0, 10, 1280, 700), Vector2(0, 0)
	)
	assert_float(no_view["top"]).is_equal_approx(0.0, 0.001)
