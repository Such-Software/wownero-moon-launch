extends Node
## Firebase Analytics + Crashlytics adapter (GA4 funnel sink).
## Autoloaded singleton. Ported from Bloomword's analytics_manager.gd so fixes flow
## between both games while the owned native bridge is shaken out in testing.
##
## Dual-sink design (v1.1.0 plan): THIS is the Firebase/GA4 sink — standard lifecycle
## + funnel + retention + activation events, with high-cardinality numbers BUCKETED
## (GA4 rejects high-cardinality numeric params). The raw, full-resolution
## death-forensics rows still go to our own /v1/events backend via Telemetry.gd.
##
## Safe before the native plugins exist: it no-ops in editor/harness/debug contexts
## and forwards to the MoonLaunchFirebase native singleton only when present. So
## adding this autoload changes NOTHING in the current mobile builds until the native
## bridge is wired + tested. Events stay aggregate: no PII, balances, or seeds.

const MAX_NAME := 40
const MAX_STRING := 96
const APP_ID := "moon_launch"
const CONFIG_PATH := "user://analytics.cfg"
const FIREBASE_SINGLETON := "BloomwordFirebase"  # Generic shared bridge; provider config selects Moon Launch. The emitted platform ID remains canonical.

var _analytics: Object = null
var _crash: Object = null
var _enabled := false
var _debug_log := false
var _session_id := ""
var _device_id := ""
var _is_first_session := false
var _cfg := ConfigFile.new()


func _ready() -> void:
	_enabled = _compute_enabled()
	_debug_log = OS.is_debug_build() and OS.get_environment("SML_ANALYTICS_DEBUG") != ""
	_session_id = "%x%x" % [Time.get_ticks_usec(), randi()]
	_load_install_state()
	if Engine.has_singleton(FIREBASE_SINGLETON):
		_analytics = Engine.get_singleton(FIREBASE_SINGLETON)
		_crash = _analytics
	if not _enabled:
		return
	set_user_property("app_id", APP_ID)
	set_user_property("device_id", _device_id_live())
	set_user_property("app_version", _app_version())
	set_user_property("build_number", _build_number())
	set_user_property("platform", _platform())
	if _is_first_session:
		event("app_first_open_our", {
			"device_lang": TranslationServer.get_locale(),
			"device_model": OS.get_model_name(),
			"os_version": OS.get_version(),
		})
	elif not bool(_cfg.get_value("install", "second_session_sent", false)):
		var first_open := int(_cfg.get_value("install", "first_open_unix", 0))
		if first_open > 0:
			var hours := int((Time.get_unix_time_from_system() - first_open) / 3600.0)
			if hours >= 24:
				event("second_session_start", {"hours_since_first_open": hours})
				_cfg.set_value("install", "second_session_sent", true)
				_cfg.save(CONFIG_PATH)
	event("app_start", {
		"platform": _platform(),
		"debug": OS.is_debug_build(),
		"analytics_sdk": _analytics != null,
	})


func enabled() -> bool:
	return _enabled


## Core: log a GA4 event. Required params (§1 of APP_ANALYTICS.md) are auto-injected.
func event(name: String, params: Dictionary = {}) -> void:
	if not _enabled:
		return
	# A "Watch a demo" run (WP-B5) replays the real level but must emit nothing.
	# Gating event() covers every specialized emitter (they all route through here).
	if globalvar.demo_mode:
		return
	var safe_name := _safe_name(name)
	var safe_params := _safe_params(params)
	var required := _required_params()
	for k in required:
		safe_params[k] = required[k]
	if _debug_log:
		print("[Analytics] %s %s" % [safe_name, safe_params])
	if _analytics != null and _analytics.has_method("log_event"):
		_analytics.call("log_event", safe_name, safe_params)


func screen(name: String) -> void:
	event("screen_view", {"screen_name": name, "screen_class": name})


func set_user_property(name: String, value: Variant) -> void:
	if not _enabled or _analytics == null:
		return
	# GA4 user-property values are capped at 36 chars (vs 100 for event params) --
	# trim so a long id isn't silently dropped.
	if _analytics.has_method("set_user_property"):
		_analytics.call("set_user_property", _safe_name(name).substr(0, 24), _trim(str(_safe_value(value)), 36))


# --- Such Moon Launch app-specific events (APP_ANALYTICS.md §3.3 + v1.1.0 forensics) ---

## Player taps launch / a level attempt begins.
func launch_attempt(level: int, fuel_loadout: String = "") -> void:
	event("launch_attempt", {"level": level, "fuel_loadout": fuel_loadout})


## Run finished successfully (the win path). outcome kept for parity with the spec.
func launch_complete(level: int, time_ms: int, distance_reached: int, outcome: String = "win") -> void:
	event("launch_complete", {
		"level": level,
		"time_bucket": _bucket_seconds(time_ms / 1000.0),
		"distance_bucket": _bucket(distance_reached, 250),
		"outcome": outcome,
	})


## Death forensics — BUCKETED for GA4 (the raw full-resolution row goes to Telemetry).
## cause_type: crash | hazard | out_of_fuel | timeout. hazard_name: Martian/BlackHole/... or "".
func level_death(level: int, cause_type: String, hazard_name: String, pct_through: float,
		dist_to_target: float, speed: float, fuel_frac: float,
		time_into_level: float, attempt_number: int) -> void:
	event("level_death", {
		"level": level,
		"cause_type": cause_type,
		"hazard_name": hazard_name,
		"pct_band": int(round(clampf(pct_through, 0.0, 1.0) * 10.0)),   # 0..10 (10% bands)
		"dist_bucket": _bucket(int(dist_to_target), 100),
		"speed_bucket": _bucket(int(speed), 50),
		"fuel_band": int(round(clampf(fuel_frac, 0.0, 1.0) * 10.0)),    # 0..10
		"time_bucket": _bucket_seconds(time_into_level),
		"attempt": mini(attempt_number, 20),                            # cap cardinality
	})


