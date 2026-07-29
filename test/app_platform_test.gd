class_name AppPlatformTest
extends GdUnitTestSuite

const Features = preload("res://game/platform/AppPlatformFeatures.gd")
const Transport = preload("res://game/platform/transport/RoomTransport.gd")
const RoomBroker = preload(
	"res://game/platform/transport/NakamaRoomBroker.gd"
)


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


func test_transport_rejects_extra_fields_and_raw_identity() -> void:
	var extra := Transport.make_envelope(&"race_state", 1, {})
	extra["purchase"] = true
	assert_str(str(Transport.validate_envelope(extra))).is_equal("shape")

	var identity := Transport.make_envelope(
		&"race_state",
		1,
		{"player": {"user_id": "must-never-cross-the-room-boundary"}}
	)
	assert_str(str(Transport.validate_envelope(identity))).is_equal(
		"forbidden_payload"
	)


func test_room_descriptor_is_neutral_and_exact() -> void:
	var descriptor := {
		"room_code": "MN2P42",
		"match_id": "relayed.match-01",
		"protocol_version": 1,
		"max_players": 2,
		"expires_at": "2026-07-29T23:59:59.000Z",
	}
	assert_str(str(RoomBroker.validate_descriptor(descriptor))).is_empty()
	descriptor["user_id"] = "must-not-appear"
	assert_str(str(RoomBroker.validate_descriptor(descriptor))).is_equal("shape")


func test_room_descriptor_rejects_ambiguous_codes() -> void:
	var descriptor := {
		"room_code": "IO0110",
		"match_id": "relayed.match-01",
		"protocol_version": 1,
		"max_players": 2,
		"expires_at": "2026-07-29T23:59:59.000Z",
	}
	assert_str(str(RoomBroker.validate_descriptor(descriptor))).is_equal(
		"room_code"
	)
