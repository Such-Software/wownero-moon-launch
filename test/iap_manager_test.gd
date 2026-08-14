class_name IAPManagerTest
extends GdUnitTestSuite
## Unit tests for IAPManager.gd
## On platforms without the IAP plugin (which is everywhere right now),
## all calls must safely no-op.


func before_test() -> void:
	## Real-money grants mutate the shared globalvar autoload and write the real
	## user://savegame.json, so isolate the money state before every case.
	globalvar.wallet = 0
	globalvar.total_crypto_earned = 0
	globalvar.ads_removed = false
	globalvar.race_unlimited_cached = false
	globalvar.granted_purchase_tokens.clear()


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
	assert_int(IAPManager.OFFER_TO_NATIVE_PRODUCT.size()).is_equal(3)


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


func test_stable_offers_map_to_existing_native_products() -> void:
	assert_str(IAPManager.get_offer_id_for_product(IAPManager.PRODUCT_REMOVE_ADS)).is_equal(
		IAPManager.OFFER_RACE_UNLIMITED
	)
	assert_str(IAPManager.get_offer_id_for_product(IAPManager.PRODUCT_MOONROCKS_10K)).is_equal(
		IAPManager.OFFER_MOONROCKS_10K
	)
	assert_str(IAPManager.get_offer_id_for_product("not-a-product")).is_empty()


func test_invalid_stable_offer_fails_closed() -> void:
	assert_bool(IAPManager.purchase_offer("moonrocks_9999999_v1")).is_false()


func test_remove_ads_purchase_grandfathers_unlimited_races() -> void:
	globalvar.ads_removed = false
	globalvar.race_unlimited_cached = false
	IAPManager.apply_purchase(IAPManager.PRODUCT_REMOVE_ADS)
	assert_bool(globalvar.ads_removed).is_true()
	assert_bool(globalvar.race_unlimited_cached).is_true()


# ==========================================================================
#  REAL-MONEY GRANTS
#  Everything below here credits money. It was almost entirely unasserted:
#  the only prior apply_purchase() test covered the Remove Ads entitlement.
# ==========================================================================

func test_apply_purchase_credits_each_consumable_exactly_its_reward() -> void:
	IAPManager.apply_purchase(IAPManager.PRODUCT_MOONROCKS_10K)
	assert_int(globalvar.wallet).is_equal(10_000)
	IAPManager.apply_purchase(IAPManager.PRODUCT_MOONROCKS_50K)
	assert_int(globalvar.wallet).is_equal(60_000)

func test_apply_purchase_ignores_an_unknown_product_id() -> void:
	IAPManager.apply_purchase("com.suchsoftware.suchmoonlaunch.not_a_product")
	assert_int(globalvar.wallet).is_equal(0)
	assert_bool(globalvar.ads_removed).is_false()

func test_apply_purchase_of_remove_ads_is_idempotent() -> void:
	IAPManager.apply_purchase(IAPManager.PRODUCT_REMOVE_ADS)
	IAPManager.apply_purchase(IAPManager.PRODUCT_REMOVE_ADS)
	assert_bool(globalvar.ads_removed).is_true()
	assert_int(globalvar.wallet).is_equal(0)

func test_purchase_token_is_claimable_only_once() -> void:
	assert_bool(globalvar.claim_purchase_token("tok-1")).is_true()
	assert_bool(globalvar.claim_purchase_token("tok-1")).is_false()
	assert_bool(globalvar.claim_purchase_token("tok-2")).is_true()

func test_replayed_play_query_cannot_double_credit_a_consumable() -> void:
	# Play returns an unconsumed purchase from query_purchases() on every launch
	# and every Restore Purchases tap. Crediting per-replay would mint real money.
	var token := "play-token-abc"
	assert_bool(globalvar.claim_purchase_token(token)).is_true()
	IAPManager.apply_purchase(IAPManager.PRODUCT_MOONROCKS_50K)
	assert_int(globalvar.wallet).is_equal(50_000)
	# Second sighting of the same token must not credit again.
	if globalvar.claim_purchase_token(token):
		IAPManager.apply_purchase(IAPManager.PRODUCT_MOONROCKS_50K)
	assert_int(globalvar.wallet).is_equal(50_000)

func test_granted_token_ledger_stays_bounded() -> void:
	for i in range(globalvar.MAX_GRANTED_TOKENS + 20):
		globalvar.claim_purchase_token("tok-%d" % i)
	assert_int(globalvar.granted_purchase_tokens.size()) \
		.is_less_equal(globalvar.MAX_GRANTED_TOKENS)
