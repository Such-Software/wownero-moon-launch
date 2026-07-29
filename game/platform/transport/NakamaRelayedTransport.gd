class_name NakamaRelayedTransport
extends RoomTransport
## Two-player client-authoritative friendly room over Nakama relay.
##
## Match/session identifiers stay internal. Membership events expose only
## neutral host/guest slots. Relayed state cannot grant ranked, economic, or
## durable outcomes.

const BrokerContract = preload(
	"res://game/platform/transport/NakamaRoomBroker.gd"
)

const MATCH_STATE_OP_CODE := 1

var _socket: Variant
var _broker: Variant
var _match_id := ""
var _room_code := ""
var _is_host := false
var _host_session_id := ""
var _local_session_id := ""
var _member_sessions: Array[String] = []
var _received_sequences := {}
var _send_sequence := 0
var _signals_connected := false


func configure(socket: Variant, broker: Variant) -> void:
	dispose()
	_socket = socket
	_broker = broker
	_connect_socket_signals()
	status = Status.IDLE


func create(_options: Dictionary) -> Dictionary:
	if not _ready_for_room():
		return _fail(&"not_configured", "Online rooms are not configured")
	_set_status(Status.CREATING)
	var match_result: Variant = await _socket.create_match_async()
	if _is_failed_result(match_result) or _read(match_result, "authoritative", true):
		return _fail(&"relay_create_failed", "Could not create a friendly room")
	var match_id := str(_read(match_result, "match_id", ""))
	if not _valid_match_id(match_id):
		return _fail(&"relay_create_failed", "Could not create a friendly room")
	var descriptor: Dictionary = await _broker.register_room(match_id)
	if not BrokerContract.validate_descriptor(descriptor).is_empty():
		_socket.leave_match_async(match_id)
		return _fail(&"room_register_failed", "Could not register a room code")
	_match_id = match_id
	_room_code = descriptor["room_code"]
	_is_host = true
	if not _adopt_match(match_result, true):
		_socket.leave_match_async(match_id)
		return _fail(&"membership_invalid", "Room membership is invalid")
	_set_status(Status.CONNECTED)
	return descriptor.duplicate(true)


func join(code_or_descriptor: Variant) -> Dictionary:
	if not _ready_for_room():
		return _fail(&"not_configured", "Online rooms are not configured")
	_set_status(Status.JOINING)
	var descriptor: Dictionary
	if code_or_descriptor is String:
		var room_code: String = str(code_or_descriptor).strip_edges().to_upper()
		descriptor = await _broker.resolve_room(room_code)
	elif code_or_descriptor is Dictionary:
		descriptor = code_or_descriptor.duplicate(true)
	else:
		return _fail(&"room_code_invalid", "Room code is invalid")
	if not BrokerContract.validate_descriptor(descriptor).is_empty():
		return _fail(&"room_unavailable", "Room code is expired or unavailable")
	var match_result: Variant = await _socket.join_match_async(descriptor["match_id"])
	if (
		_is_failed_result(match_result)
		or _read(match_result, "authoritative", true)
		or int(_read(match_result, "size", 0)) > 2
	):
		return _fail(&"relay_join_failed", "Could not join the friendly room")
	_match_id = descriptor["match_id"]
	_room_code = descriptor["room_code"]
	_is_host = false
	if not _adopt_match(match_result, false):
		_socket.leave_match_async(_match_id)
		return _fail(&"membership_invalid", "Room membership is invalid")
	_set_status(Status.CONNECTED)
	return descriptor.duplicate(true)


func send(channel: StringName, ordered_payload: Dictionary) -> Error:
	if status != Status.CONNECTED or _match_id.is_empty():
		transport_error.emit(&"not_connected", "Friendly room is not connected")
		return ERR_UNAVAILABLE
	var next_sequence := _send_sequence + 1
	var envelope := make_envelope(channel, next_sequence, ordered_payload)
	var invalid := validate_envelope(envelope)
	if not invalid.is_empty():
		transport_error.emit(invalid, "Friendly room message was rejected")
		return ERR_INVALID_DATA
	if not _socket.has_method("send_match_state_async"):
		transport_error.emit(&"relay_unavailable", "Friendly room relay is unavailable")
		return ERR_UNAVAILABLE
	_socket.send_match_state_async(
		_match_id,
		MATCH_STATE_OP_CODE,
		JSON.stringify(envelope)
	)
	_send_sequence = next_sequence
	return OK


