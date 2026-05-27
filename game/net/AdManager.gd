extends Node
## AdManager — platform-aware ad abstraction layer.
## Autoloaded singleton. All game code calls through this.
##
## Platform strategy:
##   Desktop (macOS, Windows, Linux) = always ad-free (premium builds)
##   Web     = in-game nag banner/popup promoting itch.io
##   Mobile  = AdMob via godot-sdk-integrations/godot-admob plugin v6+
##   Any platform can be upgraded to ad-free via IAP

signal rewarded_ad_completed(success: bool)
signal interstitial_closed

## Platforms that are always ad-free (premium desktop builds)
const AD_FREE_PLATFORMS := ["macOS", "Windows", "Linux"]

## Rewarded ad Moonrocks grant amount
const REWARDED_AD_MOONROCKS := 150

## AdMob production application IDs (one per platform).
const ADMOB_APP_ID_ANDROID := "ca-app-pub-2501747033825166~3900713647"
const ADMOB_APP_ID_IOS     := "ca-app-pub-2501747033825166~9592024025"

## AdMob production ad unit IDs
const ADMOB_IDS_REAL := {
	"banner_android": "ca-app-pub-2501747033825166/3145067570",
	"banner_ios": "ca-app-pub-2501747033825166/3228828051",
	"interstitial_android": "ca-app-pub-2501747033825166/8510609741",
	"interstitial_ios": "ca-app-pub-2501747033825166/8578325259",
	"rewarded_android": "ca-app-pub-2501747033825166/4266577551",
	"rewarded_ios": "ca-app-pub-2501747033825166/1915746383",
}

## Google's universal test ad units. ALWAYS return test ads. Used in debug builds
## so we can verify the pipeline without waiting for AdMob console propagation
## or registering the device as a test device.
const ADMOB_IDS_TEST := {
	"banner_android": "ca-app-pub-3940256099942544/6300978111",
	"banner_ios": "ca-app-pub-3940256099942544/2934735716",
	"interstitial_android": "ca-app-pub-3940256099942544/1033173712",
	"interstitial_ios": "ca-app-pub-3940256099942544/4411468910",
	"rewarded_android": "ca-app-pub-3940256099942544/5224354917",
	"rewarded_ios": "ca-app-pub-3940256099942544/1712485313",
}

## Use test ad unit IDs in debug builds so the iPad sideload installs see ads
## without needing the device registered in the AdMob console (a propagation
## delay on real ad units, and Google often returns no-fill for unregistered
## debug devices on real units anyway).
var ADMOB_IDS: Dictionary = ADMOB_IDS_TEST if OS.is_debug_build() else ADMOB_IDS_REAL

## Whether a rewarded ad is currently in-flight (between request and result)
var _rewarded_pending: bool = false
var _rewarded_callback: Callable

## Platform detection
var _is_web: bool = false
var _is_mobile: bool = false
var _platform: String = ""

## New AdMob plugin (godot-sdk-integrations/godot-admob) — single Admob node
## owns banner / interstitial / rewarded lifecycles. Created lazily on mobile.
var _admob = null      # Admob from res://addons/AdmobPlugin/Admob.gd
var _admob_ready: bool = false
var _banner_visible: bool = false

## Web nag banner (in-game CanvasLayer shown instead of AdSense)
var _nag_banner: CanvasLayer = null

func _dbg(msg: String) -> void:
	push_warning("[AdManager] " + msg)

const ITCH_URL := "https://suchsoftware.itch.io/such-moon-launch"


func _ready() -> void:
	_platform = OS.get_name()
	_is_web = _platform == "Web"
	_is_mobile = _platform in ["Android", "iOS"]
	_dbg("ready on %s ads_removed=%s" % [_platform, globalvar.is_ads_removed()])

	# Always initialize on supported platforms. is_ad_free() only gates the
	# public show methods (banner, interstitial) — rewarded ads stay opt-in
	# even for premium users so they can still grind extra Moonrocks.
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
## players. Kept as a no-op stub so existing call sites don't crash.
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
	pass


# ============================================================
# Mobile — AdMob via godot-sdk-integrations/godot-admob plugin v6
# ============================================================

