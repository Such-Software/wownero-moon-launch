class_name NakamaRelayedTransportTest
extends GdUnitTestSuite

const RelayedTransport = preload(
	"res://game/platform/transport/NakamaRelayedTransport.gd"
)
const TransportContract = preload(
	"res://game/platform/transport/RoomTransport.gd"
)

const HOST_SESSION := "host-session-internal"
const GUEST_SESSION := "guest-session-internal"
const MATCH_ID := "relayed.match-test"


class FakeMatchResult extends RefCounted:
	var authoritative := false
	var match_id := MATCH_ID
	var size := 1
	var self_user: Dictionary
	var presences: Array

	func _init(local_session: String, others: Array) -> void:
		self_user = {"session_id": local_session}
		presences = others
		size = others.size() + 1

	func is_exception() -> bool:
		return false


class FakeSocket extends RefCounted:
	signal closed
	signal connection_error(error: Variant)
	signal received_error(error: Variant)
	signal received_match_state(state: Variant)
	signal received_match_presence(event: Variant)

	var create_result: FakeMatchResult
	var join_result: FakeMatchResult
	var send_calls: Array = []
	var leave_calls: Array = []

	func create_match_async() -> FakeMatchResult:
		return create_result

	func join_match_async(_match_id: String) -> FakeMatchResult:
		return join_result

	func leave_match_async(match_id: String) -> void:
		leave_calls.append(match_id)

	func send_match_state_async(
		match_id: String,
		op_code: int,
		data: String,
		_presences: Variant = null
	) -> void:
		send_calls.append({
			"match_id": match_id,
			"op_code": op_code,
			"data": data,
		})


class FakeBroker extends RefCounted:
	var descriptor := {
		"room_code": "MN2P42",
		"match_id": MATCH_ID,
		"protocol_version": 1,
		"max_players": 2,
		"expires_at": "2030-07-29T23:59:59.000Z",
	}
	var close_calls: Array = []

	func register_room(_match_id: String) -> Dictionary:
		return descriptor.duplicate(true)

	func resolve_room(_room_code: String) -> Dictionary:
		return descriptor.duplicate(true)

	func close_room(room_code: String) -> bool:
		close_calls.append(room_code)
		return true


func test_host_create_send_receive_and_membership_are_sanitized() -> void:
	var socket := FakeSocket.new()
	socket.create_result = FakeMatchResult.new(HOST_SESSION, [])
	var broker := FakeBroker.new()
	var transport := RelayedTransport.new()
	var memberships: Array = []
	var received: Array = []
	transport.membership_changed.connect(
		func(members: Array) -> void: memberships.append(members)
	)
	transport.state_received.connect(
		func(channel: StringName, sequence: int, payload: Dictionary) -> void:
			received.append([channel, sequence, payload])
	)
	transport.configure(socket, broker)

	var descriptor: Dictionary = await transport.create({})
	assert_str(descriptor["room_code"]).is_equal("MN2P42")
	assert_int(transport.status).is_equal(TransportContract.Status.CONNECTED)
	assert_int(memberships.size()).is_equal(1)
	assert_str(JSON.stringify(memberships)).not_contains(HOST_SESSION)
	assert_dict(memberships[0][0]).is_equal({
		"slot": 0,
		"role": "host",
		"local": true,
	})

	socket.received_match_presence.emit({
		"match_id": MATCH_ID,
		"joins": [{"session_id": GUEST_SESSION}],
		"leaves": [],
	})
	assert_int(memberships.size()).is_equal(2)
	assert_str(JSON.stringify(memberships[-1])).not_contains(GUEST_SESSION)
	assert_int(transport.send(&"race_state", {"altitude": 42})).is_equal(OK)
	assert_int(socket.send_calls.size()).is_equal(1)
	var sent: Dictionary = JSON.parse_string(socket.send_calls[0]["data"])
	assert_int(int(sent["sequence"])).is_equal(1)
	assert_float(float(sent["payload"]["altitude"])).is_equal(42.0)

	var inbound := TransportContract.make_envelope(
		&"race_state",
		1,
		{"altitude": 40}
	)
	socket.received_match_state.emit({
		"match_id": MATCH_ID,
		"op_code": RelayedTransport.MATCH_STATE_OP_CODE,
		"presence": {"session_id": GUEST_SESSION},
		"data": JSON.stringify(inbound),
	})
	socket.received_match_state.emit({
		"match_id": MATCH_ID,
		"op_code": RelayedTransport.MATCH_STATE_OP_CODE,
		"presence": {"session_id": GUEST_SESSION},
		"data": JSON.stringify(inbound),
	})
	assert_int(received.size()).is_equal(1)
	assert_array(received[0]).is_equal([
		&"race_state",
		1,
		{"altitude": 40.0},
	])

	transport.leave()
	assert_array(broker.close_calls).is_equal(["MN2P42"])
	assert_array(socket.leave_calls).is_equal([MATCH_ID])
	assert_int(transport.status).is_equal(TransportContract.Status.CLOSED)


func test_free_guest_joins_and_fails_closed_when_host_leaves() -> void:
	var socket := FakeSocket.new()
	socket.join_result = FakeMatchResult.new(
		GUEST_SESSION,
		[{"session_id": HOST_SESSION}]
	)
	var broker := FakeBroker.new()
	var transport := RelayedTransport.new()
	var errors: Array = []
	transport.transport_error.connect(
		func(code: StringName, message: String) -> void:
			errors.append([code, message])
	)
	transport.configure(socket, broker)

	var descriptor: Dictionary = await transport.join("mn2p42")
	assert_str(descriptor["match_id"]).is_equal(MATCH_ID)
	assert_int(transport.status).is_equal(TransportContract.Status.CONNECTED)
	socket.received_match_presence.emit({
		"match_id": MATCH_ID,
		"joins": [],
		"leaves": [{"session_id": HOST_SESSION}],
	})
	assert_int(transport.status).is_equal(TransportContract.Status.CLOSED)
	assert_int(errors.size()).is_equal(1)
	assert_str(str(errors[0][0])).is_equal("host_left")
	assert_array(broker.close_calls).is_empty()


func test_transport_rejects_economic_payload_before_relay() -> void:
	var socket := FakeSocket.new()
	socket.create_result = FakeMatchResult.new(HOST_SESSION, [])
	var transport := RelayedTransport.new()
	transport.configure(socket, FakeBroker.new())
	await transport.create({})

	assert_int(
		transport.send(
			&"race_state",
			{"result": {"transaction_id": "client-claim"}}
		)
	).is_equal(ERR_INVALID_DATA)
	assert_array(socket.send_calls).is_empty()
