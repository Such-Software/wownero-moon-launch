extends "res://game/net/Telemetry.gd"

var request_calls := 0


func _transport_secret() -> String:
	return ""


func _start_transport_request(
		_headers: PackedStringArray, _json_str: String
	) -> Error:
	request_calls += 1
	return OK
