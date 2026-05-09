class_name TelemetryTest
extends GdUnitTestSuite
## Unit tests for Telemetry.gd
## Without the Firebase plugin (everywhere right now), all calls no-op.


func test_initialized_is_false_without_plugin() -> void:
	assert_bool(Telemetry._initialized).is_false()


# ==========================================================================
#  NO-OP SAFETY
# ==========================================================================

func test_log_event_noop_when_uninitialized() -> void:
	# Should not crash even with rich params.
	Telemetry.log_event(Telemetry.EVENT_LEVEL_COMPLETE, {
		"level": 3,
		"time_s": 24.5,
		"stars": 3,
		"moonrocks": 75,
	})
	assert_bool(Telemetry._initialized).is_false()


func test_set_user_property_noop_when_uninitialized() -> void:
	Telemetry.set_user_property("total_moonrocks", "1234")
	assert_bool(Telemetry._initialized).is_false()


func test_record_error_noop_when_uninitialized() -> void:
	Telemetry.record_error("test message", false)
	Telemetry.record_error("fatal test", true)
	assert_bool(Telemetry._initialized).is_false()


# ==========================================================================
#  EVENT NAME CATALOG (stable strings)
# ==========================================================================

func test_event_names_are_stable() -> void:
	# These strings show up in analytics dashboards. Don't break them silently.
	assert_str(Telemetry.EVENT_APP_OPEN).is_equal("app_open")
	assert_str(Telemetry.EVENT_LEVEL_START).is_equal("level_start")
	assert_str(Telemetry.EVENT_LEVEL_COMPLETE).is_equal("level_complete")
	assert_str(Telemetry.EVENT_LEVEL_DEATH).is_equal("level_death")
	assert_str(Telemetry.EVENT_IAP_INITIATED).is_equal("iap_initiated")
	assert_str(Telemetry.EVENT_IAP_COMPLETED).is_equal("iap_completed")
	assert_str(Telemetry.EVENT_REWARDED_WATCHED).is_equal("rewarded_watched")
	assert_str(Telemetry.EVENT_SHARE_PRESSED).is_equal("share_pressed")
	assert_str(Telemetry.EVENT_RATE_PROMPT_SHOWN).is_equal("rate_prompt_shown")
