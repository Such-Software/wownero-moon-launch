class_name EntitlementClientTest
extends GdUnitTestSuite
## Phase-2 client wiring: pure request builders and response parsers for
## app_platform_validate_iap / app_platform_entitlements, with no network.
## Shapes mirror server/nakama/src/platform.ts (moonParseIapRequest,
## moonRpcValidateIap, moonRpcEntitlements).

const Client = preload("res://game/platform/EntitlementClient.gd")

const RECEIPT := "receipt-blob-0123456789"
const REMOVE_ADS := "com.suchsoftware.suchmoonlaunch.remove_ads"
const MOONROCKS_10K := "com.suchsoftware.suchmoonlaunch.moonrocks_10k"


static func entitlement_response(overrides: Dictionary = {}) -> Dictionary:
	var response := {
		"verified": true,
		"provider": "apple",
		"product_id": REMOVE_ADS,
		"transaction_id": "200000123456789",
		"operation": "GRANT",
		"seen_before": false,
		"duplicate": false,
		"applied": true,
		"ignored_reason": null,
		"ledger_sequence": 7,
		"entitlement_key": "race.unlimited",
		"currency_key": null,
		"amount": null,
		"projection_state": "pending",
		"retry_after_ms": 750,
	}
	for key in overrides:
		response[key] = overrides[key]
	return response


static func currency_response(overrides: Dictionary = {}) -> Dictionary:
	var response := entitlement_response({
		"provider": "google",
		"product_id": MOONROCKS_10K,
		"entitlement_key": null,
		"currency_key": "moonrocks",
		"amount": 10000,
	})
	for key in overrides:
		response[key] = overrides[key]
	return response


class FakeSession extends RefCounted:
	var ensure_outcome := {"ok": true, "reason": &""}
	var rpc_outcome := {}
	var ensure_calls := 0
	var rpc_calls: Array = []

	func ensure_session() -> Dictionary:
		ensure_calls += 1
		return ensure_outcome

	func call_rpc(rpc_id: String, payload: Dictionary) -> Dictionary:
		rpc_calls.append([rpc_id, payload])
		return rpc_outcome


# ==========================================================================
#  REQUEST BUILDER — mirrors moonParseIapRequest
# ==========================================================================

func test_build_validate_iap_request_round_trips() -> void:
	var request := Client.build_validate_iap_request("apple", REMOVE_ADS, RECEIPT)
	assert_dict(request).is_equal({
		"provider": "apple",
		"product_id": REMOVE_ADS,
		"receipt": RECEIPT,
	})
	assert_str(str(Client.validate_iap_request(request))).is_empty()


func test_build_validate_iap_request_fails_closed_on_bad_input() -> void:
	assert_dict(Client.build_validate_iap_request("amazon", REMOVE_ADS, RECEIPT)) \
		.is_empty()
	assert_dict(Client.build_validate_iap_request("apple", "", RECEIPT)).is_empty()
	assert_dict(Client.build_validate_iap_request("apple", REMOVE_ADS, "short")) \
		.is_empty()


func test_validate_iap_request_maps_each_field_error() -> void:
	assert_str(str(Client.validate_iap_request({}))).is_equal("shape")
	var extra := Client.build_validate_iap_request("apple", REMOVE_ADS, RECEIPT)
	extra["debug"] = true
	assert_str(str(Client.validate_iap_request(extra))).is_equal("shape")
	assert_str(str(Client.validate_iap_request({
		"provider": "amazon", "product_id": REMOVE_ADS, "receipt": RECEIPT,
	}))).is_equal("provider")
	assert_str(str(Client.validate_iap_request({
		"provider": "google", "product_id": "spaced out!", "receipt": RECEIPT,
	}))).is_equal("product_id")
	assert_str(str(Client.validate_iap_request({
		"provider": "google", "product_id": "p".repeat(257), "receipt": RECEIPT,
	}))).is_equal("product_id")
	assert_str(str(Client.validate_iap_request({
		"provider": "google", "product_id": REMOVE_ADS, "receipt": "1234567",
	}))).is_equal("receipt")
	assert_str(str(Client.validate_iap_request({
		"provider": "google",
		"product_id": REMOVE_ADS,
		"receipt": "r".repeat(262145),
	}))).is_equal("receipt")


