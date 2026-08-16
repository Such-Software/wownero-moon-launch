class_name PlatformSession
extends Node
## Fail-closed App Platform session service (Phase-2 client wiring).
##
## Deliberately NOT registered in [autoload]: every existing autoload activates
## a live surface in _ready(), and this service must stay inert while
## AppPlatformFeatures.NAKAMA_ENABLED is closed. Callers preload the script and
## add an instance to the tree only when a flow actually needs it.
##
## Flow (mirrors server/nakama/src/platform.ts moonBeforeAuthenticateCustom):
##   1. POST to the SUCH-configured IdP ticket endpoint -> {"ticket": "..."}.
##   2. authenticate_custom_async(ticket) via the vendored Nakama SDK — the
##      server consumes the ticket against the IdP and rewrites the account id
##      to the canonical platform identity before Nakama ever sees it.
##   3. call_rpc(...) over the authenticated session.
##
## Every entry point no-ops with a machine-readable reason while the flag is
## closed. Config values and tokens are never logged and never leave this
## class; missing config fails closed, it never falls back to a default host.

const Features = preload("res://game/platform/AppPlatformFeatures.gd")

## ------------------------------------------------------------------------
## Client-side App Platform config surface — the single place these names are
## defined. Env names extend the service declarations in
## config/app-platform-v1.json (which pins SUCH_APP_NAKAMA_ENDPOINT); values
## are read at call time and fail closed to "" when unset.
## ------------------------------------------------------------------------
const ENV_IDP_TICKET_URL := "SUCH_APP_IDP_TICKET_URL"
const ENV_NAKAMA_ENDPOINT := "SUCH_APP_NAKAMA_ENDPOINT"
const ENV_NAKAMA_SERVER_KEY := "SUCH_APP_NAKAMA_SERVER_KEY"

const CONTRACT_VERSION := 1
const APP_ID := "moon_launch"

## moonBeforeAuthenticateCustom accepts an opaque ticket of 16..1024 bytes.
const TICKET_MIN_LENGTH := 16
const TICKET_MAX_LENGTH := 1024

## Endpoint shape: scheme://host[:port] with nothing else (no path, no
## userinfo, no query). Port defaults per scheme when omitted.
const ENDPOINT_PATTERN := "^(https?)://([A-Za-z0-9][A-Za-z0-9.-]{0,253})(:([0-9]{1,5}))?$"

## Widest request the server accepts is the IAP receipt payload
## (moonParseIapRequest: 262144 + 1024 bytes). Responses are far smaller.
const MAX_RPC_PAYLOAD_BYTES := 262144 + 1024
const MAX_RPC_RESPONSE_BYTES := 65536
const MAX_IDP_RESPONSE_BYTES := 8192

var _client: Variant = null
var _session: Variant = null


## Test/DI seam, mirroring NakamaRoomBroker.configure: the caller supplies an
## already authenticated client and session. Never accepts a server key.
func configure(client: Variant, session: Variant) -> void:
	_client = client
	_session = session


func is_authenticated() -> bool:
	return (
		_client != null
		and _session != null
		and _client.has_method("rpc_async")
	)


## Acquire (or reuse) an authenticated Nakama session. Returns
## {"ok": bool, "reason": StringName}; "reason" is empty on success.
func ensure_session() -> Dictionary:
	if not Features.NAKAMA_ENABLED:
		return _refusal(&"nakama_disabled")
	if is_authenticated():
		return {"ok": true, "reason": &""}
	if not config_ready():
		return _refusal(&"config_missing")
	if not is_inside_tree():
		# The IdP ticket POST needs an in-tree HTTPRequest node.
		return _refusal(&"not_in_tree")
	var ticket_outcome: Dictionary = await _acquire_ticket(
		config_value(ENV_IDP_TICKET_URL)
	)
	if not ticket_outcome.get("ok", false):
		return ticket_outcome
	var endpoint := parse_endpoint(config_value(ENV_NAKAMA_ENDPOINT))
	if endpoint.is_empty():
		return _refusal(&"config_missing")
	if _client == null:
		_client = Nakama.create_client(
			config_value(ENV_NAKAMA_SERVER_KEY),
			str(endpoint["host"]),
			int(endpoint["port"]),
			str(endpoint["scheme"])
		)
	var session: Variant = await _client.authenticate_custom_async(
		str(ticket_outcome["ticket"])
	)
	if (
		session == null
		or not session.has_method("is_exception")
		or session.is_exception()
	):
		return _refusal(&"authentication_failed")
	_session = session
	return {"ok": true, "reason": &""}


