extends Node
## AdManager — platform-aware ad abstraction layer.
## Autoloaded singleton. All game code calls through this.
##
## Platform strategy:
##   Desktop (macOS, Windows, Linux) = always ad-free (premium builds)
##   Web     = AdSense via JavaScript bridge in custom HTML shell
##   Mobile  = AdMob via poing-studios Godot AdMob plugin
##   Any platform can be upgraded to ad-free via IAP

signal rewarded_ad_completed(success: bool)
signal interstitial_closed

## Platforms that are always ad-free (premium desktop builds)
const AD_FREE_PLATFORMS := ["macOS", "Windows", "Linux"]

## Rewarded ad Moonrocks grant amount
const REWARDED_AD_MOONROCKS := 50

## AdMob production ad unit IDs
const ADMOB_IDS := {
	"banner_android": "ca-app-pub-2501747033825166/3145067570",
	"banner_ios": "ca-app-pub-2501747033825166/3228828051",
	"interstitial_android": "ca-app-pub-2501747033825166/8510609741",
	"interstitial_ios": "ca-app-pub-2501747033825166/8578325259",
	"rewarded_android": "ca-app-pub-2501747033825166/4266577551",
	"rewarded_ios": "ca-app-pub-2501747033825166/1915746383",
}

## Whether a rewarded ad is currently showing
var _rewarded_pending: bool = false

## Pending callback for rewarded ad
var _rewarded_callback: Callable

## Counter for JS callback routing (web only)
var _callback_id: int = 0

## Platform detection
var _is_web: bool = false
var _is_mobile: bool = false
var _platform: String = ""

## AdMob state (mobile only)
var _admob_ready: bool = false
var _ad_view  # AdView (banner) — untyped because class only exists when plugin loaded
var _interstitial_ad  # InterstitialAd
var _rewarded_ad  # RewardedAd


func _ready() -> void:
	_platform = OS.get_name()
	_is_web = _platform == "Web"
	_is_mobile = _platform in ["Android", "iOS"]

	if is_ad_free():
		return
	if _is_web:
		_setup_web_bridge()
	elif _is_mobile:
		_init_admob()


## Returns true if this build/user should never see forced ads (banners + interstitials).
func is_ad_free() -> bool:
	if _platform in AD_FREE_PLATFORMS:
		return true
	return globalvar.is_ads_removed()


## Returns true if ads are supported on this platform (web or mobile).
func is_ad_supported() -> bool:
	return not (_platform in AD_FREE_PLATFORMS)


## Returns true if rewarded ads can be shown (always available on ad-supported platforms).
func is_rewarded_available() -> bool:
	return is_ad_supported()


## Show an interstitial ad (between levels). No-op if ad-free.
func show_interstitial() -> void:
	if is_ad_free():
		interstitial_closed.emit()
		return
	if _is_web:
		_web_show_interstitial()
	elif _is_mobile:
		_mobile_show_interstitial()
	else:
		interstitial_closed.emit()


## Show a rewarded video ad. Calls callback(true) if watched, callback(false) if skipped.
func show_rewarded(callback: Callable) -> void:
	if not is_rewarded_available():
		callback.call(false)
		return
	_rewarded_pending = true
	_rewarded_callback = callback
	if _is_web:
		_web_show_rewarded()
	elif _is_mobile:
		_mobile_show_rewarded()
	else:
		_rewarded_pending = false
		callback.call(false)


## Show a banner ad (menu/shop screens only).
func show_banner() -> void:
	if is_ad_free():
		return
	if _is_web:
		JavaScriptBridge.eval("if(window.showBannerAd) window.showBannerAd();")
	elif _is_mobile:
		_mobile_show_banner()


## Hide the banner ad (during gameplay).
func hide_banner() -> void:
	if _is_web:
		JavaScriptBridge.eval("if(window.hideBannerAd) window.hideBannerAd();")
	elif _is_mobile:
		_mobile_hide_banner()


## Purchase ad removal via moonrocks (delegates to globalvar).
func remove_ads() -> bool:
	var success := globalvar.buy_ad_removal()
	if success:
		hide_banner()
	return success


## Restore ad removal state (reads from globalvar save data — no separate file).
func restore_purchase() -> void:
	# ads_removed is now part of savegame.json via globalvar; nothing extra to do.
	pass


# ============================================================
# Mobile — AdMob via poing-studios/godot-admob-plugin
# ============================================================

func _get_ad_id(kind: String) -> String:
	var key := kind + "_" + ("android" if _platform == "Android" else "ios")
	return ADMOB_IDS.get(key, "")


func _init_admob() -> void:
	# MobileAds is a GDScript class_name from the poing-studios AdMob plugin.
	# Its _plugin will be null if the native singleton isn't present (e.g. in
	# the editor or if the plugin .aar/.xcframework wasn't exported). In that
	# case all its methods safely no-op, but we still get initialization.
	var on_init := OnInitializationCompleteListener.new()
	on_init.on_initialization_complete = func(_status) -> void:
		_admob_ready = true
		# Pre-load interstitial and rewarded so they're ready when needed
		_mobile_load_interstitial()
		_mobile_load_rewarded()

	MobileAds.initialize(on_init)


# --- Banner ---

