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
const REWARDED_AD_MOONROCKS := 150

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

## Platform detection
var _is_web: bool = false
var _is_mobile: bool = false
var _platform: String = ""

## AdMob state (mobile only)
var _admob_ready: bool = false
var _ad_view  # AdView (banner) — untyped because class only exists when plugin loaded
var _interstitial_ad  # InterstitialAd
var _rewarded_ad  # RewardedAd

## Web nag banner (in-game CanvasLayer shown instead of AdSense)
var _nag_banner: CanvasLayer = null

## itch.io URL for this game
const ITCH_URL := "https://suchsoftware.itch.io/such-moon-launch"


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


## Forced interstitials are disabled by design — we don't push 30-60s ads on
## players. Kept as a no-op stub so existing call sites don't crash; existing
## SDK init/load logic stays in place in case we re-enable in a future build.
func show_interstitial() -> void:
	interstitial_closed.emit()
	return


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
		_web_show_nag_banner()
	elif _is_mobile:
		_mobile_show_banner()


## Hide the banner ad (during gameplay).
func hide_banner() -> void:
	if _is_web:
		_web_hide_nag_banner()
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
# Web — Nag screens (AdSense unavailable, promote itch.io)
# ============================================================

func _setup_web_bridge() -> void:
	# No JS ad bridge needed — using in-game nag banners instead
	pass


func _web_show_nag_banner() -> void:
	if _nag_banner and is_instance_valid(_nag_banner):
		return  # Already showing
	_nag_banner = CanvasLayer.new()
	_nag_banner.layer = 100
	add_child(_nag_banner)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.15, 0.92)
	style.border_color = Color(1.0, 0.85, 0.2, 0.6)
	style.border_width_top = 2
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -40
	_nag_banner.add_child(panel)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	panel.add_child(hbox)
	var lbl := Label.new()
	lbl.text = "Enjoy the game? Get the full version on itch.io!"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	hbox.add_child(lbl)
	var btn := Button.new()
	btn.text = "Visit itch.io"
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(100, 24)
	btn.pressed.connect(func(): OS.shell_open(ITCH_URL))
	hbox.add_child(btn)


func _web_hide_nag_banner() -> void:
	if _nag_banner and is_instance_valid(_nag_banner):
		_nag_banner.queue_free()
		_nag_banner = null


func _web_show_interstitial() -> void:
	_web_show_nag_popup(func(): interstitial_closed.emit())


func _web_show_rewarded() -> void:
	_web_show_nag_popup(func():
		# Grant reward anyway as a goodwill gesture (like watching an ad)
		_rewarded_pending = false
		if _rewarded_callback.is_valid():
			_rewarded_callback.call(true)
	)


func _web_show_nag_popup(on_close: Callable) -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 110
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.12, 0.97)
	style.border_color = Color(1.0, 0.85, 0.2, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -120
	panel.offset_bottom = 120
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Support the Developer!"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var msg := Label.new()
	msg.text = "Get the full version on itch.io!\nAd-free, supports development,\nand play on desktop or mobile."
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var visit := Button.new()
	visit.text = "Visit itch.io"
	visit.custom_minimum_size = Vector2(140, 36)
	visit.add_theme_font_size_override("font_size", 16)
	visit.pressed.connect(func(): OS.shell_open(ITCH_URL))
	btn_row.add_child(visit)

	var close := Button.new()
	close.text = "Continue"
	close.custom_minimum_size = Vector2(120, 36)
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(func():
		overlay.queue_free()
		on_close.call()
	)
	btn_row.add_child(close)
