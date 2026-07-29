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
const ENVELOPE_KEYS := [
	"protocol_version",
	"channel",
	"sequence",
	"payload",
]
const FORBIDDEN_PAYLOAD_KEYS := {
	"apple": true,
	"email": true,
	"entitlement": true,
	"google": true,
	"id_token": true,
	"jwt": true,
	"nostr": true,
	"purchase": true,
	"receipt": true,
	"session_id": true,
	"siwe": true,
	"subject_id": true,
	"transaction_id": true,
	"user_id": true,
}

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
	if envelope.size() != ENVELOPE_KEYS.size():
		return &"shape"
	for key in ENVELOPE_KEYS:
		if not envelope.has(key):
			return &"shape"
	if not _is_json_integer(envelope["protocol_version"]):
		return &"protocol_version"
	if int(envelope["protocol_version"]) != PROTOCOL_VERSION:
		return &"protocol_version"
	if not envelope["channel"] is String:
		return &"channel"
	var channel: String = envelope["channel"]
	if (
		channel.is_empty()
		or channel.length() > MAX_CHANNEL_LENGTH
		or not _channel_pattern().search(channel)
	):
		return &"channel"
	if not _is_json_integer(envelope["sequence"]) or int(envelope["sequence"]) < 1:
		return &"sequence"
	if not envelope["payload"] is Dictionary:
		return &"payload"
	if _contains_forbidden_payload(envelope["payload"]):
		return &"forbidden_payload"
	var encoded := JSON.stringify(envelope).to_utf8_buffer()
	if encoded.size() > MAX_PAYLOAD_BYTES:
		return &"oversized"
	return &""


static func _channel_pattern() -> RegEx:
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]{0,31}$")
	return pattern


static func _contains_forbidden_payload(value: Variant, depth := 0) -> bool:
	if depth > 8:
		return true
	if value is Dictionary:
		for key in value:
			var normalized := str(key).to_snake_case().to_lower()
			if FORBIDDEN_PAYLOAD_KEYS.has(normalized):
				return true
			if _contains_forbidden_payload(value[key], depth + 1):
				return true
	elif value is Array:
		for item in value:
			if _contains_forbidden_payload(item, depth + 1):
				return true
	return false


static func _is_json_integer(value: Variant) -> bool:
	return (
		value is int
		or (
			value is float
			and is_finite(value)
			and value == floor(value)
		)
	)