func _mobile_show_banner() -> void:
	if not _admob_ready:
		return
	if _ad_view:
		_ad_view.show()
		return
	var unit_id := _get_ad_id("banner")
	if unit_id.is_empty():
		return
	var ad_size = AdSize.get_current_orientation_anchored_adaptive_banner_ad_size(AdSize.FULL_WIDTH)
	_ad_view = AdView.new(unit_id, ad_size, AdPosition.Values.BOTTOM)
	var listener := AdListener.new()
	listener.on_ad_failed_to_load = func(err) -> void:
		push_warning("AdManager: Banner failed to load: ", err.message)
	_ad_view.ad_listener = listener
	_ad_view.load_ad(AdRequest.new())


func _mobile_hide_banner() -> void:
	if _ad_view:
		_ad_view.hide()


# --- Interstitial ---

func _mobile_load_interstitial() -> void:
	if not _admob_ready:
		return
	var unit_id := _get_ad_id("interstitial")
	if unit_id.is_empty():
		return
	var load_cb := InterstitialAdLoadCallback.new()
	load_cb.on_ad_loaded = func(ad) -> void:
		_interstitial_ad = ad
		var content_cb := FullScreenContentCallback.new()
		content_cb.on_ad_dismissed_full_screen_content = func() -> void:
			_interstitial_ad.destroy()
			_interstitial_ad = null
			interstitial_closed.emit()
			_mobile_load_interstitial()  # Pre-load next one
		content_cb.on_ad_failed_to_show_full_screen_content = func(_err) -> void:
			_interstitial_ad.destroy()
			_interstitial_ad = null
			interstitial_closed.emit()
			_mobile_load_interstitial()
		_interstitial_ad.full_screen_content_callback = content_cb
	load_cb.on_ad_failed_to_load = func(err) -> void:
		push_warning("AdManager: Interstitial failed to load: ", err.message)
	InterstitialAdLoader.new().load(unit_id, AdRequest.new(), load_cb)


func _mobile_show_interstitial() -> void:
	if _interstitial_ad:
		_interstitial_ad.show()
	else:
		# Ad not loaded yet — don't block the player
		interstitial_closed.emit()
		_mobile_load_interstitial()


# --- Rewarded ---

func _mobile_load_rewarded() -> void:
	if not _admob_ready:
		return
	var unit_id := _get_ad_id("rewarded")
	if unit_id.is_empty():
		return
	var load_cb := RewardedAdLoadCallback.new()
	load_cb.on_ad_loaded = func(ad) -> void:
		_rewarded_ad = ad
		var content_cb := FullScreenContentCallback.new()
		content_cb.on_ad_dismissed_full_screen_content = func() -> void:
			_rewarded_ad.destroy()
			_rewarded_ad = null
			# If reward wasn't granted by on_user_earned_reward, treat as skip
			if _rewarded_pending:
				_rewarded_pending = false
				if _rewarded_callback.is_valid():
					_rewarded_callback.call(false)
			_mobile_load_rewarded()  # Pre-load next one
		content_cb.on_ad_failed_to_show_full_screen_content = func(_err) -> void:
			_rewarded_ad.destroy()
			_rewarded_ad = null
			if _rewarded_pending:
				_rewarded_pending = false
				if _rewarded_callback.is_valid():
					_rewarded_callback.call(false)
			_mobile_load_rewarded()
		_rewarded_ad.full_screen_content_callback = content_cb
	load_cb.on_ad_failed_to_load = func(err) -> void:
		push_warning("AdManager: Rewarded ad failed to load: ", err.message)
	RewardedAdLoader.new().load(unit_id, AdRequest.new(), load_cb)


func _mobile_show_rewarded() -> void:
	if _rewarded_ad:
		var reward_listener := OnUserEarnedRewardListener.new()
		reward_listener.on_user_earned_reward = func(_item) -> void:
			# Player watched the full ad — grant reward
			_rewarded_pending = false
			if _rewarded_callback.is_valid():
				_rewarded_callback.call(true)
		_rewarded_ad.show(reward_listener)
	else:
		# Ad not loaded — fail gracefully
		_rewarded_pending = false
		if _rewarded_callback.is_valid():
			_rewarded_callback.call(false)
		_mobile_load_rewarded()


# ============================================================
# Web — AdSense via JavaScript bridge
# ============================================================

func _setup_web_bridge() -> void:
	JavaScriptBridge.eval("""
		window.godotAdCallback = function(id, success) {
			if (window.godotAdBridge) {
				window.godotAdBridge.callback(id, success);
			}
		};
	""")


func _web_show_interstitial() -> void:
	_callback_id += 1
	var cid := _callback_id
	JavaScriptBridge.eval(
		"if(window.showInterstitialAd) window.showInterstitialAd(%d); else window.godotAdCallback(%d, true);" % [cid, cid]
	)
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func(): interstitial_closed.emit())


func _web_show_rewarded() -> void:
	_callback_id += 1
	var cid := _callback_id
	JavaScriptBridge.eval(
		"if(window.showRewardedAd) window.showRewardedAd(%d); else window.godotAdCallback(%d, true);" % [cid, cid]
	)
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		_rewarded_pending = false
		if _rewarded_callback.is_valid():
			_rewarded_callback.call(true)
	)



