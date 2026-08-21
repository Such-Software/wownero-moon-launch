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
signal premium_status_changed(is_premium: bool)

const ExternalLinks = preload("res://game/net/ExternalLinks.gd")

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

## Debug builds use Google's test inventory. Release builds are pinned to the
## registered production units and never fall back to test inventory.
var _use_test_ads: bool = false

## Resolved against _use_test_ads each access.
var ADMOB_IDS: Dictionary:
	get:
		return ADMOB_IDS_TEST if _use_test_ads else ADMOB_IDS_REAL

## Guards against double initialization.
var _admob_init_started: bool = false
var _mobile_ads_initialize_called: bool = false
var _consent_form_requested: bool = false

## Whether a rewarded ad is currently in-flight (between request and result)
var _rewarded_pending: bool = false
var _rewarded_callback: Callable

## Platform detection
var _is_web: bool = false
var _is_mobile: bool = false
var _platform: String = ""
var _web_window = null
var _web_entitlement_callback = null

## New AdMob plugin (godot-sdk-integrations/godot-admob) — single Admob node
## owns banner / interstitial / rewarded lifecycles. Created lazily on mobile.
var _admob = null      # Admob from res://addons/AdmobPlugin/Admob.gd
var _admob_ready: bool = false
var _banner_visible: bool = false

## Web nag banner (in-game CanvasLayer shown instead of AdSense)
var _nag_banner: CanvasLayer = null

## TEMP: on-screen ad-debug HUD. Works in RELEASE builds too (it's just a Label,
## not push_warning which release templates strip). Flip false before shipping.
const SHOW_AD_DEBUG_HUD := false
var _debug_hud: Label = null
var _debug_lines: Array[String] = []

func _dbg(msg: String) -> void:
	push_warning("[AdManager] " + msg)
	if not SHOW_AD_DEBUG_HUD:
		return
	_debug_lines.append(msg)
	if _debug_lines.size() > 14:
		_debug_lines.pop_front()
	if _debug_hud == null:
		var cl := CanvasLayer.new()
		cl.layer = 999
		add_child(cl)
		_debug_hud = Label.new()
		_debug_hud.add_theme_font_size_override("font_size", 11)
		_debug_hud.add_theme_color_override("font_color", Color(1, 1, 0.4))
		_debug_hud.add_theme_color_override("font_outline_color", Color.BLACK)
		_debug_hud.add_theme_constant_override("outline_size", 3)
		_debug_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_debug_hud.offset_left = 6
		_debug_hud.offset_top = 80
		_debug_hud.offset_right = 760
		_debug_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.add_child(_debug_hud)
	if _debug_hud:
		_debug_hud.text = "\n".join(_debug_lines)

const ITCH_URL := ExternalLinks.ITCH_URL
## The free web build funnels players to the monetized mobile apps.
const APP_STORE_URL := ExternalLinks.APP_STORE_URL
const PLAY_STORE_URL := ExternalLinks.PLAY_STORE_URL


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
		if OS.is_debug_build():
			# Debug sideloads always use test ads.
			_use_test_ads = true
			_init_admob_once()
		else:
			# Release inventory is a committed, reviewable binary choice.
			_use_test_ads = false
			_init_admob_once()


func _exit_tree() -> void:
	if _web_window != null and _web_entitlement_callback != null:
		_web_window.removeEventListener(
			"such-app-entitlements-changed", _web_entitlement_callback
		)
	_web_entitlement_callback = null
	_web_window = null


func _init_admob_once() -> void:
	if _admob_init_started:
		return
	_admob_init_started = true
	_init_admob()


## Returns true if this build/user should never see forced ads (banners + interstitials).
func is_ad_free() -> bool:
	if _platform in AD_FREE_PLATFORMS:
		return true
	if _is_web and _web_has_neutral_premium():
		return true
	return globalvar.is_ads_removed()


## Web Premium is ephemeral provider-neutral capability state resolved by the
## user's OIDC session. Never copy it into the local save's ad-removal flag.
func _web_has_neutral_premium() -> bool:
	if not Engine.has_singleton("JavaScriptBridge"):
		return false
	return JavaScriptBridge.eval(
		"window.SUCH_APP && window.SUCH_APP.premium === true", true
	) == true


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
	if _supports_native_consent_flow():
		_admob.connect("consent_info_updated", _on_native_consent_info_updated)
		_admob.connect("consent_info_update_failed", _on_native_consent_info_update_failed)
		_admob.connect("consent_form_loaded", _on_native_consent_form_loaded)
		_admob.connect("consent_form_failed_to_load", _on_native_consent_form_failed_to_load)
		_admob.connect("consent_form_dismissed", _on_native_consent_form_dismissed)
		_dbg("D: signals ok, requesting current consent information")
		_admob.update_consent_info({
			"is_real": not _use_test_ads,
			"test_device_hashed_ids": [],
		})
	else:
		# A release build must never initialize an ads SDK before the consent
		# gate. Debug builds may continue with Google's test inventory so a
		# developer can diagnose an incomplete local plugin installation.
		_dbg("D: native consent API unavailable")
		if _use_test_ads:
			_initialize_mobile_ads_after_consent()


