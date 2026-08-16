class_name EntitlementClient
extends RefCounted
## Request builder + response parser for the App Platform IAP/entitlement RPCs,
## plus a thin async wrapper over PlatformSession.
##
## The static funcs are pure (Dictionary in / Dictionary or StringName out) and
## mirror the deployed server contract in server/nakama/src/platform.ts:
##   - moonParseIapRequest        -> build_validate_iap_request / validate_iap_request
##   - moonRpcValidateIap result  -> validate_iap_response / parse_validate_iap_response
##   - moonRpcEntitlements result -> validate_entitlements_response / parse_entitlements_response
## Validators return the first offending field as a StringName (&"" == clean),
## matching the NakamaRoomBroker.validate_descriptor error-code convention.

const RPC_VALIDATE_IAP := "app_platform_validate_iap"
const RPC_ENTITLEMENTS := "app_platform_entitlements"

const CONTRACT_VERSION := 1

const PROVIDERS := ["apple", "google"]
const OPERATIONS := ["GRANT", "REVOKE", "REINSTATE"]
const CURRENCY_KEY_MOONROCKS := "moonrocks"

## moonParseIapRequest bounds.
const PRODUCT_ID_PATTERN := "^[A-Za-z0-9_.-]{1,256}$"
const RECEIPT_MIN_LENGTH := 8
const RECEIPT_MAX_LENGTH := 262144

## moonParseEntitlementEvent key rule: ^[a-z][a-z0-9_.-]*$, max 128 chars.
const ENTITLEMENT_KEY_PATTERN := "^[a-z][a-z0-9_.-]{0,127}$"
const TRANSACTION_ID_MAX_LENGTH := 512
const IGNORED_REASON_MAX_LENGTH := 128
const RETRY_AFTER_MAX_MS := 600_000

const IAP_RESPONSE_KEYS := [
	"amount",
	"applied",
	"currency_key",
	"duplicate",
	"entitlement_key",
	"ignored_reason",
	"ledger_sequence",
	"operation",
	"product_id",
	"projection_state",
	"provider",
	"retry_after_ms",
	"seen_before",
	"transaction_id",
	"verified",
]

const ENTITLEMENTS_RESPONSE_KEYS := ["capabilities", "contract_version"]
const CAPABILITY_KEYS := ["active", "expires_at", "key", "last_sequence"]

var _session_service: Variant = null


## ==========================================================================
##  Async wrapper over PlatformSession
## ==========================================================================

## The caller supplies the session service (normally a PlatformSession).
## While AppPlatformFeatures.NAKAMA_ENABLED stays closed every call below
## resolves to a refusal, because PlatformSession itself refuses.
func configure(session_service: Variant) -> void:
	_session_service = session_service


func is_configured() -> bool:
	return (
		_session_service != null
		and _session_service.has_method("ensure_session")
		and _session_service.has_method("call_rpc")
	)


## Validate a native purchase server-side. Returns {"ok": bool,
## "reason": StringName, "response": Dictionary}; "response" is only present
## (and already shape-validated) when ok.
func validate_iap(provider: String, product_id: String, receipt: String) -> Dictionary:
	var request := build_validate_iap_request(provider, product_id, receipt)
	if request.is_empty():
		return {"ok": false, "reason": &"invalid_request"}
	var rpc := await _authenticated_rpc(RPC_VALIDATE_IAP, request)
	if not rpc.get("ok", false):
		return rpc
	var response := parse_validate_iap_response(rpc.get("result"))
	if response.is_empty():
		return {"ok": false, "reason": &"malformed_response"}
	return {"ok": true, "reason": &"", "response": response}


## Fetch the active capability projection. Returns {"ok": bool,
## "reason": StringName, "response": Dictionary} with the same conventions.
func fetch_entitlements() -> Dictionary:
	var rpc := await _authenticated_rpc(RPC_ENTITLEMENTS, {})
	if not rpc.get("ok", false):
		return rpc
	var response := parse_entitlements_response(rpc.get("result"))
	if response.is_empty():
		return {"ok": false, "reason": &"malformed_response"}
	return {"ok": true, "reason": &"", "response": response}