func leave() -> void:
	if status in [Status.CLOSED, Status.IDLE]:
		_set_status(Status.CLOSED)
		return
	_set_status(Status.LEAVING)
	if _is_host and not _room_code.is_empty() and _broker != null:
		_broker.close_room(_room_code)
	if not _match_id.is_empty() and _socket != null:
		if _socket.has_method("leave_match_async"):
			_socket.leave_match_async(_match_id)
	_clear_room()
	_set_status(Status.CLOSED)


func reconnect() -> Dictionary:
	if _match_id.is_empty() or _socket == null:
		return _fail(&"reconnect_unavailable", "Friendly room cannot reconnect")
	_set_status(Status.RECONNECTING)
	var match_result: Variant = await _socket.join_match_async(_match_id)
	if _is_failed_result(match_result) or int(_read(match_result, "size", 0)) > 2:
		return _fail(&"reconnect_failed", "Friendly room could not reconnect")
	if not _adopt_match(match_result, _is_host):
		return _fail(&"membership_invalid", "Room membership is invalid")
	_set_status(Status.CONNECTED)
	return {
		"room_code": _room_code,
		"match_id": _match_id,
		"protocol_version": PROTOCOL_VERSION,
		"max_players": 2,
	}


func dispose() -> void:
	if _signals_connected and _socket != null and is_instance_valid(_socket):
		for binding in _socket_signal_bindings():
			var signal_name: StringName = binding[0]
			var callback: Callable = binding[1]
			if _socket.has_signal(signal_name) and _socket.is_connected(
				signal_name,
				callback
			):
				_socket.disconnect(signal_name, callback)
	_signals_connected = false
	_clear_room()
	_socket = null
	_broker = null
	_set_status(Status.CLOSED)


func _ready_for_room() -> bool:
	return (
		_socket != null
		and _broker != null
		and _broker.has_method("register_room")
		and _broker.has_method("resolve_room")
		and _socket.has_method("create_match_async")
		and _socket.has_method("join_match_async")
	)


func _adopt_match(match_result: Variant, hosting: bool) -> bool:
	var self_presence: Variant = _read(match_result, "self_user", null)
	_local_session_id = str(_read(self_presence, "session_id", ""))
	if _local_session_id.is_empty():
		return false
	_member_sessions.clear()
	var presences: Variant = _read(match_result, "presences", [])
	if not presences is Array:
		return false
	if hosting:
		_host_session_id = _local_session_id
		_member_sessions.append(_local_session_id)
	for presence in presences:
		var session_id := str(_read(presence, "session_id", ""))
		if session_id.is_empty() or session_id in _member_sessions:
			continue
		_member_sessions.append(session_id)
	if not hosting:
		if _member_sessions.is_empty():
			return false
		_host_session_id = _member_sessions[0]
		if _local_session_id not in _member_sessions:
			_member_sessions.append(_local_session_id)
	if _member_sessions.size() > 2:
		return false
	_received_sequences.clear()
	_send_sequence = 0
	_emit_safe_membership()
	return true


func _on_match_state(match_state: Variant) -> void:
	if (
		status != Status.CONNECTED
		or str(_read(match_state, "match_id", "")) != _match_id
		or int(_read(match_state, "op_code", -1)) != MATCH_STATE_OP_CODE
	):
		return
	var presence: Variant = _read(match_state, "presence", null)
	var sender_session := str(_read(presence, "session_id", ""))
	if sender_session.is_empty() or sender_session not in _member_sessions:
		return
	var data: Variant = _read(match_state, "data", "")
	if not data is String or data.length() > MAX_PAYLOAD_BYTES:
		return
	var envelope: Variant = JSON.parse_string(data)
	if not envelope is Dictionary:
		return
	var invalid := validate_envelope(envelope)
	if not invalid.is_empty():
		transport_error.emit(invalid, "Invalid friendly room message was dropped")
		return
	var sequence := int(envelope["sequence"])
	var prior := int(_received_sequences.get(sender_session, 0))
	if sequence <= prior:
		transport_error.emit(&"replayed", "Repeated friendly room message was dropped")
		return
	_received_sequences[sender_session] = sequence
	state_received.emit(
		StringName(envelope["channel"]),
		sequence,
		envelope["payload"].duplicate(true)
	)


