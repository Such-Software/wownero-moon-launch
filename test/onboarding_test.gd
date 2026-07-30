class_name OnboardingTest
extends GdUnitTestSuite

const OpeningTransmissionScene = preload("res://game/gui/onboarding/OpeningTransmission.gd")
const FirstFlightBriefingScene = preload("res://game/gui/onboarding/FirstFlightBriefing.gd")


func test_opening_transmission_is_readable_and_player_facing() -> void:
	var beats := OpeningTransmissionScene.dialogue_beats()
	assert_int(beats.size()).is_equal(3)
	assert_str(str(beats[0]["actor"])).is_equal("alien")
	assert_str(str(beats[1]["actor"])).is_equal("doge")
	assert_bool(str(beats[2]["text"]).contains("Pilot, you're up")).is_true()
	var total_duration := 0.0
	for beat in beats:
		total_duration += float(beat["duration"])
	assert_float(total_duration).is_greater_equal(14.5)
	assert_float(total_duration).is_less_equal(16.0)


func test_first_flight_briefing_teaches_route_and_braking() -> void:
	var briefing := FirstFlightBriefingScene.briefing_copy()
	assert_str(str(briefing["coach"])).contains("Earth's gravity")
	var objectives: Array = briefing["objectives"]
	assert_int(objectives.size()).is_equal(3)
	assert_bool(str(objectives[1]).contains("gravity")).is_true()
	assert_bool(str(objectives[2]).contains("reverse thrust")).is_true()
