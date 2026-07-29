var MOON_APP_ID = "moon_launch";
var MOON_APP_SLUG = "moon-launch";
var PLATFORM_CONTRACT_VERSION = 1;
var PLATFORM_CONTRACT_SOURCE_COMMIT =
  "60adf625944d4d764e12d1242cc0cac5e65ac1b8";
var PLATFORM_SCHEMA_VERSION = 2;
var PLATFORM_MINIMUM_NAKAMA_VERSION = "3.40.0";
var PLATFORM_ENTITLEMENT_MAX_SKEW_SECONDS = 300;
var PLATFORM_EXPECTED_MIGRATION = "002_friendly_room";

type MoonJsonObject = {[key: string]: any};

interface MoonIdpClaims {
  contract_version: number;
  app_id: string;
  sub: string;
  display_name?: string;
}

interface MoonEntitlementSource {
  provider: string;
  transaction_id: string;
  line_id: string;
  occurred_at: string;
}

interface MoonEntitlementEvent {
  contract_version: number;
  event_id: string;
  sequence: number;
  operation: string;
  app_id: string;
  subject_id: string;
  entitlement_key: string;
  idempotency_key: string;
  effective_at: string;
  expires_at: string | null;
  source: MoonEntitlementSource;
  metadata?: MoonJsonObject;
}

function moonError(message: string, code: nkruntime.Codes): nkruntime.Error {
  return {message: message, code: code};
}

