extends Node
## Cloud save client — backs up savegame.json to api.such.software.
## Autoloaded — access from anywhere via `CloudSave.xxx`.
##
## PUT /v1/moonlaunch/save — upload save (HMAC-signed)
## GET /v1/moonlaunch/save — download save (by device_uuid)

const API_BASE := "https://api.such.software/v1/moonlaunch"

signal save_uploaded(success: bool)
signal save_downloaded(success: bool, save_data: Dictionary)

var _upload_http: HTTPRequest
var _download_http: HTTPRequest


func _ready():
	_upload_http = HTTPRequest.new()
	_upload_http.request_completed.connect(_on_upload_completed)
	add_child(_upload_http)

	_download_http = HTTPRequest.new()
	_download_http.request_completed.connect(_on_download_completed)
	add_child(_download_http)


# ── Upload ────────────────────────────────────────────────────────────

func upload_save() -> void:
	## Upload current savegame to the cloud. Call after level completion,
	## upgrade purchase, or skin unlock.
	var save_data := globalvar.get_save_data()
	var body := {
		"device_uuid": globalvar.device_uuid,
		"nickname": globalvar.nickname,
		"save_data": save_data,
		"platform": globalvar.get_platform_string(),
	}
	var json_str := JSON.stringify(body)
	var headers := ["Content-Type: application/json"]

	# HMAC signing
	var hmac_secret := ScoreClient._get_hmac_secret()
	if hmac_secret != "":
		var timestamp := str(int(Time.get_unix_time_from_system()))
		var signature := ScoreClient._sign(hmac_secret, timestamp, json_str.to_utf8_buffer())
		headers.append("X-Timestamp: " + timestamp)
		headers.append("X-Signature: " + signature)

	var err := _upload_http.request(API_BASE + "/save",
		headers, HTTPClient.METHOD_PUT, json_str)
	if err != OK:
		push_warning("CloudSave: upload request failed to start: %d" % err)
		save_uploaded.emit(false)


func _on_upload_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("CloudSave: upload failed — HTTP %d, result %d" % [response_code, result])
		save_uploaded.emit(false)
		return
	save_uploaded.emit(true)


# ── Download ──────────────────────────────────────────────────────────

func download_save() -> void:
	## Download cloud save for the current device_uuid.
	var url := "%s/save?device_uuid=%s" % [API_BASE, globalvar.device_uuid]
	var err := _download_http.request(url)
	if err != OK:
		push_warning("CloudSave: download request failed to start: %d" % err)
		save_downloaded.emit(false, {})


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		if response_code == 404:
			# No cloud save exists — that's fine, not an error
			save_downloaded.emit(true, {})
		else:
			push_warning("CloudSave: download failed — HTTP %d" % response_code)
			save_downloaded.emit(false, {})
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		save_downloaded.emit(false, {})
		return
	var data = json.get_data()
	if data is Dictionary and data.get("status") == "ok" and data.has("save_data"):
		save_downloaded.emit(true, data["save_data"])
	else:
		save_downloaded.emit(false, {})
