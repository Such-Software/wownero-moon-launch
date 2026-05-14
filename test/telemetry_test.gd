class_name TelemetryTest
extends GdUnitTestSuite
## Unit tests for Telemetry.gd
## Telemetry is now backend-driven: events buffer locally and POST to
## /v1/events in batches. The autoload always initializes (HTTP transport
## works on every platform), so _initialized is true on all platforms.


# ==========================================================================
#  INITIALIZATION
# ==========================================================================

func test_initialized_after_autoload_ready() -> void:
	# Backend-driven Telemetry initializes on every platform — there's no
	# native plugin gating it.
	assert_bool(Telemetry._initialized).is_true()


# ==========================================================================
#  NO-CRASH SAFETY — exercised on the test platform (desktop/headless).
#  Calls must never throw, even with weird payloads.
# ==========================================================================

func test_log_event_does_not_crash_with_rich_params() -> void:
	# Should buffer without error. Any HTTP-level failure is swallowed by the
	# fire-and-forget design.
	var before_size: int = Telemetry._buffer.size()
	Telemetry.log_event(Telemetry.EVENT_LEVEL_COMPLETE, {
		"level": 3,
		"time_s": 24.5,
		"stars": 3,
		"moonrocks": 75,
	})
	# Buffer grew by exactly one (or stayed same if just flushed at the cap).
	var after_size: int = Telemetry._buffer.size()
	assert_bool(after_size == before_size + 1 or after_size == 0).is_true()


func test_set_user_property_does_not_crash() -> void:
	Telemetry.set_user_property("total_moonrocks", "1234")


func test_record_error_does_not_crash() -> void:
	Telemetry.record_error("non-fatal test message", false)


func test_record_fatal_error_does_not_crash() -> void:
	Telemetry.record_error("fatal test message", true)


# ==========================================================================
#  EVENT NAME CATALOG (stable strings)
# ==========================================================================

func test_event_names_are_stable() -> void:
	# These strings show up in analytics queries and the daily digest. Don't
	# break them silently.
	assert_str(Telemetry.EVENT_APP_OPEN).is_equal("app_open")
	assert_str(Telemetry.EVENT_LEVEL_START).is_equal("level_start")
	assert_str(Telemetry.EVENT_LEVEL_COMPLETE).is_equal("level_complete")
	assert_str(Telemetry.EVENT_LEVEL_DEATH).is_equal("level_death")
	assert_str(Telemetry.EVENT_IAP_INITIATED).is_equal("iap_initiated")
	assert_str(Telemetry.EVENT_IAP_COMPLETED).is_equal("iap_completed")
	assert_str(Telemetry.EVENT_REWARDED_WATCHED).is_equal("rewarded_watched")
	assert_str(Telemetry.EVENT_SHARE_PRESSED).is_equal("share_pressed")
	assert_str(Telemetry.EVENT_RATE_PROMPT_SHOWN).is_equal("rate_prompt_shown")
	assert_str(Telemetry.EVENT_ERROR).is_equal("error")


func test_app_name_is_moonlaunch() -> void:
	# Server validates against {"moonlaunch","bauhaus","suchoice"}. Don't
	# accidentally rename to "such_moon_launch".
	assert_str(Telemetry.APP_NAME).is_equal("moonlaunch")


# ==========================================================================
#  BUFFER SAFETY
# ==========================================================================

func test_buffer_caps_at_max_dropped() -> void:
	# Stress: log many events, ensure the buffer doesn't grow past the cap.
	# (At test time the HTTP request will fail since there's no real server,
	# so the buffer accumulates until the safety cap kicks in.)
	for i in 250:
		Telemetry.log_event("stress_test", {"i": i})
	assert_int(Telemetry._buffer.size()).is_less_equal(Telemetry.MAX_DROPPED_BEFORE_GIVEUP)
