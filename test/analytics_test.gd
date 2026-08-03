class_name AnalyticsTest
extends GdUnitTestSuite


func test_analytics_uses_canonical_platform_app_id() -> void:
	assert_str(Analytics.APP_ID).is_equal("moon_launch")


func test_required_event_params_are_injected_by_the_wrapper() -> void:
	var params := Analytics._required_params()
	assert_array(params.keys()).contains_exactly([
		"app_version",
		"build_number",
		"device_id",
		"session_id",
		"is_first_session",
	])
