class_name AppPlatformTest
extends GdUnitTestSuite

const Features = preload("res://game/platform/AppPlatformFeatures.gd")
const Transport = preload("res://game/platform/transport/RoomTransport.gd")


func test_rollout_features_default_closed() -> void:
	assert_bool(Features.all_closed()).is_true()


func test_transport_base_fails_closed() -> void:
	var transport := Transport.new()
	assert_dict(transport.create({})).is_empty()
	assert_int(transport.status).is_equal(Transport.Status.FAILED)


func test_transport_envelope_is_versioned_and_ordered() -> void:
	var envelope := Transport.make_envelope(&"race_state", 1, {"x": 12.5})
	assert_str(str(Transport.validate_envelope(envelope))).is_empty()
	assert_int(int(envelope["protocol_version"])).is_equal(1)
	assert_int(int(envelope["sequence"])).is_equal(1)


func test_transport_rejects_bad_protocol() -> void:
	var envelope := Transport.make_envelope(&"race_state", 1, {})
	envelope["protocol_version"] = 2
	assert_str(str(Transport.validate_envelope(envelope))).is_equal("protocol_version")


func test_transport_rejects_replay_sequence() -> void:
	var envelope := Transport.make_envelope(&"race_state", 0, {})
	assert_str(str(Transport.validate_envelope(envelope))).is_equal("sequence")


func test_transport_rejects_oversized_payload() -> void:
	var envelope := Transport.make_envelope(
		&"race_state",
		1,
		{"blob": "x".repeat(Transport.MAX_PAYLOAD_BYTES)}
	)
	assert_str(str(Transport.validate_envelope(envelope))).is_equal("oversized")
