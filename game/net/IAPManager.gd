extends Node
## IAPManager — cross-platform In-App Purchase wrapper.
## Autoloaded singleton. Mirrors AdManager / PlayGamesManager patterns.
##
## v1 supports three products:
##   - remove_ads      Non-consumable, $1.99 — disables banner + nag ads forever
##   - moonrocks_10k   Consumable,     $1.99 — credits 10,000 Moonrocks
##   - moonrocks_50k   Consumable,     $7.99 — credits 50,000 Moonrocks (whale)
##
## Plugins (installed):
##   Android — godot-sdk-integrations/godot-google-play-billing 3.2.0
##             addons/GodotGooglePlayBilling/ (BillingClient class)
##   iOS     — godot-sdk-integrations/godot-storekit2 v0.2 (Godot 4.6.1 build)
##             ios/plugins/godot-storekit2/ + game/net/StoreKit2Wrapper.gd
##
## Web/desktop: IAP unsupported. is_available() returns false; UI hides buttons.

signal purchase_completed(product_id: String, success: bool)
signal restore_completed(restored_ids: Array)
signal prices_updated  # emitted after the store returns localized prices

# Bundle-prefixed product IDs — must EXACTLY match Play Console + App Store Connect.
const PRODUCT_REMOVE_ADS    := "com.suchsoftware.suchmoonlaunch.remove_ads"
const PRODUCT_MOONROCKS_10K := "com.suchsoftware.suchmoonlaunch.moonrocks_10k"
const PRODUCT_MOONROCKS_50K := "com.suchsoftware.suchmoonlaunch.moonrocks_50k"

const PRODUCT_IDS := [
	PRODUCT_REMOVE_ADS,
	PRODUCT_MOONROCKS_10K,
	PRODUCT_MOONROCKS_50K,
]

# Reward amounts for each consumable.
const MOONROCK_REWARDS := {
	PRODUCT_MOONROCKS_10K: 10_000,
	PRODUCT_MOONROCKS_50K: 50_000,
}

# Display labels (for UI). Real prices come from the store API at runtime.
const PRODUCT_LABELS := {
	PRODUCT_REMOVE_ADS:    "Remove Ads",
	PRODUCT_MOONROCKS_10K: "10,000 Moonrocks",
	PRODUCT_MOONROCKS_50K: "50,000 Moonrocks",
}

const PRODUCT_FALLBACK_PRICES := {
	PRODUCT_REMOVE_ADS:    "$1.99",
	PRODUCT_MOONROCKS_10K: "$1.99",
	PRODUCT_MOONROCKS_50K: "$7.99",
}

const CONSUMABLE_PRODUCTS := [PRODUCT_MOONROCKS_10K, PRODUCT_MOONROCKS_50K]

# Localized prices fetched from the platform store. Falls back to PRODUCT_FALLBACK_PRICES.
var _live_prices: Dictionary = {}

# Plugin handles
var _android_billing  # BillingClient instance (Android only)
var _ios_storekit  # GDScriptStoreKit2 wrapper (iOS only)

var _initialized: bool = false

## Force IAP UI to render on desktop with fallback prices — ONLY for
## capturing App Store / Play Store screenshots from the Godot editor.
## Always commit as `false`. With this on, clicking a buy button just
## emits purchase_completed(id, false) — no real purchase fires.
const DEBUG_FAKE_IAP_FOR_SCREENSHOTS := false


func _ready() -> void:
	match OS.get_name():
		"Android":
			_init_android()
			# If GPB plugin isn't present (or products aren't registered yet
			# in Play Console), fall back to fake-available for screenshots.
			if not _initialized and DEBUG_FAKE_IAP_FOR_SCREENSHOTS and OS.is_debug_build():
				_initialized = true
		"iOS":
			_init_ios()
			# If the StoreKit2 plugin didn't load (e.g. running in iOS
			# Simulator — the v0.2 release ships device-only xcframework),
			# optionally fake "available" so the shop UI still renders for
			# screenshot capture on the simulator.
			if not _initialized and DEBUG_FAKE_IAP_FOR_SCREENSHOTS and OS.is_debug_build():
				_initialized = true
		_:
			# Desktop / web — no IAP backend. Optionally fake "available"
			# so the shop UI renders for screenshot capture.
			if DEBUG_FAKE_IAP_FOR_SCREENSHOTS and OS.is_debug_build():
				_initialized = true


## Returns true once the platform-native billing layer has finished its
## product fetch. Useful for showing fallback prices vs live prices.
## DO NOT use this to decide whether to render IAP UI — that should
## happen on every supported platform regardless of init state, or Apple
## review will mark the IAPs as missing (see is_supported below).
func is_available() -> bool:
	return _initialized


