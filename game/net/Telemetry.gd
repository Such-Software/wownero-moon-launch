extends Node
## Telemetry — backend-driven analytics + error reporting.
## Autoloaded singleton.
##
## Strategy: instead of Firebase/Crashlytics (Godot 4 plugin landscape is
## sparse, especially on iOS), events are POSTed in batches to our own
## backend at https://api.such.software/v1/events. The backend stores them
## in the events table and ships a daily Resend digest email summarizing
## activity across all apps (moonlaunch + bauhaus + suchoice).
##
## Native crash reports come from Apple App Store Connect + Google Play
## Console (free, automatic). Caught logical errors are forwarded via
## `record_error()` and logged as event_name='error'.
##
## All `log_event` / `record_error` calls are safe on every platform.
## Events are buffered locally and flushed every FLUSH_INTERVAL or on
## application quit / focus-out — fire-and-forget; telemetry must NEVER
## affect gameplay.

const API_URL := "https://api.such.software/v1/events"
const APP_NAME := "moonlaunch"
const FLUSH_INTERVAL := 30.0     # seconds between automatic flushes
const MAX_BUFFER := 50           # batch size cap (matches server MAX_BATCH_SIZE)
const MAX_DROPPED_BEFORE_GIVEUP := 200  # safety cap if backend is down

# Standard event names — keep these stable so analytics dashboards don't break.
const EVENT_APP_OPEN          := "app_open"
const EVENT_LEVEL_START       := "level_start"
const EVENT_LEVEL_COMPLETE    := "level_complete"
const EVENT_LEVEL_DEATH       := "level_death"
const EVENT_IAP_INITIATED     := "iap_initiated"
const EVENT_IAP_COMPLETED     := "iap_completed"
const EVENT_REWARDED_WATCHED  := "rewarded_watched"
const EVENT_SHARE_PRESSED     := "share_pressed"
const EVENT_RATE_PROMPT_SHOWN := "rate_prompt_shown"
const EVENT_ERROR             := "error"

var _buffer: Array = []          # pending events (each: {name, params})
var _http: HTTPRequest = null
var _flush_timer: Timer = null
var _initialized: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_http_completed)
	add_child(_http)

	_flush_timer = Timer.new()
	_flush_timer.wait_time = FLUSH_INTERVAL
	_flush_timer.one_shot = false
	_flush_timer.autostart = true
	_flush_timer.timeout.connect(_flush)
	add_child(_flush_timer)

	_initialized = true
	log_event(EVENT_APP_OPEN, {})


func _notification(what: int) -> void:
	# Flush on app pause / quit so we don't lose the last few events.
	match what:
		NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_CLOSE_REQUEST, \
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_flush()


## Log a custom analytics event. Safe on any platform.
func log_event(name: String, params: Dictionary = {}) -> void:
	if not _initialized:
		return
	if _buffer.size() >= MAX_DROPPED_BEFORE_GIVEUP:
		# Backend is presumably down; stop adding to avoid unbounded growth.
		return
	_buffer.append({"name": name, "params": params.duplicate(true)})
	if _buffer.size() >= MAX_BUFFER:
		_flush()


## Set a sticky user property. Currently logged as a special event (no-op
## in DB until we extend the schema; kept for API parity with Firebase).
func set_user_property(key: String, value: String) -> void:
	log_event("user_property", {"key": key, "value": value})


## Record a non-fatal logical error. Surfaces in the daily digest.
func record_error(msg: String, fatal: bool = false) -> void:
	log_event(EVENT_ERROR, {"msg": msg, "fatal": fatal})
	if fatal:
		# Force a flush so a crash-loop won't lose the report.
		_flush()


# --- Internal ---

func _flush() -> void:
	if _buffer.is_empty():
		return
	if _http == null:
		return
	# Drain the buffer into the request body (cap at MAX_BUFFER per request).
	var batch: Array = _buffer.slice(0, MAX_BUFFER)
	_buffer = _buffer.slice(MAX_BUFFER)

	var body := {
		"app": APP_NAME,
		"device_uuid": globalvar.device_uuid,
		"nickname": globalvar.nickname,
		"platform": globalvar.get_platform_string(),
		"events": batch,
	}
	var json_str := JSON.stringify(body)
	var headers := PackedStringArray(["Content-Type: application/json"])

	# HMAC sign — reuse ScoreClient's secret reconstruction.
	var secret: String = ScoreClient._get_hmac_secret()
	if secret != "":
		var ts := str(int(Time.get_unix_time_from_system()))
		var sig := ScoreClient._sign(secret, ts, json_str.to_utf8_buffer())
		headers.append("X-Timestamp: " + ts)
		headers.append("X-Signature: " + sig)

	var err := _http.request(API_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		# Couldn't even start the request — re-enqueue and try next flush.
		_buffer = batch + _buffer


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		# Don't re-enqueue on persistent failure — telemetry is best-effort.
		# (Re-enqueueing on every failure would amplify outage cost.)
		push_warning("Telemetry: flush failed — HTTP %d, result %d" % [response_code, result])
