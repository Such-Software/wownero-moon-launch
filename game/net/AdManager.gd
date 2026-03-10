extends Node
## AdManager — platform-aware ad abstraction layer.
## Autoloaded singleton. Provides clean API for showing ads without
## any game code needing to know about platform specifics.
##
## Design:
##   Desktop (macOS, Windows, Linux) = always ad-free (sold on itch.io)
##   Web = ads via JavaScript bridge (AdSense for display, AdSense rewarded)
##   Mobile (Android/iOS) = ads via AdMob plugin
##   Any platform can be upgraded to ad-free via IAP
##
## Web integration:
##   The HTML5 export template should include an ad script in the shell HTML.
##   This script exposes global JS functions that AdManager calls via JavaScriptBridge:
##     window.showInterstitialAd(callback_id)  — show AdSense interstitial
##     window.showRewardedAd(callback_id)      — show AdSense rewarded ad
##     window.showBannerAd()                   — show persistent banner
##     window.hideBannerAd()                   — hide banner
##   Callbacks are routed back via: window.godotAdCallback(callback_id, success)
##
## Usage:
##   AdManager.is_ad_free()            → bool
##   AdManager.show_interstitial()     → void (no-op if ad-free)
##   AdManager.show_rewarded(callback) → void (calls callback(success) when done)
##   AdManager.show_banner()           → void (menu screens only)
##   AdManager.hide_banner()           → void
##   AdManager.remove_ads()            → void (IAP upgrade, persisted)

signal rewarded_ad_completed(success: bool)
signal interstitial_closed

## Platforms that are always ad-free (premium desktop builds)
const AD_FREE_PLATFORMS := ["macOS", "Windows", "Linux"]

## Rewarded ad Moonrocks grant amount
const REWARDED_AD_MOONROCKS := 50

## Whether the user purchased ad removal (persisted in save)
var _ads_removed: bool = false

## Whether a rewarded ad is currently showing
var _rewarded_pending: bool = false

## Pending callback for rewarded ad
var _rewarded_callback: Callable

## Counter for JS callback routing
var _callback_id: int = 0

## Whether we're on web platform
var _is_web: bool = false


func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	_load_ad_state()
	if _is_web and not is_ad_free():
		_setup_web_bridge()


## Returns true if this build/user should never see ads.
func is_ad_free() -> bool:
	if OS.get_name() in AD_FREE_PLATFORMS:
		return true
	return _ads_removed


## Returns true if ads are supported on this platform (web or mobile).
func is_ad_supported() -> bool:
	return not (OS.get_name() in AD_FREE_PLATFORMS)


## Show an interstitial ad (between levels). No-op if ad-free.
func show_interstitial() -> void:
	if is_ad_free():
		interstitial_closed.emit()
		return
	if _is_web:
		_web_show_interstitial()
	else:
		# Mobile: AdMob plugin call would go here
		# Stub: emit closed immediately
		interstitial_closed.emit()


## Show a rewarded video ad. Calls callback(true) if watched, callback(false) if skipped.
func show_rewarded(callback: Callable) -> void:
	if is_ad_free():
		# Ad-free users get the reward without watching
		callback.call(true)
		return
	_rewarded_pending = true
	_rewarded_callback = callback
	if _is_web:
		_web_show_rewarded()
	else:
		# Mobile: AdMob rewarded ad plugin call would go here
		# Stub: simulate success after brief delay
		var timer := get_tree().create_timer(0.5)
		timer.timeout.connect(func():
			_rewarded_pending = false
			callback.call(true)
		)


## Show a banner ad (menu/shop screens only).
func show_banner() -> void:
	if is_ad_free():
		return
	if _is_web:
		JavaScriptBridge.eval("if(window.showBannerAd) window.showBannerAd();")
	# Mobile: AdMob banner show


## Hide the banner ad (during gameplay).
func hide_banner() -> void:
	if _is_web:
		JavaScriptBridge.eval("if(window.hideBannerAd) window.hideBannerAd();")
	# Mobile: AdMob banner hide


## Purchase ad removal (IAP). Persists to save file.
func remove_ads() -> void:
	_ads_removed = true
	hide_banner()
	_save_ad_state()


## Restore ad removal state (e.g. after reinstall, check receipt).
func restore_purchase() -> void:
	_load_ad_state()


# --- Web (AdSense) integration ---

func _setup_web_bridge() -> void:
	## Register a JS callback that the ad script calls when an ad completes.
	## The HTML shell should call: window.godotAdCallback(id, success)
	JavaScriptBridge.eval("""
		window.godotAdCallback = function(id, success) {
			// Route back to Godot via the interface object
			if (window.godotAdBridge) {
				window.godotAdBridge.callback(id, success);
			}
		};
	""")


func _web_show_interstitial() -> void:
	_callback_id += 1
	var cid := _callback_id
	# Try to call the JS interstitial function
	JavaScriptBridge.eval(
		"if(window.showInterstitialAd) window.showInterstitialAd(%d); else window.godotAdCallback(%d, true);" % [cid, cid]
	)
	# Since we can't easily await JS callbacks in the stub,
	# emit closed after a short delay
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func(): interstitial_closed.emit())


func _web_show_rewarded() -> void:
	_callback_id += 1
	var cid := _callback_id
	JavaScriptBridge.eval(
		"if(window.showRewardedAd) window.showRewardedAd(%d); else window.godotAdCallback(%d, true);" % [cid, cid]
	)
	# Await result via timer fallback (real implementation uses JS callback bridge)
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		_rewarded_pending = false
		if _rewarded_callback.is_valid():
			_rewarded_callback.call(true)
	)


# --- Persistence ---

func _save_ad_state() -> void:
	var f := FileAccess.open("user://adstate.json", FileAccess.WRITE)
	if f:
		f.store_line(JSON.stringify({"ads_removed": _ads_removed}))
		f.close()


func _load_ad_state() -> void:
	if not FileAccess.file_exists("user://adstate.json"):
		return
	var f := FileAccess.open("user://adstate.json", FileAccess.READ)
	if not f:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK:
		var data = json.get_data()
		if data is Dictionary:
			_ads_removed = bool(data.get("ads_removed", false))
	f.close()
			_ads_removed = bool(data.get("ads_removed", false))
	f.close()