## Returns true on platforms that support real-money IAP, regardless of
## whether the native billing layer has finished initializing yet. UI
## should use this to decide whether to render IAP buttons. The
## purchase() call itself is safe to invoke before _initialized — it
## just emits a failed purchase_completed signal, so taps before init
## complete are no-ops (acceptable UX vs. hidden IAPs which Apple flags).
func is_supported() -> bool:
	var p := OS.get_name()
	return p == "iOS" or p == "Android"


## Begin a purchase flow. Always emits purchase_completed when done.
func purchase(product_id: String) -> void:
	Telemetry.log_event(Telemetry.EVENT_IAP_INITIATED, {"product_id": product_id})
	if not _initialized:
		purchase_completed.emit(product_id, false)
		return
	if _android_billing:
		_android_billing.purchase(product_id)
		# Result arrives via on_purchase_updated → _on_android_purchase_updated.
		return
	if _ios_storekit:
		_ios_storekit.purchase_product(product_id, 1)
		# Result arrives via transaction_state_changed → _on_ios_transaction.
		return
	purchase_completed.emit(product_id, false)


## Re-apply previously-bought non-consumables. Required by Apple + Google.
func restore_purchases() -> void:
	if not _initialized:
		restore_completed.emit([])
		return
	if _android_billing:
		# Re-query purchases. Restored items will route through _on_android_purchases_queried.
		_android_billing.query_purchases(_android_billing.ProductType.INAPP)
		return
	if _ios_storekit:
		_ios_storekit.sync()
		# Apple's sync re-emits PURCHASED/RESTORED transactions for owned non-consumables.
		return
	restore_completed.emit([])


## Localized price string from the store, or fallback dollar amount if not yet fetched.
func get_price(product_id: String) -> String:
	if _live_prices.has(product_id):
		return str(_live_prices[product_id])
	return PRODUCT_FALLBACK_PRICES.get(product_id, "")


## Apply a successful purchase's effect. Public so test harnesses can drive it.
func apply_purchase(product_id: String) -> void:
	match product_id:
		PRODUCT_REMOVE_ADS:
			AdManager.remove_ads()
		PRODUCT_MOONROCKS_10K, PRODUCT_MOONROCKS_50K:
			var amount: int = MOONROCK_REWARDS.get(product_id, 0)
			if amount > 0:
				globalvar.add_crypto(amount)
				globalvar.save_game()


# ============================================================================
#  Android — Google Play Billing
# ============================================================================

func _init_android() -> void:
	if not Engine.has_singleton("GodotGooglePlayBilling"):
		# Plugin enabled but native singleton not present (likely editor / dev build).
		return
	var BillingClientScript = load("res://addons/GodotGooglePlayBilling/BillingClient.gd")
	if BillingClientScript == null:
		return
	_android_billing = BillingClientScript.new()
	# We're a SceneTree singleton (autoload); attach so the BillingClient is in-tree.
	add_child(_android_billing)
	_android_billing.connected.connect(_on_android_connected)
	_android_billing.connect_error.connect(_on_android_connect_error)
	_android_billing.query_product_details_response.connect(_on_android_product_details)
	_android_billing.query_purchases_response.connect(_on_android_purchases_queried)
	_android_billing.on_purchase_updated.connect(_on_android_purchase_updated)
	_android_billing.start_connection()
	_initialized = true


func _on_android_connected() -> void:
	# Fetch prices and existing non-consumable purchases on connect.
	_android_billing.query_product_details(PackedStringArray(PRODUCT_IDS), _android_billing.ProductType.INAPP)
	_android_billing.query_purchases(_android_billing.ProductType.INAPP)


func _on_android_connect_error(code: int, msg: String) -> void:
	push_warning("IAPManager (Android): connect_error %d — %s" % [code, msg])
	Telemetry.record_error("IAPManager Android connect: %d %s" % [code, msg])


func _on_android_product_details(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) != _android_billing.BillingResponseCode.OK:
		return
	for product in response.get("product_details", []):
		var pid: String = str(product.get("product_id", ""))
		var price_text := _android_extract_price(product)
		if pid != "" and price_text != "":
			_live_prices[pid] = price_text
	prices_updated.emit()


func _android_extract_price(product: Dictionary) -> String:
	# Pull the formatted_price from the first one_time_purchase_offer_details entry.
	var offers = product.get("one_time_purchase_offer_details_list", [])
	for offer in offers:
		var formatted := str(offer.get("formatted_price", ""))
		if formatted != "":
			return formatted
	return ""


func _on_android_purchases_queried(response: Dictionary) -> void:
	# Existing non-consumable purchases on connect / on Restore Purchases.
	if int(response.get("response_code", -1)) != _android_billing.BillingResponseCode.OK:
		restore_completed.emit([])
		return
	var restored: Array = []
	for purchase in response.get("purchases", []):
		_handle_android_purchase(purchase, true)
		for pid in purchase.get("product_ids", []):
			restored.append(str(pid))
	restore_completed.emit(restored)