func _init_admob() -> void:
	_dbg("A: init_admob start")
	if not Engine.has_singleton("AdmobPlugin"):
		_dbg("B: singleton NOT registered")
		return
	_dbg("B: got singleton")
	_admob = Engine.get_singleton("AdmobPlugin")
	_dbg("C: connecting signals")
	_admob.connect("initialization_completed", _on_native_init_complete)
	_admob.connect("banner_ad_loaded", _on_native_banner_loaded)
	_admob.connect("banner_ad_failed_to_load", _on_native_banner_failed)
	_admob.connect("rewarded_ad_loaded", _on_native_rewarded_loaded)
	_admob.connect("rewarded_ad_failed_to_load", _on_native_rewarded_failed)
	_admob.connect("rewarded_ad_user_earned_reward", _on_native_rewarded_earned)
	_admob.connect("rewarded_ad_dismissed_full_screen_content", _on_native_rewarded_dismissed)
	_admob.connect("rewarded_ad_failed_to_show_full_screen_content", _on_native_rewarded_dismissed)
	_dbg("D: signals ok, calling initialize()")
	_admob.initialize()
	_dbg("E: initialize() returned, waiting for signal")
	var watchdog := get_tree().create_timer(5.0)
	watchdog.timeout.connect(func():
		if _admob_ready: return
		_dbg("WATCHDOG 5s: init_completed never fired")
	)


# ============================================================
# Native plugin handlers (talking to AdmobPlugin singleton directly)
# ============================================================

var _banner_ad_id: String = ""
var _rewarded_ad_id: String = ""

func _on_native_init_complete(_status_data) -> void:
	_admob_ready = true
	_dbg("init COMPLETE - loading banner+rewarded")
	_native_load_banner()
	_native_load_rewarded()


func _native_load_banner() -> void:
	var ad_unit: String = ADMOB_IDS["banner_ios"] if _platform == "iOS" else ADMOB_IDS["banner_android"]
	var request := {
		"ad_unit_id": ad_unit,
		"ad_position": "BOTTOM",
		"ad_size": "BANNER",
		"anchor_to_safe_area": true,
		"keywords": [],
		"network_extras": [],
	}
	_admob.load_banner_ad(request)


func _native_load_rewarded() -> void:
	var ad_unit: String = ADMOB_IDS["rewarded_ios"] if _platform == "iOS" else ADMOB_IDS["rewarded_android"]
	var request := {
		"ad_unit_id": ad_unit,
		"keywords": [],
		"network_extras": [],
	}
	_admob.load_rewarded_ad(request)


func _on_native_banner_loaded(ad_data: Dictionary, _response_info: Dictionary) -> void:
	_banner_ad_id = ad_data.get("ad_id", "")
	_dbg("banner loaded id=%s want_show=%s" % [_banner_ad_id, _banner_visible])
	if _banner_visible and _admob:
		_admob.show_banner_ad(_banner_ad_id)


func _on_native_banner_failed(_ad_data: Dictionary, error_data: Dictionary) -> void:
	_dbg("banner FAILED: %s" % str(error_data))


func _on_native_rewarded_loaded(ad_data: Dictionary, _response_info: Dictionary) -> void:
	_rewarded_ad_id = ad_data.get("ad_id", "")
	if _rewarded_pending and _admob:
		_admob.show_rewarded_ad(_rewarded_ad_id)


func _on_native_rewarded_failed(_ad_data: Dictionary, error_data: Dictionary) -> void:
	_dbg("rewarded FAILED: %s" % str(error_data))
	if _rewarded_pending:
		_finish_rewarded(false)


func _on_native_rewarded_earned(_ad_data: Dictionary, _reward_data: Dictionary) -> void:
	_finish_rewarded(true)


func _on_native_rewarded_dismissed(_ad_data: Dictionary, _error_data = null) -> void:
	if _rewarded_pending:
		_finish_rewarded(false)
	_native_load_rewarded()


# --- Banner ---

func _mobile_show_banner() -> void:
	_banner_visible = true
	if not _admob_ready or _admob == null:
		return  # show when banner_loaded fires
	if _banner_ad_id != "":
		_admob.show_banner_ad(_banner_ad_id)
	else:
		_native_load_banner()


func _mobile_hide_banner() -> void:
	_banner_visible = false
	if _admob and _banner_ad_id != "":
		_admob.hide_banner_ad(_banner_ad_id)


# --- Rewarded ---

func _mobile_show_rewarded() -> void:
	if not _admob_ready or _admob == null:
		_finish_rewarded(false)
		return
	if _rewarded_ad_id != "":
		_admob.show_rewarded_ad(_rewarded_ad_id)
	else:
		_native_load_rewarded()


func _finish_rewarded(success: bool) -> void:
	_rewarded_pending = false
	if _rewarded_callback.is_valid():
		var cb := _rewarded_callback
		_rewarded_callback = Callable()
		cb.call(success)
	rewarded_ad_completed.emit(success)


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


func _web_show_rewarded() -> void:
	_web_show_nag_popup(func():
		# Grant reward anyway as a goodwill gesture (like watching an ad)
		_finish_rewarded(true)
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