func _authenticated_rpc(rpc_id: String, payload: Dictionary) -> Dictionary:
	if not is_configured():
		return {"ok": false, "reason": &"not_configured"}
	var session_outcome: Dictionary = await _session_service.ensure_session()
	if not session_outcome.get("ok", false):
		return {
			"ok": false,
			"reason": session_outcome.get("reason", &"session_unavailable"),
		}
	var rpc: Dictionary = await _session_service.call_rpc(rpc_id, payload)
	if not rpc.get("ok", false):
		var reason: StringName = rpc.get("reason", &"transport_failed")
		if reason == &"rpc_rejected":
			reason = map_rpc_failure(
				int(rpc.get("status_code", -1)),
				int(rpc.get("grpc_status_code", -1))
			)
		return {"ok": false, "reason": reason}
	return rpc


## ==========================================================================
##  Pure request builders / validators (no network, gdUnit-testable)
## ==========================================================================

## Build the app_platform_validate_iap payload; {} when any field would be
## rejected server-side (moonParseIapRequest).
static func build_validate_iap_request(
	provider: String,
	product_id: String,
	receipt: String
) -> Dictionary:
	var request := {
		"provider": provider,
		"product_id": product_id,
		"receipt": receipt,
	}
	if validate_iap_request(request) != &"":
		return {}
	return request


static func validate_iap_request(value: Dictionary) -> StringName:
	if value.size() != 3:
		return &"shape"
	for key in ["provider", "product_id", "receipt"]:
		if not value.has(key):
			return &"shape"
	if not value["provider"] is String or value["provider"] not in PROVIDERS:
		return &"provider"
	if not value["product_id"] is String or not _matches(
		PRODUCT_ID_PATTERN,
		value["product_id"]
	):
		return &"product_id"
	if not value["receipt"] is String:
		return &"receipt"
	var receipt_length: int = str(value["receipt"]).length()
	if receipt_length < RECEIPT_MIN_LENGTH or receipt_length > RECEIPT_MAX_LENGTH:
		return &"receipt"
	return &""


## Strict shape check of a moonRpcValidateIap response.
static func validate_iap_response(value: Dictionary) -> StringName:
	if value.size() != IAP_RESPONSE_KEYS.size():
		return &"shape"
	for key in IAP_RESPONSE_KEYS:
		if not value.has(key):
			return &"shape"
	if not value["verified"] is bool or value["verified"] != true:
		return &"verified"
	if not value["provider"] is String or value["provider"] not in PROVIDERS:
		return &"provider"
	if not value["product_id"] is String or not _matches(
		PRODUCT_ID_PATTERN,
		value["product_id"]
	):
		return &"product_id"
	if (
		not value["transaction_id"] is String
		or value["transaction_id"] == ""
		or str(value["transaction_id"]).length() > TRANSACTION_ID_MAX_LENGTH
	):
		return &"transaction_id"
	if not value["operation"] is String or value["operation"] not in OPERATIONS:
		return &"operation"
	if not value["seen_before"] is bool:
		return &"seen_before"
	if not value["duplicate"] is bool:
		return &"duplicate"
	if not value["applied"] is bool:
		return &"applied"
	var ignored: Variant = value["ignored_reason"]
	if ignored != null and (
		not ignored is String
		or ignored == ""
		or str(ignored).length() > IGNORED_REASON_MAX_LENGTH
	):
		return &"ignored_reason"
	# The ledger guarantees applied XOR ignored_reason (moonRpcValidateIap
	# rejects anything else before returning).
	if value["applied"] == true and ignored != null:
		return &"ignored_reason"
	if value["applied"] == false and ignored == null:
		return &"ignored_reason"
	if not _is_json_integer(value["ledger_sequence"]) or int(value["ledger_sequence"]) < 1:
		return &"ledger_sequence"
	var entitlement_key: Variant = value["entitlement_key"]
	if entitlement_key != null and (
		not entitlement_key is String
		or not _matches(ENTITLEMENT_KEY_PATTERN, entitlement_key)
	):
		return &"entitlement_key"
	var currency_key: Variant = value["currency_key"]
	if currency_key != null and currency_key != CURRENCY_KEY_MOONROCKS:
		return &"currency_key"
	# Exactly one ledger family per event (moonBindLedgerEvent).
	if (entitlement_key == null) == (currency_key == null):
		return &"entitlement_key"
	var amount: Variant = value["amount"]
	if currency_key == null:
		if amount != null:
			return &"amount"
	elif not _is_json_integer(amount) or int(amount) < 1:
		return &"amount"
	if value["projection_state"] != "pending":
		return &"projection_state"
	if (
		not _is_json_integer(value["retry_after_ms"])
		or int(value["retry_after_ms"]) < 0
		or int(value["retry_after_ms"]) > RETRY_AFTER_MAX_MS
	):
		return &"retry_after_ms"
	return &""


