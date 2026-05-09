extends Node
## IAPManager — cross-platform In-App Purchase wrapper.
## Autoloaded singleton. Mirrors AdManager / PlayGamesManager patterns.
##
## v1 supports three products:
##   - remove_ads      Non-consumable, $1.99 — disables banner + nag ads forever
##   - moonrocks_10k   Consumable,     $1.99 — credits 10,000 Moonrocks
##   - moonrocks_50k   Consumable,     $7.99 — credits 50,000 Moonrocks (whale)
##
## Plugin: poing-studios godot-iap-plugin (or equivalent). Feature-detected at
## runtime so this autoload is safe to ship before the native plugin is wired —
## every public method becomes a no-op on platforms without IAP support.
##
## Web / desktop: IAP is unsupported. Buttons should hide via is_available().

signal purchase_completed(product_id: String, success: bool)
signal restore_completed(restored_ids: Array)

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

var _plugin = null
var _initialized: bool = false


func _ready() -> void:
	# Only attempt to initialize on platforms with a real IAP layer.
	if not _platform_supports_iap():
		return
	# Feature-detect the plugin without hard-binding to its class names.
	# Replace this block when the actual plugin is installed; for now we leave
	# the no-op stub in place so the build doesn't break.
	if not _has_plugin():
		return
	_init_plugin()


## Returns true if this platform can perform real-money purchases.
## Web/desktop should hide IAP buttons.
func is_available() -> bool:
	return _initialized


## Begin a purchase flow for one of the PRODUCT_IDS.
## Always emits purchase_completed when done; success=false on failure or unsupported.
func purchase(product_id: String) -> void:
	Telemetry.log_event(Telemetry.EVENT_IAP_INITIATED, {"product_id": product_id})
	if not is_available():
		purchase_completed.emit(product_id, false)
		return
	# Plugin call goes here when wired:
	#   _plugin.purchase(product_id)
	# For the v1-pre-plugin stub, fail gracefully.
	purchase_completed.emit(product_id, false)


## Re-apply previously-bought non-consumables (required by Apple + Google).
func restore_purchases() -> void:
	if not is_available():
		restore_completed.emit([])
		return
	# Plugin call:
	#   _plugin.queryPurchases()
	restore_completed.emit([])


## Return a localized price string from the store, or a fallback dollar amount.
func get_price(product_id: String) -> String:
	# Plugin should expose .get_price(product_id) once wired; for now use fallback.
	return PRODUCT_FALLBACK_PRICES.get(product_id, "")


## Apply the effect of a successful purchase. Called by the plugin signal handler.
## Public so test harnesses can drive it without the native plugin.
func apply_purchase(product_id: String) -> void:
	match product_id:
		PRODUCT_REMOVE_ADS:
			AdManager.remove_ads()
		PRODUCT_MOONROCKS_10K, PRODUCT_MOONROCKS_50K:
			var amount: int = MOONROCK_REWARDS.get(product_id, 0)
			if amount > 0:
				globalvar.add_crypto(amount)
				globalvar.save_game()


# --- Internal ---

func _platform_supports_iap() -> bool:
	var name := OS.get_name()
	return name == "Android" or name == "iOS"


func _has_plugin() -> bool:
	# Replace with the real plugin's detection check once installed, e.g.:
	#   return ClassDB.class_exists(&"IAPPlugin") or Engine.has_singleton("IAP")
	return false


func _init_plugin() -> void:
	# Replace with real plugin init wiring once installed:
	#   _plugin = Engine.get_singleton("IAP")
	#   _plugin.initialize(PRODUCT_IDS)
	#   _plugin.purchase_completed.connect(_on_purchase_completed)
	#   _plugin.restore_completed.connect(_on_restore_completed)
	_initialized = true


func _on_purchase_completed(product_id: String, success: bool) -> void:
	Telemetry.log_event(Telemetry.EVENT_IAP_COMPLETED, {
		"product_id": product_id,
		"success": success,
	})
	if success:
		apply_purchase(product_id)
	purchase_completed.emit(product_id, success)


func _on_restore_completed(restored_ids: Array) -> void:
	for pid in restored_ids:
		apply_purchase(pid)
	restore_completed.emit(restored_ids)