func _on_match_presence(event: Variant) -> void:
	if str(_read(event, "match_id", "")) != _match_id:
		return
	var leaves: Variant = _read(event, "leaves", [])
	if leaves is Array:
		for presence in leaves:
			var session_id := str(_read(presence, "session_id", ""))
			if session_id == _host_session_id and not _is_host:
				transport_error.emit(&"host_left", "The room host left")
				leave()
				return
			_member_sessions.erase(session_id)
	var joins: Variant = _read(event, "joins", [])
	if joins is Array:
		for presence in joins:
			var session_id := str(_read(presence, "session_id", ""))
			if session_id.is_empty() or session_id in _member_sessions:
				continue
			if _member_sessions.size() >= 2:
				_fail(&"capacity_exceeded", "Room capacity was exceeded")
				leave()
				return
			_member_sessions.append(session_id)
	_emit_safe_membership()


func _on_socket_closed() -> void:
	if status == Status.CONNECTED:
		_set_status(Status.RECONNECTING)
		transport_error.emit(&"relay_closed", "Friendly room relay disconnected")


func _on_connection_error(_error: Variant) -> void:
	if status in [Status.CREATING, Status.JOINING, Status.CONNECTED]:
		_set_status(Status.RECONNECTING)
		transport_error.emit(&"relay_error", "Friendly room relay is unavailable")


func _on_received_error(_error: Variant) -> void:
	transport_error.emit(&"relay_error", "Friendly room relay rejected an operation")


func _emit_safe_membership() -> void:
	var safe_members: Array = []
	for index in range(_member_sessions.size()):
		var session_id := _member_sessions[index]
		safe_members.append({
			"slot": index,
			"role": "host" if session_id == _host_session_id else "guest",
			"local": session_id == _local_session_id,
		})
	membership_changed.emit(safe_members)


func _connect_socket_signals() -> void:
	if _socket == null:
		return
	for binding in _socket_signal_bindings():
		var signal_name: StringName = binding[0]
		var callback: Callable = binding[1]
		if _socket.has_signal(signal_name) and not _socket.is_connected(
			signal_name,
			callback
		):
			_socket.connect(signal_name, callback)
	_signals_connected = true


func _socket_signal_bindings() -> Array:
	return [
		[&"closed", _on_socket_closed],
		[&"connection_error", _on_connection_error],
		[&"received_error", _on_received_error],
		[&"received_match_state", _on_match_state],
		[&"received_match_presence", _on_match_presence],
	]


func _fail(code: StringName, message: String) -> Dictionary:
	_set_status(Status.FAILED)
	transport_error.emit(code, message)
	return {}


func _clear_room() -> void:
	_match_id = ""
	_room_code = ""
	_is_host = false
	_host_session_id = ""
	_local_session_id = ""
	_member_sessions.clear()
	_received_sequences.clear()
	_send_sequence = 0


static func _read(value: Variant, key: String, fallback: Variant) -> Variant:
	if value is Dictionary:
		return value.get(key, fallback)
	if value is Object:
		var result: Variant = value.get(key)
		return fallback if result == null else result
	return fallback


static func _is_failed_result(value: Variant) -> bool:
	return (
		value == null
		or (
			value is Object
			and
			value.has_method("is_exception")
			and value.is_exception()
		)
	)


static func _valid_match_id(value: String) -> bool:
	var pattern := RegEx.new()
	return (
		pattern.compile(BrokerContract.MATCH_ID_PATTERN) == OK
		and pattern.search(value) != null
	)
