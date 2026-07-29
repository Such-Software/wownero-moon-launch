class_name NakamaRoomBroker
extends RefCounted
## Authenticated HTTP RPC boundary for friendly room codes.
##
## The caller supplies an already authenticated Nakama client and session.
## This class never accepts a server key and never persists or logs tokens.

const RoomTransportContract = preload("res://game/platform/transport/RoomTransport.gd")

const RPC_REGISTER := "moon_launch_room_register"
const RPC_RESOLVE := "moon_launch_room_resolve"
const RPC_CLOSE := "moon_launch_room_close"
const ROOM_CODE_PATTERN := "^[A-HJ-NP-Z2-9]{6}$"
const MATCH_ID_PATTERN := "^[A-Za-z0-9._:-]{8,256}$"
const DESCRIPTOR_KEYS := [
	"expires_at",
	"match_id",
	"max_players",
	"protocol_version",
	"room_code",
]

var _client: Variant
var _session: Variant


func configure(client: Variant, session: Variant) -> void:
	_client = client
	_session = session


func is_configured() -> bool:
	return (
		_client != null
		and _session != null
		and _client.has_method("rpc_async")
	)


func register_room(match_id: String) -> Dictionary:
	return await _call_rpc(
		RPC_REGISTER,
		{
			"match_id": match_id,
			"protocol_version": RoomTransportContract.PROTOCOL_VERSION,
			"max_players": 2,
		}
	)


func resolve_room(room_code: String) -> Dictionary:
	return await _call_rpc(
		RPC_RESOLVE,
		{"room_code": room_code.strip_edges().to_upper()}
	)


func close_room(room_code: String) -> bool:
	var response := await _call_rpc(
		RPC_CLOSE,
		{"room_code": room_code.strip_edges().to_upper()}
	)
	return response.get("closed", false) == true


func _call_rpc(rpc_id: String, payload: Dictionary) -> Dictionary:
	if not is_configured():
		return {}
	var result: Variant = await _client.rpc_async(
		_session,
		rpc_id,
		JSON.stringify(payload)
	)
	if result == null or not result.has_method("is_exception"):
		return {}
	if result.is_exception():
		return {}
	var payload_text: Variant = result.get("payload")
	if not payload_text is String or payload_text.length() > 2048:
		return {}
	var decoded: Variant = JSON.parse_string(payload_text)
	if not decoded is Dictionary:
		return {}
	return decoded


static func validate_descriptor(value: Dictionary) -> StringName:
	if value.size() != DESCRIPTOR_KEYS.size():
		return &"shape"
	for key in DESCRIPTOR_KEYS:
		if not value.has(key):
			return &"shape"
	if not value["room_code"] is String or not _matches(
		ROOM_CODE_PATTERN,
		value["room_code"]
	):
		return &"room_code"
	if not value["match_id"] is String or not _matches(
		MATCH_ID_PATTERN,
		value["match_id"]
	):
		return &"match_id"
	if (
		not _is_json_integer(value["protocol_version"])
		or int(value["protocol_version"])
			!= RoomTransportContract.PROTOCOL_VERSION
	):
		return &"protocol_version"
	if not _is_json_integer(value["max_players"]) or int(value["max_players"]) != 2:
		return &"max_players"
	if not value["expires_at"] is String:
		return &"expires_at"
	var parsed := Time.get_unix_time_from_datetime_string(value["expires_at"])
	if parsed <= 0:
		return &"expires_at"
	return &""


static func _matches(pattern_text: String, value: String) -> bool:
	var pattern := RegEx.new()
	return pattern.compile(pattern_text) == OK and pattern.search(value) != null


static func _is_json_integer(value: Variant) -> bool:
	return (
		value is int
		or (
			value is float
			and is_finite(value)
			and value == floor(value)
		)
	)