## In-game (non-IAP) upgrade bought with moonrocks.
func upgrade_purchased(upgrade_id: String, cost: int) -> void:
	event("upgrade_purchased", {"upgrade_id": upgrade_id, "cost_bucket": _bucket(cost, 500)})


func personal_best(metric: String, value: float) -> void:
	event("personal_best", {"metric": metric, "value_bucket": _bucket(int(value), 100)})


func share(method: String, content_type: String, item_id: String = "results_card") -> void:
	event("share", {"method": method, "content_type": content_type, "item_id": item_id})


## First successful launch = activation. One-time, deduped via the install config.
func activation(source: String) -> void:
	if not _enabled:
		return
	if globalvar.demo_mode:  # a demo must not consume the one-time activation
		return
	if bool(_cfg.get_value("install", "activation_sent", false)):
		return
	event("activation_moment", {"event_source": source})
	_cfg.set_value("install", "activation_sent", true)
	_cfg.save(CONFIG_PATH)


# --- Crashlytics ---

func crash_log(message: String, params: Dictionary = {}) -> void:
	if not _enabled or _crash == null:
		return
	var safe_params := _safe_params(params)
	if _debug_log:
		print("[CrashLog] %s %s" % [message, safe_params])
	if _crash.has_method("log"):
		_crash.call("log", _trim(message, 180))
	for k in safe_params:
		if _crash.has_method("set_custom_key"):
			_crash.call("set_custom_key", str(k), str(safe_params[k]))


func nonfatal(area: String, message: String, params: Dictionary = {}) -> void:
	var safe_params := _safe_params(params)
	safe_params["area"] = _safe_name(area)
	event("nonfatal_error", safe_params)
	crash_log("%s: %s" % [area, message], safe_params)
	if _crash and _crash.has_method("record_exception"):
		_crash.call("record_exception", _safe_name(area), message)


# --- Internal ---

func _compute_enabled() -> bool:
	# Never emit from the bot harness, video capture, or RL training runs
	# (--disable-render-loop marks a godot_rl_agents training env binary).
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--sim" in args or "--autopilot" in args or "--capture" in args or "--disable-render-loop" in args:
		return false
	# Keep GA4 clean: no editor/debug events unless explicitly opted in.
	return not OS.is_debug_build() or OS.get_environment("SML_ANALYTICS_DEBUG") != ""


func _load_install_state() -> void:
	_cfg.load(CONFIG_PATH)
	# Reuse the game's existing anonymous device UUID so GA4 joins with our backend.
	var gv_uuid := ""
	if has_node("/root/globalvar"):
		gv_uuid = str(get_node("/root/globalvar").get("device_uuid"))
	_device_id = gv_uuid if gv_uuid != "" else String(_cfg.get_value("install", "device_id", ""))
	var fresh := not _cfg.has_section_key("install", "first_open_unix")
	if _device_id == "":
		_device_id = "sml-%x-%x-%x" % [Time.get_ticks_usec(), randi(), randi()]
	if fresh:
		_cfg.set_value("install", "device_id", _device_id)
		_cfg.set_value("install", "first_open_unix", int(Time.get_unix_time_from_system()))
		_cfg.set_value("install", "second_session_sent", false)
		_cfg.set_value("install", "activation_sent", false)
		_is_first_session = true
		_cfg.save(CONFIG_PATH)


func _required_params() -> Dictionary:
	return {
		"app_version": _app_version(),
		"build_number": _build_number(),
		"device_id": _device_id_live(),
		"session_id": _session_id,
		"is_first_session": _is_first_session,
	}


## device_uuid is loaded from the save in globalvar; prefer the live value so the GA4
## device_id always matches our backend telemetry even if autoload order shifts.
func _device_id_live() -> String:
	if has_node("/root/globalvar"):
		var u := str(get_node("/root/globalvar").get("device_uuid"))
		if u != "":
			return u
	return _device_id


func _app_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "1.0.0"))


func _build_number() -> String:
	var env := OS.get_environment("SML_BUILD_NUMBER")
	if env != "":
		return env
	return String(ProjectSettings.get_setting("application/config/build_number", "dev"))


func _safe_params(params: Dictionary) -> Dictionary:
	var out := {}
	for raw_key in params.keys():
		var key := _safe_name(str(raw_key))
		if key == "":
			continue
		out[key] = _safe_value(params[raw_key])
	return out


func _safe_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return value
		_:
			return _trim(str(value), MAX_STRING)


func _safe_name(value: String) -> String:
	var out := ""
	for i in value.length():
		var ch := value.substr(i, 1)
		var code := ch.unicode_at(0)
		var ok := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or ch == "_"
		out += ch if ok else "_"
	out = out.strip_edges().substr(0, MAX_NAME)
	if out == "":
		return "event"
	var first := out.substr(0, 1).unicode_at(0)
	if first >= 48 and first <= 57:
		out = "e_" + out
	return out.substr(0, MAX_NAME)


func _trim(value: String, max_len: int) -> String:
	return value.substr(0, max_len)


func _bucket(value: int, size: int) -> int:
	if size <= 0:
		return value
	return int(floor(float(value) / size)) * size


func _bucket_seconds(seconds: float) -> int:
	return int(floor(maxf(seconds, 0.0) / 15.0)) * 15


func _platform() -> String:
	match OS.get_name():
		"iOS": return "ios"
		"Android": return "android"
		"Web": return "web"
		"macOS": return "macos"
		"Windows": return "windows"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD": return "linux"
		_: return "other"