## Invoke a named server RPC with a Dictionary payload. Returns
## {"ok": true, "reason": &"", "result": Dictionary} on success, or
## {"ok": false, "reason": StringName, ...} on refusal. RPC-level rejections
## additionally carry "status_code" and "grpc_status_code" for error mapping.
func call_rpc(rpc_id: String, payload: Dictionary) -> Dictionary:
	if not Features.NAKAMA_ENABLED:
		return _refusal(&"nakama_disabled")
	if not is_authenticated():
		return _refusal(&"not_authenticated")
	var payload_text := JSON.stringify(payload)
	if payload_text.to_utf8_buffer().size() > MAX_RPC_PAYLOAD_BYTES:
		return _refusal(&"payload_oversized")
	var result: Variant = await _client.rpc_async(_session, rpc_id, payload_text)
	if result == null or not result.has_method("is_exception"):
		return _refusal(&"transport_failed")
	if result.is_exception():
		return rpc_rejection(result)
	var response_text: Variant = result.get("payload")
	if (
		not response_text is String
		or response_text.length() > MAX_RPC_RESPONSE_BYTES
	):
		return _refusal(&"malformed_response")
	var decoded: Variant = JSON.parse_string(response_text)
	if not decoded is Dictionary:
		return _refusal(&"malformed_response")
	return {"ok": true, "reason": &"", "result": decoded}


func drop_session() -> void:
	_session = null


## ------------------------------------------------------------------------
##  Pure config/validation helpers (gdUnit-testable with no network)
## ------------------------------------------------------------------------

## Fail-closed config lookup: ProjectSettings override first (official builds
## have no environment), then process environment, then "".
static func config_value(env_name: String) -> String:
	var setting_name := "such/app_platform/%s" % env_name.to_lower()
	var from_settings := str(ProjectSettings.get_setting(setting_name, ""))
	if from_settings != "":
		return from_settings
	return OS.get_environment(env_name)


static func config_ready() -> bool:
	return (
		config_value(ENV_IDP_TICKET_URL) != ""
		and config_value(ENV_NAKAMA_ENDPOINT) != ""
		and config_value(ENV_NAKAMA_SERVER_KEY) != ""
	)


static func parse_endpoint(value: String) -> Dictionary:
	var pattern := RegEx.new()
	if pattern.compile(ENDPOINT_PATTERN) != OK:
		return {}
	var found := pattern.search(value.strip_edges())
	if found == null:
		return {}
	var scheme := found.get_string(1)
	var port := 443 if scheme == "https" else 7350
	var port_text := found.get_string(4)
	if port_text != "":
		port = int(port_text)
		if port < 1 or port > 65535:
			return {}
	return {"scheme": scheme, "host": found.get_string(2), "port": port}


## Mirrors moonIsOpaqueString(ticket, 16, 1024) from the server's
## before-authenticate hook: bounded, and no control characters.
static func validate_ticket(value: Variant) -> StringName:
	if not value is String:
		return &"ticket"
	var ticket: String = value
	if (
		ticket.to_utf8_buffer().size() < TICKET_MIN_LENGTH
		or ticket.to_utf8_buffer().size() > TICKET_MAX_LENGTH
	):
		return &"ticket"
	for index in ticket.length():
		var code := ticket.unicode_at(index)
		if code <= 0x1f or code == 0x7f:
			return &"ticket"
	return &""


## Build the &"rpc_rejected" refusal from an exception-bearing SDK result.
## The vendored SDK carries the status codes on the NakamaException returned
## by get_exception() (NakamaAsyncResult.gd), NOT on the ApiRpc result object
## itself; reading them off the result would always yield -1/-1 and collapse
## every rejection to &"unknown" in EntitlementClient.map_rpc_failure.
static func rpc_rejection(result: Variant) -> Dictionary:
	var rejection := _refusal(&"rpc_rejected")
	rejection["status_code"] = -1
	rejection["grpc_status_code"] = -1
	if result != null and result.has_method("get_exception"):
		var exception: Variant = result.get_exception()
		if exception != null:
			rejection["status_code"] = _optional_int(exception.get("status_code"))
			rejection["grpc_status_code"] = _optional_int(
				exception.get("grpc_status_code")
			)
	return rejection


static func parse_ticket_response(body: Variant) -> Dictionary:
	if not body is String or body == "" or body.length() > MAX_IDP_RESPONSE_BYTES:
		return {}
	var decoded: Variant = JSON.parse_string(body)
	if not decoded is Dictionary or decoded.size() != 1 or not decoded.has("ticket"):
		return {}
	if validate_ticket(decoded["ticket"]) != &"":
		return {}
	return {"ticket": str(decoded["ticket"])}


## ------------------------------------------------------------------------
##  Internal
## ------------------------------------------------------------------------

static func _refusal(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _optional_int(value: Variant) -> int:
	if value is int:
		return value
	return -1


func _acquire_ticket(url: String) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({
		"contract_version": CONTRACT_VERSION,
		"app_id": APP_ID,
	})
	var error := http.request(
		url,
		["Content-Type: application/json", "Accept: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		http.queue_free()
		return _refusal(&"idp_unreachable")
	var completed: Array = await http.request_completed
	http.queue_free()
	if (
		int(completed[0]) != HTTPRequest.RESULT_SUCCESS
		or int(completed[1]) != 200
	):
		return _refusal(&"idp_rejected")
	var parsed := parse_ticket_response(
		(completed[3] as PackedByteArray).get_string_from_utf8()
	)
	if parsed.is_empty():
		return _refusal(&"idp_malformed")
	return {"ok": true, "reason": &"", "ticket": parsed["ticket"]}