func _supports_native_consent_flow() -> bool:
	if _admob == null:
		return false
	var required_methods := [
		"update_consent_info",
		"get_consent_status",
		"is_consent_form_available",
		"load_consent_form",
		"show_consent_form",
	]
	var required_signals := [
		"consent_info_updated",
		"consent_info_update_failed",
		"consent_form_loaded",
		"consent_form_failed_to_load",
		"consent_form_dismissed",
	]
	for method in required_methods:
		if not _admob.has_method(method):
			return false
	for native_signal in required_signals:
		if not _admob.has_signal(native_signal):
			return false
	return true


func _native_consent_status() -> String:
	if _admob == null or not _admob.has_method("get_consent_status"):
		return "UNKNOWN"
	return str(_admob.get_consent_status()).strip_edges().to_upper()


func _consent_status_allows_ads() -> bool:
	return _native_consent_status() in ["NOT_REQUIRED", "OBTAINED"]


func _continue_from_cached_consent(context: String) -> void:
	var status := _native_consent_status()
	_dbg("consent %s status=%s" % [context, status])
	if status in ["NOT_REQUIRED", "OBTAINED"]:
		_initialize_mobile_ads_after_consent()


func _on_native_consent_info_updated() -> void:
	var status := _native_consent_status()
	_dbg("consent info updated status=%s" % status)
	if status in ["NOT_REQUIRED", "OBTAINED"]:
		_initialize_mobile_ads_after_consent()
		return
	if status == "REQUIRED" and _admob.is_consent_form_available():
		_consent_form_requested = true
		_admob.load_consent_form()
		return
	_dbg("consent gate remains closed: status=%s form_available=%s" % [
		status,
		_admob.is_consent_form_available(),
	])


func _on_native_consent_info_update_failed(error_data: Dictionary) -> void:
	_dbg("consent info update failed: %s" % str(error_data))
	# UMP permits continuing from a previously obtained cached decision when a
	# refresh fails offline. UNKNOWN/REQUIRED remains fail-closed.
	_continue_from_cached_consent("update failure")


func _on_native_consent_form_loaded() -> void:
	if not _consent_form_requested:
		return
	_dbg("consent form loaded")
	_admob.show_consent_form()


func _on_native_consent_form_failed_to_load(error_data: Dictionary) -> void:
	_consent_form_requested = false
	_dbg("consent form failed to load: %s" % str(error_data))
	_continue_from_cached_consent("form load failure")


func _on_native_consent_form_dismissed(error_data: Dictionary) -> void:
	_consent_form_requested = false
	_dbg("consent form dismissed: %s" % str(error_data))
	_continue_from_cached_consent("form dismissal")


func _initialize_mobile_ads_after_consent() -> void:
	if _mobile_ads_initialize_called or _admob == null:
		return
	if not _use_test_ads and not _consent_status_allows_ads():
		_dbg("refusing release ads initialization without consent resolution")
		return
	_mobile_ads_initialize_called = true
	# Force non-personalized ads BEFORE initialize(). Without this the SDK uses
	# AdmobConfig.PersonalizationState.DEFAULT, documented as "attempt to serve
	# personalized ads based on the user's past behavior and interests" — which is
	# tracking under Apple's definition and conflicts with the company rule against
	# cross-app identifiers (docs engineering/app-analytics.md). It is also what makes
	# privacy/tracking_enabled=false and used_for_tracking=false truthful declarations.
	#
	# AdManager talks to the raw native singleton rather than the Admob.gd wrapper, so
	# this passes the same raw dictionary AdmobConfig.get_raw_data() would produce.
	# Keys and values mirror addons/AdmobPlugin/model/AdmobConfig.gd.
	_apply_non_personalized_request_config()
	_dbg("calling initialize() after consent gate")
	_admob.initialize()


