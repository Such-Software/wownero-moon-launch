extends Node
## HTTP client for the Such Software backend API.
## Autoloaded — access from anywhere via `ScoreClient.xxx`.
## Works on desktop, mobile, and HTML5 (uses HTTPRequest node).

const API_BASE := "https://api.such.software/v1/moonlaunch"

# Signals for async responses
signal score_submitted(success: bool, rank: int)
signal leaderboard_received(success: bool, scores: Array)
signal rank_received(success: bool, rank: int, total: int, best_time: float)

var _submit_http: HTTPRequest
var _leaderboard_http: HTTPRequest
var _rank_http: HTTPRequest


func _ready():
	_submit_http = HTTPRequest.new()
	_submit_http.request_completed.connect(_on_submit_completed)
	add_child(_submit_http)

	_leaderboard_http = HTTPRequest.new()
	_leaderboard_http.request_completed.connect(_on_leaderboard_completed)
	add_child(_leaderboard_http)

	_rank_http = HTTPRequest.new()
	_rank_http.request_completed.connect(_on_rank_completed)
	add_child(_rank_http)


# ── Submit a score ────────────────────────────────────────────────────

func submit_score(level: int, completion_time: float, fuel_remaining: float,
		crypto_collected: int, stars: int, wave: int = 0) -> void:
	var body := {
		"device_uuid": globalvar.device_uuid,
		"nickname": globalvar.nickname,
		"level": level,
		"completion_time": snapped(completion_time, 0.01),
		"fuel_remaining": snapped(fuel_remaining, 0.1),
		"crypto_collected": crypto_collected,
		"stars": stars,
		"platform": globalvar.get_platform_string(),
	}
	if wave > 0:
		body["wave"] = wave
	var json_str := JSON.stringify(body)
	var headers := ["Content-Type: application/json"]

	# HMAC signing (if secret is configured in the build)
	var hmac_secret := _get_hmac_secret()
	if hmac_secret != "":
		var timestamp := str(int(Time.get_unix_time_from_system()))
		var signature := _sign(hmac_secret, timestamp, json_str.to_utf8_buffer())
		headers.append("X-Timestamp: " + timestamp)
		headers.append("X-Signature: " + signature)

	var err := _submit_http.request(API_BASE + "/scores",
		headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		push_warning("ScoreClient: submit request failed to start: %d" % err)
		score_submitted.emit(false, -1)


func _on_submit_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("ScoreClient: submit failed — HTTP %d, result %d" % [response_code, result])
		score_submitted.emit(false, -1)
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		score_submitted.emit(false, -1)
		return
	var data = json.get_data()
	if data is Dictionary and data.get("status") == "ok":
		score_submitted.emit(true, int(data.get("rank", -1)))
	else:
		push_warning("ScoreClient: submit error — %s" % str(data))
		score_submitted.emit(false, -1)


# ── Fetch leaderboard ────────────────────────────────────────────────

func fetch_leaderboard(level: int, limit: int = 50, board: String = "time") -> void:
	var url := "%s/scores?level=%d&limit=%d&device_uuid=%s&board=%s" % [
		API_BASE, level, limit, globalvar.device_uuid, board]
	var err := _leaderboard_http.request(url)
	if err != OK:
		push_warning("ScoreClient: leaderboard request failed to start: %d" % err)
		leaderboard_received.emit(false, [])


func _on_leaderboard_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("ScoreClient: leaderboard failed — HTTP %d" % response_code)
		leaderboard_received.emit(false, [])
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		leaderboard_received.emit(false, [])
		return
	var data = json.get_data()
	if data is Dictionary and data.has("scores"):
		leaderboard_received.emit(true, data["scores"])
	else:
		leaderboard_received.emit(false, [])


# ── Fetch player rank ────────────────────────────────────────────────

func fetch_rank(level: int, board: String = "time") -> void:
	var url := "%s/rank?level=%d&device_uuid=%s&board=%s" % [
		API_BASE, level, globalvar.device_uuid, board]
	var err := _rank_http.request(url)
	if err != OK:
		push_warning("ScoreClient: rank request failed to start: %d" % err)
		rank_received.emit(false, -1, 0, 0.0)


func _on_rank_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("ScoreClient: rank failed — HTTP %d" % response_code)
		rank_received.emit(false, -1, 0, 0.0)
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		rank_received.emit(false, -1, 0, 0.0)
		return
	var data = json.get_data()
	if data is Dictionary:
		var rank = data.get("rank")
		if rank == null:
			rank_received.emit(true, -1, 0, 0.0)
		else:
			rank_received.emit(true, int(rank),
				int(data.get("total", 0)),
				float(data.get("best_time", 0.0)))
	else:
		rank_received.emit(false, -1, 0, 0.0)


# ── HMAC helpers ──────────────────────────────────────────────────────

func _get_hmac_secret() -> String:
	return "100922e6655d098f3af9aeb75cca2bff84d25b4d99bdd7a52c23e22d7bfe0a8d"


func _sign(secret_hex: String, timestamp: String, body: PackedByteArray) -> String:
	var ctx := HMACContext.new()
	var key := secret_hex.hex_decode()
	ctx.start(HashingContext.HASH_SHA256, key)
	ctx.update(timestamp.to_utf8_buffer())
	ctx.update(body)
	var digest := ctx.finish()
	return digest.hex_encode()