# ==========================================================================
#  VALIDATE-IAP RESPONSE PARSER — mirrors moonRpcValidateIap
# ==========================================================================

func test_iap_response_accepts_entitlement_and_currency_shapes() -> void:
	assert_str(str(Client.validate_iap_response(entitlement_response()))).is_empty()
	assert_str(str(Client.validate_iap_response(currency_response()))).is_empty()
	assert_str(str(Client.validate_iap_response(entitlement_response({
		"applied": false,
		"duplicate": true,
		"ignored_reason": "duplicate_event",
	})))).is_empty()


func test_iap_response_rejects_shape_drift() -> void:
	var extra := entitlement_response()
	extra["surprise"] = true
	assert_str(str(Client.validate_iap_response(extra))).is_equal("shape")
	var missing := entitlement_response()
	missing.erase("ledger_sequence")
	assert_str(str(Client.validate_iap_response(missing))).is_equal("shape")
	assert_dict(Client.parse_validate_iap_response("not a dictionary")).is_empty()
	assert_dict(Client.parse_validate_iap_response(null)).is_empty()


func test_iap_response_maps_each_field_error() -> void:
	var cases := {
		"verified": entitlement_response({"verified": false}),
		"provider": entitlement_response({"provider": "amazon"}),
		"product_id": entitlement_response({"product_id": "spaced out!"}),
		"transaction_id": entitlement_response({"transaction_id": ""}),
		"operation": entitlement_response({"operation": "UPGRADE"}),
		"seen_before": entitlement_response({"seen_before": 1}),
		"duplicate": entitlement_response({"duplicate": "no"}),
		"applied": entitlement_response({"applied": "yes"}),
		"ledger_sequence": entitlement_response({"ledger_sequence": 0}),
		"entitlement_key": entitlement_response({"entitlement_key": "Race"}),
		"currency_key": currency_response({"currency_key": "gems"}),
		"projection_state": entitlement_response({"projection_state": "done"}),
		"retry_after_ms": entitlement_response({"retry_after_ms": -1}),
	}
	for expected in cases:
		assert_str(str(Client.validate_iap_response(cases[expected]))) \
			.is_equal(str(expected))


func test_iap_response_enforces_applied_ignored_reason_consistency() -> void:
	assert_str(str(Client.validate_iap_response(entitlement_response({
		"applied": true,
		"ignored_reason": "should_be_null",
	})))).is_equal("ignored_reason")
	assert_str(str(Client.validate_iap_response(entitlement_response({
		"applied": false,
		"duplicate": true,
	})))).is_equal("ignored_reason")


func test_iap_response_requires_exactly_one_ledger_family() -> void:
	assert_str(str(Client.validate_iap_response(entitlement_response({
		"entitlement_key": null,
	})))).is_equal("entitlement_key")
	assert_str(str(Client.validate_iap_response(entitlement_response({
		"currency_key": "moonrocks",
	})))).is_equal("entitlement_key")
	assert_str(str(Client.validate_iap_response(currency_response({
		"amount": null,
	})))).is_equal("amount")
	assert_str(str(Client.validate_iap_response(currency_response({
		"amount": 0,
	})))).is_equal("amount")
	assert_str(str(Client.validate_iap_response(entitlement_response({
		"amount": 500,
	})))).is_equal("amount")


# ==========================================================================
#  ENTITLEMENTS RESPONSE PARSER — mirrors moonRpcEntitlements
# ==========================================================================

func test_entitlements_response_accepts_server_shape() -> void:
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 1,
		"capabilities": [],
	}))).is_empty()
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 1,
		"capabilities": [
			{
				"key": "race.unlimited",
				"active": true,
				"expires_at": null,
				"last_sequence": "42",
			},
			{
				"key": "season.pass",
				"active": true,
				"expires_at": "2027-01-01 00:00:00+00",
				"last_sequence": "7",
			},
		],
	}))).is_empty()