func _on_android_purchase_updated(response: Dictionary) -> void:
	# Live purchase result (after the user taps Buy and Google completes).
	var ok: bool = int(response.get("response_code", -1)) == int(_android_billing.BillingResponseCode.OK)
	for purchase in response.get("purchases", []):
		_handle_android_purchase(purchase, false)
	if not ok:
		# Surface the failure for whatever product was attempted.
		# response.purchases may be empty on cancel; emit a generic failure so callers can recover.
		for pid in PRODUCT_IDS:
			# We don't know which one without context; emit a single generic failure.
			pass
		# Emit a single failure with empty id; callers using CONNECT_ONE_SHOT will hear it.
		purchase_completed.emit("", false)


func _handle_android_purchase(purchase: Dictionary, _is_query: bool) -> void:
	var state := int(purchase.get("purchase_state", 0))
	if state != _android_billing.PurchaseState.PURCHASED:
		return
	var token := str(purchase.get("purchase_token", ""))
	for pid_variant in purchase.get("product_ids", []):
		var pid := str(pid_variant)
		apply_purchase(pid)
		if pid in CONSUMABLE_PRODUCTS:
			# Consume so the player can re-buy.
			if token != "":
				_android_billing.consume_purchase(token)
		else:
			# Non-consumable: acknowledge if not already.
			if not bool(purchase.get("is_acknowledged", false)) and token != "":
				_android_billing.acknowledge_purchase(token)
		purchase_completed.emit(pid, true)
		Telemetry.log_event(Telemetry.EVENT_IAP_COMPLETED, {
			"product_id": pid,
			"success": true,
		})


# ============================================================================
#  iOS — StoreKit 2
# ============================================================================

func _init_ios() -> void:
	if not ClassDB.class_exists("GodotStoreKit2"):
		return
	var WrapperScript = load("res://game/net/StoreKit2Wrapper.gd")
	if WrapperScript == null:
		return
	_ios_storekit = WrapperScript.new()
	if _ios_storekit._store_kit == null:
		# class_exists returned true but instantiation failed.
		return
	_ios_storekit.transaction_state_changed.connect(_on_ios_transaction)
	_ios_storekit.product_info_received.connect(_on_ios_product_info)
	_ios_storekit.synchronized.connect(_on_ios_synchronized)
	_initialized = true
	# Fetch prices for all products.
	for pid in PRODUCT_IDS:
		_ios_storekit.request_product_info(pid)


func _on_ios_product_info(info) -> void:
	# info is GDScriptStoreKit2.ProductInfo
	if str(info.error) != "":
		push_warning("IAPManager (iOS): product info error — %s" % info.error)
		return
	var pid := str(info.product_id)
	var localized := str(info.localized_price)
	if pid != "" and localized != "":
		_live_prices[pid] = localized
	# If a non-consumable is already purchased on this device, apply the effect.
	if info.is_purchased and pid not in CONSUMABLE_PRODUCTS:
		apply_purchase(pid)
	prices_updated.emit()


func _on_ios_transaction(transaction) -> void:
	# transaction is GDScriptStoreKit2.TransactionData
	if str(transaction.error) != "":
		Telemetry.record_error("IAPManager iOS transaction error: %s" % transaction.error)
		purchase_completed.emit("", false)
		return
	var pid := str(transaction.product_id)
	# StoreKit2 TransactionState: PURCHASED=4, RESTORED=5
	var state: int = int(transaction.transaction_state)
	var purchased_or_restored: bool = state == int(_ios_storekit.TransactionState.PURCHASED) \
			or state == int(_ios_storekit.TransactionState.RESTORED)
	if purchased_or_restored:
		apply_purchase(pid)
		purchase_completed.emit(pid, true)
		Telemetry.log_event(Telemetry.EVENT_IAP_COMPLETED, {
			"product_id": pid,
			"success": true,
		})
	elif state == _ios_storekit.TransactionState.CANCELED:
		purchase_completed.emit(pid, false)
	else:
		# PENDING / DEFERRED / FAILED / REFUNDED / EXPIRED — surface to caller.
		purchase_completed.emit(pid, false)


func _on_ios_synchronized() -> void:
	# After sync, currently-owned non-consumables re-emit transaction_state_changed
	# with state RESTORED. We collect them in apply_purchase / _on_ios_transaction.
	# Emit restore_completed with the keys we've already applied via product_info.
	var restored: Array = []
	for pid in _live_prices.keys():
		if pid not in CONSUMABLE_PRODUCTS and globalvar.is_ads_removed():
			restored.append(pid)
	restore_completed.emit(restored)