static func parse_validate_iap_response(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	if validate_iap_response(value) != &"":
		return {}
	return (value as Dictionary).duplicate(true)


## Strict shape check of a moonRpcEntitlements response.
static func validate_entitlements_response(value: Dictionary) -> StringName:
	if value.size() != ENTITLEMENTS_RESPONSE_KEYS.size():
		return &"shape"
	for key in ENTITLEMENTS_RESPONSE_KEYS:
		if not value.has(key):
			return &"shape"
	if (
		not _is_json_integer(value["contract_version"])
		or int(value["contract_version"]) != CONTRACT_VERSION
	):
		return &"contract_version"
	if not value["capabilities"] is Array:
		return &"capabilities"
	for capability in value["capabilities"]:
		if not capability is Dictionary:
			return &"capability_shape"
		if capability.size() != CAPABILITY_KEYS.size():
			return &"capability_shape"
		for key in CAPABILITY_KEYS:
			if not capability.has(key):
				return &"capability_shape"
		if not capability["key"] is String or not _matches(
			ENTITLEMENT_KEY_PATTERN,
			capability["key"]
		):
			return &"key"
		# The RPC only ever projects active capabilities.
		if not capability["active"] is bool or capability["active"] != true:
			return &"active"
		# Postgres emits expires_at::text ("YYYY-MM-DD HH:MM:SS+TZ"), not
		# strict ISO 8601 — validate the date prefix, not a full parse.
		var expires: Variant = capability["expires_at"]
		if expires != null and (
			not expires is String
			or not _matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ]", expires)
			or str(expires).length() > 40
		):
			return &"expires_at"
		# last_sequence is cast ::text server-side: a digit string.
		if not capability["last_sequence"] is String or not _matches(
			"^[0-9]{1,19}$",
			capability["last_sequence"]
		):
			return &"last_sequence"
	return &""


static func parse_entitlements_response(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	if validate_entitlements_response(value) != &"":
		return {}
	return (value as Dictionary).duplicate(true)


## Map an RPC-level rejection onto a client action. Nakama surfaces the gRPC
## code when present and the HTTP status otherwise.
static func map_rpc_failure(status_code: int, grpc_code: int) -> StringName:
	match grpc_code:
		16:
			return &"unauthenticated"
		3:
			return &"invalid_request"
		9:
			return &"precondition_failed"
		13:
			return &"server_error"
		14:
			return &"retryable"
	match status_code:
		401, 403:
			return &"unauthenticated"
		400:
			return &"invalid_request"
		500:
			return &"server_error"
		502, 503, 504:
			return &"retryable"
	return &"unknown"


## Reduce a (validated) validate_iap response to local reconcile actions.
## Entitlements are idempotent projections: duplicates still converge local
## state. Currency is not: only a first-time applied event may credit, or a
## replayed receipt would mint moonrocks on every retry.
static func reconcile_actions(response: Dictionary) -> Dictionary:
	if validate_iap_response(response) != &"":
		return {}
	var actions := {
		"product_id": str(response["product_id"]),
		"operation": str(response["operation"]),
		"grant_entitlement": "",
		"revoke_entitlement": "",
		"currency_key": "",
		"credit_amount": 0,
	}
	var converged: bool = response["applied"] == true or response["duplicate"] == true
	if response["entitlement_key"] is String:
		if not converged:
			return actions
		if response["operation"] == "REVOKE":
			actions["revoke_entitlement"] = str(response["entitlement_key"])
		else:
			actions["grant_entitlement"] = str(response["entitlement_key"])
	elif (
		response["currency_key"] is String
		and response["operation"] != "REVOKE"
		and response["applied"] == true
		and response["duplicate"] == false
	):
		actions["currency_key"] = str(response["currency_key"])
		actions["credit_amount"] = int(response["amount"])
	return actions


## ==========================================================================
##  Internal
## ==========================================================================

static func _matches(pattern_text: String, value: String) -> bool:
	var pattern := RegEx.new()
	return pattern.compile(pattern_text) == OK and pattern.search(value) != null


static func _is_json_integer(value: Variant) -> bool:
	return (
		value is int
		or (
			value is float
			and is_finite(value)
			and value == floor(value)
		)
	)