func test_entitlements_response_maps_each_field_error() -> void:
	assert_str(str(Client.validate_entitlements_response({}))).is_equal("shape")
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 2, "capabilities": [],
	}))).is_equal("contract_version")
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 1, "capabilities": "none",
	}))).is_equal("capabilities")
	var capability := {
		"key": "race.unlimited",
		"active": true,
		"expires_at": null,
		"last_sequence": "42",
	}
	var extra := capability.duplicate()
	extra["debug"] = true
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 1, "capabilities": [extra],
	}))).is_equal("capability_shape")
	var bad_key := capability.duplicate()
	bad_key["key"] = "Race"
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 1, "capabilities": [bad_key],
	}))).is_equal("key")
	var inactive := capability.duplicate()
	inactive["active"] = false
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 1, "capabilities": [inactive],
	}))).is_equal("active")
	var bad_expiry := capability.duplicate()
	bad_expiry["expires_at"] = "soon"
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 1, "capabilities": [bad_expiry],
	}))).is_equal("expires_at")
	var bad_sequence := capability.duplicate()
	bad_sequence["last_sequence"] = 42
	assert_str(str(Client.validate_entitlements_response({
		"contract_version": 1, "capabilities": [bad_sequence],
	}))).is_equal("last_sequence")


# ==========================================================================
#  RPC ERROR MAPPING
# ==========================================================================

func test_map_rpc_failure_covers_each_contract_error() -> void:
	assert_str(str(Client.map_rpc_failure(-1, 16))).is_equal("unauthenticated")
	assert_str(str(Client.map_rpc_failure(-1, 3))).is_equal("invalid_request")
	assert_str(str(Client.map_rpc_failure(-1, 9))).is_equal("precondition_failed")
	assert_str(str(Client.map_rpc_failure(-1, 13))).is_equal("server_error")
	assert_str(str(Client.map_rpc_failure(-1, 14))).is_equal("retryable")
	assert_str(str(Client.map_rpc_failure(401, -1))).is_equal("unauthenticated")
	assert_str(str(Client.map_rpc_failure(400, -1))).is_equal("invalid_request")
	assert_str(str(Client.map_rpc_failure(503, -1))).is_equal("retryable")
	assert_str(str(Client.map_rpc_failure(500, -1))).is_equal("server_error")
	assert_str(str(Client.map_rpc_failure(-1, -1))).is_equal("unknown")


# ==========================================================================
#  RECONCILE ACTIONS — server response replaces the local grant
# ==========================================================================

func test_reconcile_grants_entitlement_even_on_duplicate() -> void:
	var applied := Client.reconcile_actions(entitlement_response())
	assert_str(str(applied["grant_entitlement"])).is_equal("race.unlimited")
	assert_int(int(applied["credit_amount"])).is_equal(0)
	var duplicate := Client.reconcile_actions(entitlement_response({
		"applied": false,
		"duplicate": true,
		"ignored_reason": "duplicate_event",
	}))
	assert_str(str(duplicate["grant_entitlement"])).is_equal("race.unlimited")


func test_reconcile_revokes_entitlement() -> void:
	var actions := Client.reconcile_actions(entitlement_response({
		"operation": "REVOKE",
	}))
	assert_str(str(actions["revoke_entitlement"])).is_equal("race.unlimited")
	assert_str(str(actions["grant_entitlement"])).is_empty()


func test_reconcile_credits_currency_exactly_once() -> void:
	var applied := Client.reconcile_actions(currency_response())
	assert_str(str(applied["currency_key"])).is_equal("moonrocks")
	assert_int(int(applied["credit_amount"])).is_equal(10000)
	# A replayed receipt is duplicate=true / applied=false: never re-credit.
	var duplicate := Client.reconcile_actions(currency_response({
		"applied": false,
		"duplicate": true,
		"ignored_reason": "duplicate_event",
	}))
	assert_int(int(duplicate["credit_amount"])).is_equal(0)
	assert_str(str(duplicate["currency_key"])).is_empty()