func _apply_non_personalized_request_config() -> void:
	if _admob == null or not _admob.has_method("set_request_configuration"):
		_dbg("set_request_configuration unavailable; cannot force NPA")
		return
	_admob.set_request_configuration({
		"is_real": not _use_test_ads,
		"personalization_state": 2,             # PersonalizationState.DISABLED — NPA only
		"tag_for_child_directed_treatment": 0,  # FALSE — not a child-directed app
		"tag_for_under_age_of_consent": -1,     # UNSPECIFIED — UMP resolves EEA handling
		"first_party_id_enabled": false,        # no cross-app first-party id
		"max_ad_content_rating": "T",
		"test_device_ids": [],
	})
	_dbg("request configuration set: non-personalized ads only")
	_dbg("initialize() returned, waiting for signal")
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
	var bid: String = ADMOB_IDS["banner_ios"] if _platform == "iOS" else ADMOB_IDS["banner_android"]
	_dbg("init COMPLETE debug=%s banner_unit=%s" % [OS.is_debug_build(), bid])
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
	# Clear the consumed ad ID immediately. Without this, a fast re-tap before
	# the next preload completes would try to show an already-watched ad and
	# fail with "Ad unavailable" (a second flavor of the 2.1(a) race we got
	# rejected on).
	_rewarded_ad_id = ""
	_native_load_rewarded()
	# The ad ran as its own activity and may have left the device in an
	# orientation we do not want. RESUMED covers this too, but a rewarded ad is
	# the one overlay a player watches mid-run, so put the lock back here rather
	# than waiting for a notification whose delivery we do not control.
	globalvar.apply_orientation()


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
	# If we have an ad cached, show it immediately.
	if _admob_ready and _admob != null and _rewarded_ad_id != "":
		_admob.show_rewarded_ad(_rewarded_ad_id)
		return
	# Singleton genuinely missing — only path that fails fast.
	if _admob == null:
		_finish_rewarded(false)
		return
	# Otherwise WAIT for init + load to complete. The pending state set in
	# show_rewarded() makes _on_native_init_complete -> _on_native_rewarded_loaded
	# auto-fire the show. Don't fail on a fast reviewer who tapped before
	# init/load finished on cold launch — that's the App Store 2.1(a)
	# "Ad unavailable" race we got rejected on in builds 6 and 7.
	if _admob_ready:
		# Init done, just no ad cached yet; kick a load. _on_native_rewarded_loaded
		# checks _rewarded_pending and shows.
		_native_load_rewarded()
	# else: init still pending; _on_native_init_complete will auto-load and
	# the pending check will fire the show. Nothing to do but wait.
	#
	# Safety net: if init or load truly never completes (e.g. SDK is wedged
	# offline), don't leave the UI on "Loading..." forever. 15s is well past
	# normal cold-launch init (1-3s) + load (~0.5-1s).
	var timeout := get_tree().create_timer(15.0)
	timeout.timeout.connect(func():
		if _rewarded_pending:
			_dbg("rewarded TIMEOUT 15s waiting for init/load")
			_finish_rewarded(false)
	)


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
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	_web_window = JavaScriptBridge.get_interface("window")
	if _web_window == null:
		return
	_web_entitlement_callback = JavaScriptBridge.create_callback(
		_on_web_entitlements_changed
	)
	_web_window.addEventListener(
		"such-app-entitlements-changed", _web_entitlement_callback
	)
	# Covers a cached entitlement that resolved before this autoload was ready.
	_on_web_entitlements_changed([])


func _on_web_entitlements_changed(_arguments: Array) -> void:
	var premium := _web_has_neutral_premium()
	if premium:
		_web_hide_nag_banner()
	premium_status_changed.emit(premium)


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
	lbl.text = "Love the game? Get the free app:"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	hbox.add_child(lbl)
	var ios_btn := Button.new()
	ios_btn.text = " App Store "
	ios_btn.add_theme_font_size_override("font_size", 13)
	ios_btn.custom_minimum_size = Vector2(96, 24)
	ios_btn.pressed.connect(func(): OS.shell_open(APP_STORE_URL))
	hbox.add_child(ios_btn)
	var play_btn := Button.new()
	play_btn.text = " Google Play "
	play_btn.add_theme_font_size_override("font_size", 13)
	play_btn.custom_minimum_size = Vector2(110, 24)
	play_btn.pressed.connect(func(): OS.shell_open(PLAY_STORE_URL))
	hbox.add_child(play_btn)


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
	title.text = "Get the Mobile App!"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var msg := Label.new()
	msg.text = "Take Such Moon Launch with you!\nPlay anywhere, climb the leaderboards,\nand earn Moonrocks on iOS & Android."
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var ios_btn := Button.new()
	ios_btn.text = "App Store"
	ios_btn.custom_minimum_size = Vector2(130, 36)
	ios_btn.add_theme_font_size_override("font_size", 16)
	ios_btn.pressed.connect(func(): OS.shell_open(APP_STORE_URL))
	btn_row.add_child(ios_btn)

	var play_btn := Button.new()
	play_btn.text = "Google Play"
	play_btn.custom_minimum_size = Vector2(130, 36)
	play_btn.add_theme_font_size_override("font_size", 16)
	play_btn.pressed.connect(func(): OS.shell_open(PLAY_STORE_URL))
	btn_row.add_child(play_btn)

	var close := Button.new()
	close.text = "Continue Playing"
	close.custom_minimum_size = Vector2(150, 32)
	close.add_theme_font_size_override("font_size", 14)
	close.flat = true
	close.pressed.connect(func():
		overlay.queue_free()
		on_close.call()
	)
	vbox.add_child(close)
