class_name IAPManagerTest
extends GdUnitTestSuite
## Unit tests for IAPManager.gd
## On platforms without the IAP plugin (which is everywhere right now),
## all calls must safely no-op.


# ==========================================================================
#  AVAILABILITY
# ==========================================================================

func test_is_available_returns_false_without_plugin() -> void:
	# Plugin not yet installed → all platforms report unavailable.
	assert_bool(IAPManager.is_available()).is_false()


# ==========================================================================
#  NO-OP SAFETY
# ==========================================================================

func test_purchase_emits_failure_when_unavailable() -> void:
	# Use a Dictionary (reference type) so the lambda can mutate captured state.
	var captured := {"got": false, "id": "", "success": true}
	var on_done := func(pid: String, success: bool):
		captured["got"] = true
		captured["id"] = pid
		captured["success"] = success
	IAPManager.purchase_completed.connect(on_done, CONNECT_ONE_SHOT)
	IAPManager.purchase(IAPManager.PRODUCT_REMOVE_ADS)
	# Emission is synchronous in the stub; safe to assert immediately.
	assert_bool(bool(captured["got"])).is_true()
	assert_str(str(captured["id"])).is_equal(IAPManager.PRODUCT_REMOVE_ADS)
	assert_bool(bool(captured["success"])).is_false()


func test_restore_emits_empty_when_unavailable() -> void:
	var captured := {"got": false}
	var on_done := func(_ids: Array): captured["got"] = true
	IAPManager.restore_completed.connect(on_done, CONNECT_ONE_SHOT)
	IAPManager.restore_purchases()
	assert_bool(bool(captured["got"])).is_true()


# ==========================================================================
#  PRODUCT CATALOG
# ==========================================================================

func test_product_catalog_has_three_entries() -> void:
	assert_int(IAPManager.PRODUCT_IDS.size()).is_equal(3)


func test_product_ids_are_bundle_prefixed() -> void:
	for pid in IAPManager.PRODUCT_IDS:
		assert_str(str(pid)).starts_with("com.suchsoftware.suchmoonlaunch.")


func test_moonrock_rewards_match_consumable_ids() -> void:
	# Both consumables map to a positive amount; the non-consumable does not.
	assert_int(int(IAPManager.MOONROCK_REWARDS.get(IAPManager.PRODUCT_MOONROCKS_10K, 0))).is_equal(10000)
	assert_int(int(IAPManager.MOONROCK_REWARDS.get(IAPManager.PRODUCT_MOONROCKS_50K, 0))).is_equal(50000)
	assert_bool(IAPManager.MOONROCK_REWARDS.has(IAPManager.PRODUCT_REMOVE_ADS)).is_false()


func test_get_price_returns_fallback_when_unavailable() -> void:
	# No store API to query → fallback string.
	assert_str(IAPManager.get_price(IAPManager.PRODUCT_REMOVE_ADS)).is_equal("$1.99")
	assert_str(IAPManager.get_price(IAPManager.PRODUCT_MOONROCKS_50K)).is_equal("$7.99")