func test_reconcile_fails_closed_on_malformed_response() -> void:
	assert_dict(Client.reconcile_actions({})).is_empty()
	assert_dict(Client.reconcile_actions(entitlement_response({
		"verified": false,
	}))).is_empty()


# ==========================================================================
#  ASYNC WRAPPER — driven through a fake PlatformSession, no network
# ==========================================================================

func test_wrapper_refuses_when_not_configured() -> void:
	var client := Client.new()
	var outcome: Dictionary = await client.validate_iap("apple", REMOVE_ADS, RECEIPT)
	assert_bool(bool(outcome["ok"])).is_false()
	assert_str(str(outcome["reason"])).is_equal("not_configured")


func test_wrapper_rejects_invalid_request_before_any_session_use() -> void:
	var session := FakeSession.new()
	var client := Client.new()
	client.configure(session)
	var outcome: Dictionary = await client.validate_iap("amazon", REMOVE_ADS, RECEIPT)
	assert_str(str(outcome["reason"])).is_equal("invalid_request")
	assert_int(session.ensure_calls).is_equal(0)
	assert_int(session.rpc_calls.size()).is_equal(0)


func test_wrapper_propagates_closed_flag_refusal() -> void:
	var session := FakeSession.new()
	session.ensure_outcome = {"ok": false, "reason": &"nakama_disabled"}
	var client := Client.new()
	client.configure(session)
	var outcome: Dictionary = await client.validate_iap("apple", REMOVE_ADS, RECEIPT)
	assert_bool(bool(outcome["ok"])).is_false()
	assert_str(str(outcome["reason"])).is_equal("nakama_disabled")
	assert_int(session.rpc_calls.size()).is_equal(0)


func test_wrapper_returns_parsed_iap_response() -> void:
	var session := FakeSession.new()
	session.rpc_outcome = {
		"ok": true,
		"reason": &"",
		"result": entitlement_response(),
	}
	var client := Client.new()
	client.configure(session)
	var outcome: Dictionary = await client.validate_iap("apple", REMOVE_ADS, RECEIPT)
	assert_bool(bool(outcome["ok"])).is_true()
	assert_str(str(session.rpc_calls[0][0])).is_equal("app_platform_validate_iap")
	assert_dict(session.rpc_calls[0][1]).is_equal({
		"provider": "apple",
		"product_id": REMOVE_ADS,
		"receipt": RECEIPT,
	})
	assert_str(str(outcome["response"]["entitlement_key"])).is_equal("race.unlimited")


func test_wrapper_maps_rpc_rejection_codes() -> void:
	var session := FakeSession.new()
	session.rpc_outcome = {
		"ok": false,
		"reason": &"rpc_rejected",
		"status_code": 503,
		"grpc_status_code": 14,
	}
	var client := Client.new()
	client.configure(session)
	var outcome: Dictionary = await client.validate_iap("apple", REMOVE_ADS, RECEIPT)
	assert_str(str(outcome["reason"])).is_equal("retryable")


func test_wrapper_rejects_malformed_rpc_result() -> void:
	var session := FakeSession.new()
	session.rpc_outcome = {"ok": true, "reason": &"", "result": {"nope": true}}
	var client := Client.new()
	client.configure(session)
	var outcome: Dictionary = await client.validate_iap("apple", REMOVE_ADS, RECEIPT)
	assert_str(str(outcome["reason"])).is_equal("malformed_response")


func test_wrapper_fetches_entitlements() -> void:
	var session := FakeSession.new()
	session.rpc_outcome = {
		"ok": true,
		"reason": &"",
		"result": {"contract_version": 1, "capabilities": []},
	}
	var client := Client.new()
	client.configure(session)
	var outcome: Dictionary = await client.fetch_entitlements()
	assert_bool(bool(outcome["ok"])).is_true()
	assert_str(str(session.rpc_calls[0][0])).is_equal("app_platform_entitlements")
	assert_array(outcome["response"]["capabilities"]).is_empty()
