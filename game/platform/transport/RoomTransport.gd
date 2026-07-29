class_name RoomTransport
extends RefCounted
## App-local transport boundary for online rooms and future nearby research.
##
## Implementations move bounded, ordered messages. They never grant durable
## game state, carry raw identity or purchase data, or redefine game rules.

signal status_changed(status: int)
signal membership_changed(members: Array)
signal state_received(channel: StringName, sequence: int, payload: Dictionary)
signal transport_error(code: StringName, message: String)

enum Status {
	IDLE,
	CREATING,
	JOINING,
	CONNECTED,
	RECONNECTING,
	LEAVING,
	CLOSED,
	FAILED,
}

const PROTOCOL_VERSION := 1
const MAX_PAYLOAD_BYTES := 4096
const MAX_CHANNEL_LENGTH := 32

var status: Status = Status.IDLE


func create(_options: Dictionary) -> Dictionary:
	return _unavailable("create")


func join(_code_or_descriptor: Variant) -> Dictionary:
	return _unavailable("join")


func send(_channel: StringName, _ordered_payload: Dictionary) -> Error:
	_unavailable("send")
	return ERR_UNAVAILABLE


func leave() -> void:
	_set_status(Status.CLOSED)


func dispose() -> void:
	_set_status(Status.CLOSED)


func _set_status(next_status: Status) -> void:
	if status == next_status:
		return
	status = next_status
	status_changed.emit(status)


func _unavailable(operation: String) -> Dictionary:
	_set_status(Status.FAILED)
	transport_error.emit(&"not_implemented", "%s is unavailable" % operation)
	return {}


static func make_envelope(channel: StringName, sequence: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"channel": str(channel),
		"sequence": sequence,
		"payload": payload.duplicate(true),
	}


static func validate_envelope(envelope: Dictionary) -> StringName:
	if int(envelope.get("protocol_version", -1)) != PROTOCOL_VERSION:
		return &"protocol_version"
	var channel := str(envelope.get("channel", ""))
	if channel.is_empty() or channel.length() > MAX_CHANNEL_LENGTH:
		return &"channel"
	if int(envelope.get("sequence", 0)) < 1:
		return &"sequence"
	if not envelope.get("payload") is Dictionary:
		return &"payload"
	var encoded := JSON.stringify(envelope).to_utf8_buffer()
	if encoded.size() > MAX_PAYLOAD_BYTES:
		return &"oversized"
	return &""
