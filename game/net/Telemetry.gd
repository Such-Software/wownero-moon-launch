extends Node
## Telemetry — cross-platform analytics + crash reporting wrapper.
## Autoloaded singleton. Mirrors AdManager / IAPManager patterns.
##
## Backend: Firebase (Analytics + Crashlytics) on Android/iOS. The plugin is
## not yet installed; this autoload is a no-op stub until `_has_firebase()`
## returns true. Replace the bodies of `_init_firebase` and the dispatch
## helpers with real plugin calls once the Firebase plugin lands.
##
## Web/desktop: no-op (no Firebase support). Telemetry calls are silently
## dropped — game code calls `Telemetry.log_event(...)` unconditionally.

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

var _initialized: bool = false


func _ready() -> void:
	if not _platform_supports_firebase():
		return
	if not _has_firebase():
		return
	_init_firebase()
	log_event(EVENT_APP_OPEN, {})


## Log a custom analytics event. Safe on any platform (no-op if SDK absent).
func log_event(name: String, params: Dictionary = {}) -> void:
	if not _initialized:
		return
	# Real plugin call goes here, e.g.:
	#   FirebaseAnalytics.log_event(name, params)
	pass


## Set a sticky user property (e.g. progression tier). Cohorts in dashboards.
func set_user_property(key: String, value: String) -> void:
	if not _initialized:
		return
	# FirebaseAnalytics.set_user_property(key, value)
	pass


## Record a non-fatal logical error to Crashlytics for triage.
func record_error(msg: String, fatal: bool = false) -> void:
	if not _initialized:
		return
	# FirebaseCrashlytics.record_error(msg, fatal)
	pass


# --- Internal ---

func _platform_supports_firebase() -> bool:
	var name := OS.get_name()
	return name == "Android" or name == "iOS"


func _has_firebase() -> bool:
	# Replace with real detection when plugin installed, e.g.:
	#   return ClassDB.class_exists(&"FirebaseAnalytics")
	return false


func _init_firebase() -> void:
	# Replace with plugin init once installed:
	#   FirebaseAnalytics.initialize()
	#   FirebaseCrashlytics.initialize()
	_initialized = true