function moonIsObject(value: any): value is MoonJsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function moonHasOwn(value: MoonJsonObject, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function moonHasExactKeys(
  value: MoonJsonObject,
  required: string[],
  optional: string[]
): boolean {
  var allowed: {[key: string]: boolean} = {};
  var index: number;
  for (index = 0; index < required.length; index += 1) {
    allowed[required[index]] = true;
    if (!moonHasOwn(value, required[index])) {
      return false;
    }
  }
  for (index = 0; index < optional.length; index += 1) {
    allowed[optional[index]] = true;
  }
  var keys = Object.keys(value);
  for (index = 0; index < keys.length; index += 1) {
    if (!allowed[keys[index]]) {
      return false;
    }
  }
  return true;
}

function moonParseObject(payload: string, label: string): MoonJsonObject {
  var parsed: any;
  try {
    parsed = JSON.parse(payload);
  } catch (_) {
    throw moonError(label + " is not valid JSON.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  if (!moonIsObject(parsed)) {
    throw moonError(label + " must be a JSON object.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  return parsed;
}

function moonIsSafeInteger(value: any): value is number {
  return typeof value === "number" &&
    isFinite(value) &&
    Math.floor(value) === value &&
    Math.abs(value) <= 9007199254740991;
}

function moonUtf8Length(value: string): number {
  var length = 0;
  var index;
  for (index = 0; index < value.length; index += 1) {
    var code = value.charCodeAt(index);
    if (code <= 0x7f) {
      length += 1;
    } else if (code <= 0x7ff) {
      length += 2;
    } else if (code >= 0xd800 && code <= 0xdbff) {
      if (index + 1 >= value.length) {
        return -1;
      }
      var next = value.charCodeAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        return -1;
      }
      length += 4;
      index += 1;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return -1;
    } else {
      length += 3;
    }
  }
  return length;
}

function moonIsBoundedString(
  value: any,
  minimumBytes: number,
  maximumBytes: number
): value is string {
  if (typeof value !== "string") {
    return false;
  }
  var length = moonUtf8Length(value);
  return length >= minimumBytes && length <= maximumBytes;
}

function moonIsOpaqueString(
  value: any,
  minimumBytes: number,
  maximumBytes: number
): value is string {
  return moonIsBoundedString(value, minimumBytes, maximumBytes) &&
    !/[\u0000-\u001f\u007f]/.test(value);
}

function moonIsDateTime(value: any): value is string {
  if (typeof value !== "string" || value.length > 40) {
    return false;
  }
  var match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|([+-])(\d{2}):(\d{2}))$/.exec(value);
  if (!match) {
    return false;
  }
  var year = parseInt(match[1], 10);
  var month = parseInt(match[2], 10);
  var day = parseInt(match[3], 10);
  var hour = parseInt(match[4], 10);
  var minute = parseInt(match[5], 10);
  var second = parseInt(match[6], 10);
  var offsetHour = parseInt(match[8] || "0", 10);
  var offsetMinute = parseInt(match[9] || "0", 10);
  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    return false;
  }
  var days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if ((year % 4 === 0 && year % 100 !== 0) || year % 400 === 0) {
    days[1] = 29;
  }
  return day >= 1 && day <= days[month - 1] && !isNaN(Date.parse(value));
}

function moonRequireEnv(
  ctx: nkruntime.Context,
  key: string,
  maximumBytes: number
): string {
  var value = ctx.env[key];
  if (!moonIsOpaqueString(value, 1, maximumBytes)) {
    throw moonError(
      "Required runtime configuration is incomplete.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  return value;
}

function moonReadSingleHeader(
  ctx: nkruntime.Context,
  expectedName: string
): string | null {
  if (!ctx.headers) {
    return null;
  }
  var expected = expectedName.toLowerCase();
  var names = Object.keys(ctx.headers);
  var values: string[] = [];
  var index;
  for (index = 0; index < names.length; index += 1) {
    if (names[index].toLowerCase() === expected) {
      var current = ctx.headers[names[index]];
      var valueIndex;
      for (valueIndex = 0; valueIndex < current.length; valueIndex += 1) {
        values.push(current[valueIndex]);
      }
    }
  }
  return values.length === 1 ? values[0] : null;
}

function moonMacMatches(mac: ArrayBuffer, expectedHex: string): boolean {
  if (!/^[0-9a-f]{64}$/.test(expectedHex)) {
    return false;
  }
  var actual = new Uint8Array(mac);
  var difference = actual.length ^ 32;
  var index;
  for (index = 0; index < 32; index += 1) {
    var expected = parseInt(expectedHex.substr(index * 2, 2), 16);
    var observed = index < actual.length ? actual[index] : 0;
    difference |= observed ^ expected;
  }
  return difference === 0;
}

function moonParseIdpClaims(payload: string): MoonIdpClaims {
  var value = moonParseObject(payload, "Identity response");
  if (!moonHasExactKeys(
    value,
    ["contract_version", "app_id", "sub"],
    ["display_name"]
  )) {
    throw moonError(
      "Identity response does not match the contract.",
      nkruntime.Codes.UNAUTHENTICATED
    );
  }
  if (value.contract_version !== PLATFORM_CONTRACT_VERSION ||
      value.app_id !== MOON_APP_ID ||
      !moonIsOpaqueString(value.sub, 1, 255)) {
    throw moonError(
      "Identity response does not match the contract.",
      nkruntime.Codes.UNAUTHENTICATED
    );
  }
  if (moonHasOwn(value, "display_name") &&
      !moonIsOpaqueString(value.display_name, 1, 64)) {
    throw moonError(
      "Identity response does not match the contract.",
      nkruntime.Codes.UNAUTHENTICATED
    );
  }
  return value as MoonIdpClaims;
}

function moonCanonicalAuthId(nk: nkruntime.Nakama, subject: string): string {
  var digest = nk.sha256Hash(MOON_APP_ID + "\n" + subject).toLowerCase();
  var canonical = MOON_APP_SLUG + "-" + digest;
  if (!/^[a-z0-9-]{6,128}$/.test(canonical) ||
      !/^[0-9a-f]{64}$/.test(digest)) {
    throw moonError(
      "Canonical identity derivation failed.",
      nkruntime.Codes.INTERNAL
    );
  }
  return canonical;
}

function moonBeforeAuthenticateCustom(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  request: nkruntime.AuthenticateCustomRequest
): nkruntime.AuthenticateCustomRequest {
  if (!request.account ||
      !moonIsOpaqueString(request.account.id, 16, 1024)) {
    throw moonError("Authentication ticket is invalid.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var ticket = request.account.id;
  var url = moonRequireEnv(ctx, "IDP_CONSUME_URL", 2048);
  var consumerToken = moonRequireEnv(ctx, "IDP_CONSUMER_TOKEN", 4096);
  var body = JSON.stringify({
    contract_version: PLATFORM_CONTRACT_VERSION,
    app_id: MOON_APP_ID,
    ticket: ticket
  });
  var response: nkruntime.HttpResponse;
  try {
    response = nk.httpRequest(
      url,
      "post",
      {
        "Authorization": "Bearer " + consumerToken,
        "Content-Type": "application/json"
      },
      body,
      3000,
      false
    );
  } catch (_) {
    throw moonError(
      "Identity service is temporarily unavailable.",
      nkruntime.Codes.UNAVAILABLE
    );
  }
  if (response.code !== 200 || !moonIsBoundedString(response.body, 2, 8192)) {
    throw moonError("Authentication ticket was rejected.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var claims = moonParseIdpClaims(response.body);
  var canonical = moonCanonicalAuthId(nk, claims.sub);
  var result = nk.sqlExec(
    "INSERT INTO such_platform_identity " +
      "(subject_id, canonical_auth_id, idp_verified_at) " +
      "VALUES ($1, $2, now()) " +
      "ON CONFLICT (subject_id) DO UPDATE SET " +
      "canonical_auth_id = EXCLUDED.canonical_auth_id, " +
      "idp_verified_at = now() " +
      "WHERE such_platform_identity.canonical_auth_id = EXCLUDED.canonical_auth_id",
    [claims.sub, canonical]
  );
  if (result.rowsAffected !== 1) {
    throw moonError("Identity mapping failed.", nkruntime.Codes.INTERNAL);
  }
  request.account.id = canonical;
  request.account.vars = {};
  return request;
}

function moonAfterAuthenticateCustom(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  _session: nkruntime.Session,
  request: nkruntime.AuthenticateCustomRequest
): void {
  if (!request.account ||
      typeof request.account.id !== "string" ||
      !/^[a-z0-9-]{6,128}$/.test(request.account.id)) {
    throw moonError("Identity mapping failed.", nkruntime.Codes.INTERNAL);
  }
  var userId = ctx.userId;
  if (!userId || !/^[0-9a-f-]{36}$/.test(userId)) {
    var users = nk.sqlQuery(
      "SELECT id::text AS user_id FROM users WHERE custom_id = $1",
      [request.account.id]
    );
    if (users.length !== 1 || typeof users[0].user_id !== "string") {
      throw moonError("Identity mapping failed.", nkruntime.Codes.INTERNAL);
    }
    userId = users[0].user_id;
  }
  var result = nk.sqlExec(
    "UPDATE such_platform_identity SET " +
      "nakama_user_id = $1::uuid, linked_at = now() " +
      "WHERE canonical_auth_id = $2 " +
      "AND (nakama_user_id IS NULL OR nakama_user_id = $1::uuid)",
    [userId, request.account.id]
  );
  if (result.rowsAffected !== 1) {
    throw moonError("Identity mapping failed.", nkruntime.Codes.INTERNAL);
  }
}

function moonParseEntitlementEvent(payload: string): MoonEntitlementEvent {
  if (!moonIsBoundedString(payload, 2, 65536)) {
    throw moonError("Entitlement event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  var value = moonParseObject(payload, "Entitlement event");
  if (!moonHasExactKeys(
    value,
    [
      "contract_version",
      "event_id",
      "sequence",
      "operation",
      "app_id",
      "subject_id",
      "entitlement_key",
      "idempotency_key",
      "effective_at",
      "expires_at",
      "source"
    ],
    ["$schema", "metadata"]
  )) {
    throw moonError("Entitlement event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  if (value.contract_version !== PLATFORM_CONTRACT_VERSION ||
      value.app_id !== MOON_APP_ID ||
      !moonIsOpaqueString(value.event_id, 16, 128) ||
      !moonIsSafeInteger(value.sequence) ||
      value.sequence < 1 ||
      (value.operation !== "GRANT" &&
       value.operation !== "REVOKE" &&
       value.operation !== "REINSTATE") ||
      !moonIsOpaqueString(value.subject_id, 8, 255) ||
      typeof value.entitlement_key !== "string" ||
      !/^[a-z][a-z0-9_.-]*$/.test(value.entitlement_key) ||
      value.entitlement_key.length > 128 ||
      !moonIsOpaqueString(value.idempotency_key, 16, 512) ||
      !moonIsDateTime(value.effective_at) ||
      (value.expires_at !== null && !moonIsDateTime(value.expires_at)) ||
      (value.expires_at !== null &&
       Date.parse(value.expires_at) < Date.parse(value.effective_at))) {
    throw moonError("Entitlement event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  if (!moonIsObject(value.source) ||
      !moonHasExactKeys(
        value.source,
        ["provider", "transaction_id", "line_id", "occurred_at"],
        []
      )) {
    throw moonError("Entitlement event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  var providers: {[key: string]: boolean} = {
    apple: true,
    google: true,
    medusa_stripe: true,
    medusa_crypto: true,
    migration: true,
    admin: true,
    test: true
  };
  if (typeof value.source.provider !== "string" ||
      !providers[value.source.provider] ||
      !moonIsOpaqueString(value.source.transaction_id, 1, 512) ||
      !moonIsOpaqueString(value.source.line_id, 1, 255) ||
      !moonIsDateTime(value.source.occurred_at)) {
    throw moonError("Entitlement event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  if (moonHasOwn(value, "metadata")) {
    if (!moonIsObject(value.metadata)) {
      throw moonError("Entitlement event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
    }
    var metadataKeys = Object.keys(value.metadata);
    if (metadataKeys.length > 32) {
      throw moonError("Entitlement event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
    }
    var index;
    for (index = 0; index < metadataKeys.length; index += 1) {
      var metadataValue = value.metadata[metadataKeys[index]];
      if (metadataValue !== null &&
          typeof metadataValue !== "string" &&
          typeof metadataValue !== "number" &&
          typeof metadataValue !== "boolean") {
        throw moonError("Entitlement event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
      }
    }
  }
  return value as MoonEntitlementEvent;
}

function moonVerifyEntitlementRequest(
  ctx: nkruntime.Context,
  nk: nkruntime.Nakama,
  payload: string
): void {
  if (ctx.userId) {
    throw moonError("Server invocation required.", nkruntime.Codes.PERMISSION_DENIED);
  }
  var timestamp = moonReadSingleHeader(ctx, "X-Such-Entitlement-Timestamp");
  var signature = moonReadSingleHeader(ctx, "X-Such-Entitlement-Signature");
  if (timestamp === null ||
      signature === null ||
      !/^[0-9]{10,12}$/.test(timestamp) ||
      !/^v1=[0-9a-f]{64}$/.test(signature)) {
    throw moonError("Entitlement verification failed.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var timestampNumber = Number(timestamp);
  var now = Math.floor(Date.now() / 1000);
  if (!moonIsSafeInteger(timestampNumber) ||
      Math.abs(now - timestampNumber) > PLATFORM_ENTITLEMENT_MAX_SKEW_SECONDS) {
    throw moonError("Entitlement verification failed.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var key = moonRequireEnv(ctx, "ENTITLEMENT_SIGNING_KEY", 4096);
  var mac = nk.hmacSha256Hash(timestamp + "\n" + payload, key);
  if (!moonMacMatches(mac, signature.substr(3))) {
    throw moonError("Entitlement verification failed.", nkruntime.Codes.UNAUTHENTICATED);
  }
}

function moonRpcHealth(
  _ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  _payload: string
): string {
  return JSON.stringify({
    status: "ok",
    app_id: MOON_APP_ID,
    contract_version: PLATFORM_CONTRACT_VERSION
  });
}

function moonVersionAtLeast(actual: string, minimum: string): boolean {
  var actualParts = actual.split(".");
  var minimumParts = minimum.split(".");
  var index;
  for (index = 0; index < 3; index += 1) {
    var actualValue = parseInt(actualParts[index] || "0", 10);
    var minimumValue = parseInt(minimumParts[index] || "0", 10);
    if (actualValue > minimumValue) {
      return true;
    }
    if (actualValue < minimumValue) {
      return false;
    }
  }
  return true;
}

function moonRuntimeConfigurationReady(ctx: nkruntime.Context): boolean {
  var sourceCommit = ctx.env.APP_RUNTIME_SOURCE_COMMIT;
  var runtimeDigest = ctx.env.APP_RUNTIME_SHA256;
  var migrationDigest = ctx.env.APP_MIGRATION_SHA256;
  var schemaVersion = ctx.env.APP_SCHEMA_VERSION;
  var consumeUrl = ctx.env.IDP_CONSUME_URL;
  var idpToken = ctx.env.IDP_CONSUMER_TOKEN;
  var entitlementKey = ctx.env.ENTITLEMENT_SIGNING_KEY;
  return ctx.env.APP_ID === MOON_APP_ID &&
    ctx.env.APP_PLATFORM_CONTRACT_VERSION === String(PLATFORM_CONTRACT_VERSION) &&
    ctx.env.APP_PLATFORM_CONTRACT_SOURCE_COMMIT === PLATFORM_CONTRACT_SOURCE_COMMIT &&
    schemaVersion === String(PLATFORM_SCHEMA_VERSION) &&
    typeof sourceCommit === "string" &&
    /^[0-9a-f]{40,64}$/.test(sourceCommit) &&
    typeof runtimeDigest === "string" &&
    /^[0-9a-f]{64}$/.test(runtimeDigest) &&
    typeof migrationDigest === "string" &&
    /^[0-9a-f]{64}$/.test(migrationDigest) &&
    typeof consumeUrl === "string" &&
    /^(?:https:\/\/[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?(?::[0-9]{2,5})?|http:\/\/10\.42\.[0-9]{1,3}\.[0-9]{1,3}(?::[0-9]{2,5})?)\/internal\/consume-nakama-ticket$/.test(consumeUrl) &&
    moonIsOpaqueString(idpToken, 24, 4096) &&
    moonIsOpaqueString(entitlementKey, 24, 4096) &&
    moonVersionAtLeast(ctx.version, PLATFORM_MINIMUM_NAKAMA_VERSION);
}

function moonRpcReadiness(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!moonRuntimeConfigurationReady(ctx)) {
    throw moonError("Runtime is not ready.", nkruntime.Codes.FAILED_PRECONDITION);
  }
  var rows = nk.sqlQuery(
    "SELECT migration_id FROM such_platform_schema_migration " +
      "WHERE schema_version = $1 AND migration_id = $2",
    [PLATFORM_SCHEMA_VERSION, PLATFORM_EXPECTED_MIGRATION]
  );
  if (rows.length !== 1) {
    throw moonError("Runtime is not ready.", nkruntime.Codes.FAILED_PRECONDITION);
  }
  return JSON.stringify({
    ready: true,
    app_id: MOON_APP_ID,
    schema_version: PLATFORM_SCHEMA_VERSION,
    contract_version: PLATFORM_CONTRACT_VERSION
  });
}

function moonRpcBuildInfo(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!moonRuntimeConfigurationReady(ctx)) {
    throw moonError("Build information is incomplete.", nkruntime.Codes.FAILED_PRECONDITION);
  }
  return JSON.stringify({
    app_id: MOON_APP_ID,
    contract_version: PLATFORM_CONTRACT_VERSION,
    contract_source_commit: PLATFORM_CONTRACT_SOURCE_COMMIT,
    schema_version: PLATFORM_SCHEMA_VERSION,
    source_commit: ctx.env.APP_RUNTIME_SOURCE_COMMIT,
    runtime_sha256: ctx.env.APP_RUNTIME_SHA256,
    migration_sha256: ctx.env.APP_MIGRATION_SHA256
  });
}

function moonRpcEntitlements(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!ctx.userId) {
    throw moonError("Authentication required.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var rows = nk.sqlQuery(
    "SELECT entitlement_key, operation, " +
      "CASE WHEN expires_at IS NULL THEN NULL ELSE expires_at::text END AS expires_at, " +
      "last_sequence::text AS last_sequence " +
      "FROM such_platform_entitlement e " +
      "JOIN such_platform_identity i ON i.subject_id = e.subject_id " +
      "WHERE i.nakama_user_id = $1::uuid " +
      "AND e.operation IN ('GRANT', 'REINSTATE') " +
      "AND e.effective_at <= now() " +
      "AND (e.expires_at IS NULL OR e.expires_at > now()) " +
      "ORDER BY entitlement_key",
    [ctx.userId]
  );
  var capabilities: MoonJsonObject[] = [];
  var index;
  for (index = 0; index < rows.length; index += 1) {
    capabilities.push({
      key: rows[index].entitlement_key,
      active: true,
      expires_at: rows[index].expires_at,
      last_sequence: rows[index].last_sequence
    });
  }
  return JSON.stringify({
    contract_version: PLATFORM_CONTRACT_VERSION,
    capabilities: capabilities
  });
}

function moonRpcEntitlementProjection(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  moonVerifyEntitlementRequest(ctx, nk, payload);
  var event = moonParseEntitlementEvent(payload);
  var eventDigest = nk.sha256Hash(payload).toLowerCase();
  var rows = nk.sqlQuery(
    "SELECT outcome, last_sequence::text AS last_sequence " +
      "FROM such_platform_apply_entitlement_event(" +
      "$1, $2, $3, $4, $5, $6, $7, $8::timestamptz, " +
      "$9::timestamptz, $10, $11)",
    [
      event.event_id,
      event.subject_id,
      event.entitlement_key,
      event.sequence,
      event.operation,
      event.idempotency_key,
      eventDigest,
      event.effective_at,
      event.expires_at,
      event.source.provider,
      event.source.occurred_at
    ]
  );
  if (rows.length !== 1 ||
      (rows[0].outcome !== "APPLIED" && rows[0].outcome !== "DUPLICATE")) {
    throw moonError("Entitlement projection failed.", nkruntime.Codes.INTERNAL);
  }
  return JSON.stringify({
    outcome: rows[0].outcome.toLowerCase(),
    entitlement_key: event.entitlement_key,
    last_sequence: rows[0].last_sequence
  });
}

function moonRpcPrepareGuestClaim(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!ctx.userId) {
    throw moonError("Authentication required.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var identities = nk.sqlQuery(
    "SELECT 1 AS found FROM such_platform_identity WHERE nakama_user_id = $1::uuid",
    [ctx.userId]
  );
  if (identities.length !== 0) {
    throw moonError(
      "Guest claim preparation requires a guest session.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  var token = nk.base64UrlEncode(nk.secureRandomBytes(32), false);
  var tokenHash = nk.sha256Hash(token).toLowerCase();
  var result = nk.sqlExec(
    "INSERT INTO such_platform_guest_claim_token " +
      "(token_hash, guest_user_id, expires_at) " +
      "VALUES ($1, $2::uuid, now() + interval '10 minutes')",
    [tokenHash, ctx.userId]
  );
  if (result.rowsAffected !== 1) {
    throw moonError("Guest claim preparation failed.", nkruntime.Codes.INTERNAL);
  }
  return JSON.stringify({
    contract_version: PLATFORM_CONTRACT_VERSION,
    claim_token: token,
    expires_in_seconds: 600
  });
}

function moonRpcClaimGuest(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw moonError("Authentication required.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var value = moonParseObject(payload, "Guest claim");
  if (!moonHasExactKeys(value, ["claim_token", "idempotency_key"], []) ||
      !moonIsOpaqueString(value.claim_token, 32, 512) ||
      !moonIsOpaqueString(value.idempotency_key, 16, 255)) {
    throw moonError("Guest claim is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  var tokenHash = nk.sha256Hash(value.claim_token).toLowerCase();
  var rows = nk.sqlQuery(
    "SELECT outcome, merge_result_hash " +
      "FROM such_moon_launch_claim_guest($1, $2::uuid, $3)",
    [tokenHash, ctx.userId, value.idempotency_key]
  );
  if (rows.length !== 1 ||
      (rows[0].outcome !== "APPLIED" && rows[0].outcome !== "DUPLICATE") ||
      !/^[0-9a-f]{64}$/.test(rows[0].merge_result_hash)) {
    throw moonError("Guest claim failed.", nkruntime.Codes.INTERNAL);
  }
  return JSON.stringify({
    outcome: rows[0].outcome.toLowerCase(),
    merge_result_hash: rows[0].merge_result_hash
  });
}
