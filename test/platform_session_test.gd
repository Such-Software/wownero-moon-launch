class_name PlatformSessionTest
extends GdUnitTestSuite
## Phase-2 client wiring: PlatformSession must stay a complete no-op while
## AppPlatformFeatures.NAKAMA_ENABLED is closed, and its pure config helpers
## must fail closed with no network.

const Features = preload("res://game/platform/AppPlatformFeatures.gd")
const Session = preload("res://game/platform/PlatformSession.gd")


class RecordingClient extends RefCounted:
	var rpc_calls: Array = []

	func rpc_async(_session: Variant, rpc_id: String, payload: Variant) -> Variant:
		rpc_calls.append([rpc_id, payload])
		return null


## Mirrors the vendored SDK's failure surface: NakamaException exposes the
## status codes (NakamaException.gd), and the ApiRpc result only reaches them
## through get_exception() (NakamaAsyncResult.gd).
class FakeSdkException extends RefCounted:
	var status_code: int = 503
	var grpc_status_code: int = 14


class FakeRejectedRpc extends RefCounted:
	var _exception := FakeSdkException.new()

	func is_exception() -> bool:
		return true

	func get_exception() -> Variant:
		return _exception


# ==========================================================================
#  FLAG-OFF NO-OP PROOFS
# ==========================================================================

func test_rollout_flags_stay_closed() -> void:
	assert_bool(Features.NAKAMA_ENABLED).is_false()
	assert_bool(Features.ENTITLEMENTS_ENABLED).is_false()
	assert_bool(Features.all_closed()).is_true()


func test_ensure_session_refuses_while_flag_closed() -> void:
	var session: Node = auto_free(Session.new())
	var outcome: Dictionary = await session.ensure_session()
	assert_bool(bool(outcome["ok"])).is_false()
	assert_str(str(outcome["reason"])).is_equal("nakama_disabled")
	assert_bool(session.is_authenticated()).is_false()


func test_call_rpc_refuses_before_touching_an_injected_client() -> void:
	# Even a fully configured session must not reach the transport while the
	# flag is closed: the refusal happens before any client call.
	var session: Node = auto_free(Session.new())
	var client := RecordingClient.new()
	session.configure(client, {"token": "fake"})
	var outcome: Dictionary = await session.call_rpc(
		"app_platform_entitlements", {}
	)
	assert_bool(bool(outcome["ok"])).is_false()
	assert_str(str(outcome["reason"])).is_equal("nakama_disabled")
	assert_int(client.rpc_calls.size()).is_equal(0)


func test_drop_session_clears_authentication() -> void:
	var session: Node = auto_free(Session.new())
	session.configure(RecordingClient.new(), {"token": "fake"})
	assert_bool(session.is_authenticated()).is_true()
	session.drop_session()
	assert_bool(session.is_authenticated()).is_false()


func test_rpc_rejection_reads_codes_from_the_sdk_exception() -> void:
	# The vendored SDK carries status codes on get_exception(), never on the
	# ApiRpc result itself — mapping must go through the exception or every
	# rejection degrades to &"unknown".
	var rejection := Session.rpc_rejection(FakeRejectedRpc.new())
	assert_str(str(rejection["reason"])).is_equal("rpc_rejected")
	assert_int(int(rejection["status_code"])).is_equal(503)
	assert_int(int(rejection["grpc_status_code"])).is_equal(14)
	# A result with no exception surface fails closed to -1/-1 ("unknown").
	var bare := Session.rpc_rejection(RefCounted.new())
	assert_int(int(bare["status_code"])).is_equal(-1)
	assert_int(int(bare["grpc_status_code"])).is_equal(-1)


# ==========================================================================
#  CONFIG SURFACE — fail-closed empties
# ==========================================================================

func test_config_value_fails_closed_to_empty() -> void:
	assert_str(Session.config_value("SUCH_APP_TEST_UNSET_SENTINEL")).is_empty()


func test_config_surface_names_are_defined_in_one_place() -> void:
	assert_str(Session.ENV_IDP_TICKET_URL).is_equal("SUCH_APP_IDP_TICKET_URL")
	assert_str(Session.ENV_NAKAMA_ENDPOINT).is_equal("SUCH_APP_NAKAMA_ENDPOINT")
	assert_str(Session.ENV_NAKAMA_SERVER_KEY).is_equal("SUCH_APP_NAKAMA_SERVER_KEY")


# ==========================================================================
#  ENDPOINT PARSER
# ==========================================================================

func test_parse_endpoint_accepts_explicit_port() -> void:
	assert_dict(Session.parse_endpoint("https://nakama.such.software:7350")).is_equal({
		"scheme": "https",
		"host": "nakama.such.software",
		"port": 7350,
	})


func test_parse_endpoint_defaults_port_per_scheme() -> void:
	assert_int(int(Session.parse_endpoint("https://nakama.such.software")["port"])) \
		.is_equal(443)
	assert_int(int(Session.parse_endpoint("http://127.0.0.1")["port"])) \
		.is_equal(7350)


func test_parse_endpoint_rejects_malformed_values() -> void:
	assert_dict(Session.parse_endpoint("")).is_empty()
	assert_dict(Session.parse_endpoint("ftp://nakama.such.software")).is_empty()
	assert_dict(Session.parse_endpoint("https://host/path")).is_empty()
	assert_dict(Session.parse_endpoint("https://user@host")).is_empty()
	assert_dict(Session.parse_endpoint("https://host:0")).is_empty()
	assert_dict(Session.parse_endpoint("https://host:99999")).is_empty()
	assert_dict(Session.parse_endpoint("nakama.such.software")).is_empty()


# ==========================================================================
#  TICKET VALIDATION — mirrors moonBeforeAuthenticateCustom bounds
# ==========================================================================

func test_validate_ticket_accepts_opaque_token() -> void:
	assert_str(str(Session.validate_ticket("ticket-0123456789abcdef"))).is_empty()


func test_validate_ticket_rejects_out_of_contract_values() -> void:
	assert_str(str(Session.validate_ticket("short"))).is_equal("ticket")
	assert_str(str(Session.validate_ticket("x".repeat(1025)))).is_equal("ticket")
	assert_str(str(Session.validate_ticket("control\ncharacters-0123456789"))) \
		.is_equal("ticket")
	assert_str(str(Session.validate_ticket(42))).is_equal("ticket")
	assert_str(str(Session.validate_ticket(null))).is_equal("ticket")


func test_parse_ticket_response_is_exact() -> void:
	var body := JSON.stringify({"ticket": "ticket-0123456789abcdef"})
	assert_dict(Session.parse_ticket_response(body)).is_equal({
		"ticket": "ticket-0123456789abcdef",
	})
	assert_dict(Session.parse_ticket_response("not json")).is_empty()
	assert_dict(Session.parse_ticket_response("")).is_empty()
	assert_dict(Session.parse_ticket_response(
		JSON.stringify({"ticket": "ticket-0123456789abcdef", "extra": true})
	)).is_empty()
	assert_dict(Session.parse_ticket_response(
		JSON.stringify({"ticket": "short"})
	)).is_empty()
	assert_dict(Session.parse_ticket_response(
		JSON.stringify({"ticket": 7})
	)).is_empty()
