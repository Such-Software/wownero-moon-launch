var MOON_APP_ID = "moon_launch";
var MOON_APP_SLUG = "moon-launch";
var PLATFORM_CONTRACT_VERSION = 1;
var PLATFORM_CONTRACT_SOURCE_COMMIT =
  "90a11e5c21ff1fbe3cec2522c837edd3996a9bf2";
var PLATFORM_SCHEMA_VERSION = 4;
var PLATFORM_MINIMUM_NAKAMA_VERSION = "3.40.0";
var PLATFORM_ENTITLEMENT_MAX_SKEW_SECONDS = 300;
var PLATFORM_CURRENCY_MAX_SKEW_SECONDS = 300;
var PLATFORM_EXPECTED_MIGRATION = "004_native_purchase";

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

interface MoonCurrencyEvent {
  contract_version: number;
  event_id: string;
  sequence: number;
  operation: string;
  app_id: string;
  subject_id: string;
  currency_key: string;
  amount: number;
  original_event_id: string | null;
  idempotency_key: string;
  effective_at: string;
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
  var url = moonRequireEnv(ctx, "SUCH_IDP_CONSUME_URL", 2048);
  var consumerToken = moonRequireEnv(ctx, "SUCH_IDP_CONSUMER_TOKEN", 4096);
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
  var key = moonRequireEnv(
    ctx,
    "SUCH_ENTITLEMENT_PROJECTION_HMAC_KEY",
    4096
  );
  var mac = nk.hmacSha256Hash(timestamp + "\n" + payload, key);
  if (!moonMacMatches(mac, signature.substr(3))) {
    throw moonError("Entitlement verification failed.", nkruntime.Codes.UNAUTHENTICATED);
  }
}

function moonParseCurrencyEvent(payload: string): MoonCurrencyEvent {
  if (!moonIsBoundedString(payload, 2, 65536)) {
    throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  var value = moonParseObject(payload, "Currency event");
  if (!moonHasExactKeys(
    value,
    [
      "contract_version",
      "event_id",
      "sequence",
      "operation",
      "app_id",
      "subject_id",
      "currency_key",
      "amount",
      "original_event_id",
      "idempotency_key",
      "effective_at",
      "source"
    ],
    ["$schema", "metadata"]
  )) {
    throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  if (value.contract_version !== PLATFORM_CONTRACT_VERSION ||
      value.app_id !== MOON_APP_ID ||
      !moonIsOpaqueString(value.event_id, 16, 128) ||
      !moonIsSafeInteger(value.sequence) ||
      value.sequence < 1 ||
      (value.operation !== "CREDIT" &&
       value.operation !== "REVERSE" &&
       value.operation !== "REINSTATE") ||
      !moonIsOpaqueString(value.subject_id, 8, 255) ||
      value.currency_key !== "moonrocks" ||
      !moonIsSafeInteger(value.amount) ||
      value.amount < 1 ||
      !moonIsOpaqueString(value.idempotency_key, 16, 512) ||
      !moonIsDateTime(value.effective_at)) {
    throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  if ((value.operation === "CREDIT" && value.original_event_id !== null) ||
      (value.operation !== "CREDIT" &&
       !moonIsOpaqueString(value.original_event_id, 16, 128))) {
    throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  if (!moonIsObject(value.source) ||
      !moonHasExactKeys(
        value.source,
        ["provider", "transaction_id", "line_id", "occurred_at"],
        []
      )) {
    throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
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
  var catalogAmounts: {[key: string]: number} = {
    moonrocks_10k_v1: 10000,
    moonrocks_50k_v1: 50000
  };
  if (typeof value.source.provider !== "string" ||
      !providers[value.source.provider] ||
      !moonIsOpaqueString(value.source.transaction_id, 1, 512) ||
      !moonIsOpaqueString(value.source.line_id, 1, 255) ||
      catalogAmounts[value.source.line_id] !== value.amount ||
      !moonIsDateTime(value.source.occurred_at)) {
    throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  if (moonHasOwn(value, "metadata")) {
    if (!moonIsObject(value.metadata)) {
      throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
    }
    var metadataKeys = Object.keys(value.metadata);
    if (metadataKeys.length > 32) {
      throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
    }
    var index;
    for (index = 0; index < metadataKeys.length; index += 1) {
      var metadataValue = value.metadata[metadataKeys[index]];
      if (metadataValue !== null &&
          typeof metadataValue !== "string" &&
          typeof metadataValue !== "number" &&
          typeof metadataValue !== "boolean") {
        throw moonError("Currency event is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
      }
    }
  }
  return value as MoonCurrencyEvent;
}

function moonVerifyCurrencyRequest(
  ctx: nkruntime.Context,
  nk: nkruntime.Nakama,
  payload: string
): void {
  if (ctx.userId) {
    throw moonError("Server invocation required.", nkruntime.Codes.PERMISSION_DENIED);
  }
  var timestamp = moonReadSingleHeader(ctx, "X-Such-Currency-Timestamp");
  var signature = moonReadSingleHeader(ctx, "X-Such-Currency-Signature");
  if (timestamp === null ||
      signature === null ||
      !/^[0-9]{10,12}$/.test(timestamp) ||
      !/^v1=[0-9a-f]{64}$/.test(signature)) {
    throw moonError("Currency verification failed.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var timestampNumber = Number(timestamp);
  var now = Math.floor(Date.now() / 1000);
  if (!moonIsSafeInteger(timestampNumber) ||
      Math.abs(now - timestampNumber) > PLATFORM_CURRENCY_MAX_SKEW_SECONDS) {
    throw moonError("Currency verification failed.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var key = moonRequireEnv(ctx, "SUCH_CURRENCY_PROJECTION_HMAC_KEY", 4096);
  var mac = nk.hmacSha256Hash(timestamp + "\n" + payload, key);
  if (!moonMacMatches(mac, signature.substr(3))) {
    throw moonError("Currency verification failed.", nkruntime.Codes.UNAUTHENTICATED);
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

function moonIsPlatformServiceUrl(value: any, expectedPath: string): boolean {
  if (typeof value !== "string") {
    return false;
  }
  var match =
    /^(?:https:\/\/[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?(?::[0-9]{2,5})?|http:\/\/10\.42\.[0-9]{1,3}\.[0-9]{1,3}(?::[0-9]{2,5})?)(\/[^?#]*)$/.exec(
      value
    );
  return match !== null && match[1] === expectedPath;
}

function moonProductCatalogReady(value: any): boolean {
  if (typeof value !== "string" || value.length === 0) {
    return false;
  }
  var products = value.split(",");
  var seen: {[key: string]: boolean} = {};
  var index;
  for (index = 0; index < products.length; index += 1) {
    var product = products[index].trim();
    if (!/^[A-Za-z0-9_.-]{1,256}$/.test(product) || seen[product]) {
      return false;
    }
    seen[product] = true;
  }
  return products.length > 0;
}

function moonSecretsUnique(values: any[]): boolean {
  var left;
  var right;
  for (left = 0; left < values.length; left += 1) {
    for (right = left + 1; right < values.length; right += 1) {
      if (values[left] === values[right]) {
        return false;
      }
    }
  }
  return true;
}

function moonRuntimeConfigurationReady(ctx: nkruntime.Context): boolean {
  var sourceCommit = ctx.env.SUCH_PLATFORM_SOURCE_COMMIT;
  var runtimeDigest = ctx.env.SUCH_PLATFORM_RUNTIME_SHA256;
  var migrationDigest = ctx.env.SUCH_PLATFORM_MIGRATION_SHA256;
  var schemaVersion = ctx.env.SUCH_PLATFORM_SCHEMA_VERSION;
  var consumeUrl = ctx.env.SUCH_IDP_CONSUME_URL;
  var idpToken = ctx.env.SUCH_IDP_CONSUMER_TOKEN;
  var entitlementProviderUrl = ctx.env.SUCH_ENTITLEMENT_PROVIDER_URL;
  var entitlementProviderToken = ctx.env.SUCH_ENTITLEMENT_PROVIDER_TOKEN;
  var entitlementKey = ctx.env.SUCH_ENTITLEMENT_PROJECTION_HMAC_KEY;
  var currencyKey = ctx.env.SUCH_CURRENCY_PROJECTION_HMAC_KEY;
  var roomSeedKey = ctx.env.SUCH_ROOM_SEED_HMAC_KEY;
  return ctx.env.SUCH_PLATFORM_APP_ID === MOON_APP_ID &&
    ctx.env.SUCH_PLATFORM_CONTRACT_VERSION ===
      String(PLATFORM_CONTRACT_VERSION) &&
    ctx.env.SUCH_PLATFORM_CONTRACT_COMMIT ===
      PLATFORM_CONTRACT_SOURCE_COMMIT &&
    schemaVersion === String(PLATFORM_SCHEMA_VERSION) &&
    typeof sourceCommit === "string" &&
    /^[0-9a-f]{40,64}$/.test(sourceCommit) &&
    typeof runtimeDigest === "string" &&
    /^[0-9a-f]{64}$/.test(runtimeDigest) &&
    typeof migrationDigest === "string" &&
    /^[0-9a-f]{64}$/.test(migrationDigest) &&
    moonIsPlatformServiceUrl(
      consumeUrl,
      "/internal/consume-nakama-ticket"
    ) &&
    moonIsOpaqueString(idpToken, 24, 4096) &&
    moonIsPlatformServiceUrl(
      entitlementProviderUrl,
      "/v1/provider-events/" + MOON_APP_ID
    ) &&
    moonIsOpaqueString(entitlementProviderToken, 24, 4096) &&
    moonIsOpaqueString(entitlementKey, 32, 4096) &&
    moonIsOpaqueString(currencyKey, 32, 4096) &&
    moonIsOpaqueString(roomSeedKey, 32, 4096) &&
    moonSecretsUnique([
      idpToken,
      entitlementProviderToken,
      entitlementKey,
      currencyKey,
      roomSeedKey
    ]) &&
    moonProductCatalogReady(ctx.env.SUCH_IAP_APPLE_PRODUCT_IDS) &&
    moonProductCatalogReady(ctx.env.SUCH_IAP_GOOGLE_PRODUCT_IDS) &&
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
    source_commit: ctx.env.SUCH_PLATFORM_SOURCE_COMMIT,
    runtime_sha256: ctx.env.SUCH_PLATFORM_RUNTIME_SHA256,
    migration_sha256: ctx.env.SUCH_PLATFORM_MIGRATION_SHA256
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
      "last_event_sequence::text AS last_sequence " +
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

function moonRpcCurrencyBalance(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!ctx.userId) {
    throw moonError("Authentication required.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var rows = nk.sqlQuery(
    "SELECT COALESCE(b.balance, 0)::text AS balance, " +
      "GREATEST(COALESCE(b.balance, 0), 0)::text AS available, " +
      "GREATEST(-COALESCE(b.balance, 0), 0)::text AS debt, " +
      "COALESCE(b.last_sequence, 0)::text AS last_sequence " +
      "FROM such_platform_identity i " +
      "LEFT JOIN such_platform_currency_balance b " +
      "ON b.subject_id = i.subject_id AND b.currency_key = $2 " +
      "WHERE i.nakama_user_id = $1::uuid",
    [ctx.userId, "moonrocks"]
  );
  if (rows.length !== 1 ||
      !/^-?[0-9]+$/.test(rows[0].balance) ||
      !/^[0-9]+$/.test(rows[0].available) ||
      !/^[0-9]+$/.test(rows[0].debt) ||
      !/^[0-9]+$/.test(rows[0].last_sequence)) {
    throw moonError("Currency balance is unavailable.", nkruntime.Codes.FAILED_PRECONDITION);
  }
  return JSON.stringify({
    contract_version: PLATFORM_CONTRACT_VERSION,
    currency_key: "moonrocks",
    balance: rows[0].balance,
    available: rows[0].available,
    debt: rows[0].debt,
    last_sequence: rows[0].last_sequence
  });
}

function moonRpcCurrencyProjection(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  moonVerifyCurrencyRequest(ctx, nk, payload);
  var event = moonParseCurrencyEvent(payload);
  var eventDigest = nk.sha256Hash(payload).toLowerCase();
  var rows = nk.sqlQuery(
    "SELECT outcome, balance::text AS balance, " +
      "last_sequence::text AS last_sequence " +
      "FROM such_platform_apply_currency_event(" +
      "$1, $2, $3, $4, $5, $6, $7, $8, $9, " +
      "$10::timestamptz, $11, $12, $13, $14::timestamptz)",
    [
      event.event_id,
      event.subject_id,
      event.currency_key,
      event.sequence,
      event.operation,
      event.amount,
      event.original_event_id,
      event.idempotency_key,
      eventDigest,
      event.effective_at,
      event.source.provider,
      event.source.transaction_id,
      event.source.line_id,
      event.source.occurred_at
    ]
  );
  if (rows.length !== 1 ||
      (rows[0].outcome !== "APPLIED" && rows[0].outcome !== "DUPLICATE") ||
      !/^-?[0-9]+$/.test(rows[0].balance) ||
      !/^[0-9]+$/.test(rows[0].last_sequence)) {
    throw moonError("Currency projection failed.", nkruntime.Codes.INTERNAL);
  }
  return JSON.stringify({
    outcome: rows[0].outcome.toLowerCase(),
    currency_key: event.currency_key,
    balance: rows[0].balance,
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
      "(claim_token_digest, guest_user_id, expires_at) " +
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

// --- Native IAP validation (nakama_iap_validate_v1) ---
//
// The client submits a store receipt; Nakama core validates it against Apple or
// Google (iap.apple / iap.google server credentials), the result is posted to
// the entitlement ledger as a native provider event carrying the
// nakama_iap_validate_v1 assertion, and the accepted event is recorded locally
// in such_platform_native_purchase. The ledger stays the authority: nothing is
// granted here, and the client learns the projection is pending rather than
// receiving a fabricated grant (per the identity-and-entitlements contract).
//
// Moon Launch is the one app whose catalog includes consumables (Moonrocks),
// so unlike the vegan-IQ/bauhaus/bloomword validators this port must accept
// BOTH ledger response kinds. A currency response maps operations
// GRANT->CREDIT / REVOKE->REVERSE / REINSTATE->REINSTATE, and its
// source.line_id is the ledger's offer_id rather than the transaction id we
// sent, so the binding check branches by kind instead of blindly comparing.

interface MoonIapRequest {
  provider: string;
  product_id: string;
  receipt: string;
}

function moonProductSet(value: string | undefined): {[id: string]: boolean} {
  var products: {[id: string]: boolean} = {};
  if (typeof value !== "string") {
    return products;
  }
  var parts = value.split(",");
  var index;
  for (index = 0; index < parts.length; index += 1) {
    var trimmed = parts[index].replace(/^\s+|\s+$/g, "");
    if (trimmed !== "") {
      products[trimmed] = true;
    }
  }
  return products;
}

function moonParseIapRequest(
  ctx: nkruntime.Context,
  payload: string
): MoonIapRequest {
  if (!moonIsBoundedString(payload, 2, 262144 + 1024)) {
    throw moonError(
      "Purchase validation request is invalid.",
      nkruntime.Codes.INVALID_ARGUMENT
    );
  }
  var value = moonParseObject(payload, "Purchase validation request");
  if (!moonHasExactKeys(value, ["provider", "product_id", "receipt"], []) ||
      (value.provider !== "apple" && value.provider !== "google") ||
      typeof value.product_id !== "string" ||
      !/^[A-Za-z0-9_.-]{1,256}$/.test(value.product_id) ||
      typeof value.receipt !== "string" ||
      value.receipt.length < 8 ||
      value.receipt.length > 262144) {
    throw moonError(
      "Purchase validation request is invalid.",
      nkruntime.Codes.INVALID_ARGUMENT
    );
  }
  var catalog = value.provider === "apple"
    ? moonProductSet(ctx.env.SUCH_IAP_APPLE_PRODUCT_IDS)
    : moonProductSet(ctx.env.SUCH_IAP_GOOGLE_PRODUCT_IDS);
  if (catalog[value.product_id] !== true) {
    throw moonError(
      "Purchase product is not in the deployed catalog.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  return {
    provider: value.provider,
    product_id: value.product_id,
    receipt: value.receipt
  };
}

function moonResolveSubject(ctx: nkruntime.Context, nk: nkruntime.Nakama): string {
  var rows = nk.sqlQuery(
    "SELECT subject_id FROM such_platform_identity WHERE nakama_user_id = $1::uuid",
    [ctx.userId]
  );
  if (rows.length !== 1 || !moonIsOpaqueString(rows[0].subject_id, 8, 255)) {
    throw moonError(
      "Purchase validation requires a platform identity.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  return rows[0].subject_id;
}

function moonProviderEnvironment(provider: string, value: string): string {
  if (value === "SANDBOX") {
    // The ledger catalog pins per-provider environments: Apple test purchases
    // are "sandbox", Google test purchases are "test". Sending google+sandbox
    // is a guaranteed catalog_rejected 422.
    return provider === "google" ? "test" : "sandbox";
  }
  if (value === "PRODUCTION") {
    return "production";
  }
  throw moonError(
    "Purchase provider environment is unknown.",
    nkruntime.Codes.FAILED_PRECONDITION
  );
}

function moonEpochIso(value: number): string {
  if (typeof value !== "number" || !isFinite(value) || value <= 0) {
    throw moonError(
      "Purchase provider returned an invalid timestamp.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  var milliseconds = value > 100000000000 ? value : value * 1000;
  var result = new Date(milliseconds);
  if (!isFinite(result.getTime())) {
    throw moonError(
      "Purchase provider returned an invalid timestamp.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  return result.toISOString();
}

function moonSelectValidatedPurchase(
  response: nkruntime.ValidatePurchaseResponse,
  request: MoonIapRequest,
  userId: string
): nkruntime.ValidatedPurchase {
  var purchases = response.validatedPurchases || [];
  var expectedStore = request.provider === "apple"
    ? "APPLE_APP_STORE"
    : "GOOGLE_PLAY_STORE";
  var selected: nkruntime.ValidatedPurchase | null = null;
  var index;
  for (index = 0; index < purchases.length; index += 1) {
    var purchase = purchases[index];
    if (purchase.userId === userId &&
        purchase.productId === request.product_id &&
        String(purchase.store) === expectedStore &&
        (!selected || purchase.updateTime > selected.updateTime)) {
      selected = purchase;
    }
  }
  if (!selected || !selected.transactionId) {
    throw moonError(
      "The store did not validate this product for the current account.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  return selected;
}

function moonOperationForPurchase(
  nk: nkruntime.Nakama,
  provider: string,
  purchase: nkruntime.ValidatedPurchase,
  subject: string
): string {
  // Check the immutable local binding even for a refund before deriving the
  // lifecycle operation. The ledger independently enforces the same binding;
  // failing here keeps a replayed receipt from ever leaving this instance.
  var rows = nk.sqlQuery(
    "SELECT last_operation, subject_id, product_id " +
      "FROM such_platform_native_purchase " +
      "WHERE provider = $1 AND transaction_id = $2 AND line_id = $2",
    [provider, purchase.transactionId]
  );
  if (rows.length > 1 ||
      (rows.length === 1 &&
        (rows[0].subject_id !== subject ||
         rows[0].product_id !== purchase.productId))) {
    throw moonError(
      "Store transaction is already bound to another account or product.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  if (purchase.refundTime > 0) {
    return "REVOKE";
  }
  return rows.length === 1 && rows[0].last_operation === "REVOKE"
    ? "REINSTATE"
    : "GRANT";
}

// Ledger acceptance for a native event. Entitlement events echo our line_id
// (the transaction id); currency events replace source.line_id with the
// catalog offer_id, and their operation is the currency mapping of ours.
function moonBindLedgerEvent(
  eventValue: MoonJsonObject,
  expected: {
    subjectId: string;
    operation: string;
    provider: string;
    productId: string;
    transactionId: string;
  }
): {
  sequence: number;
  entitlementKey: string | null;
  currencyKey: string | null;
  amount: number | null;
} {
  var isCurrency = moonHasOwn(eventValue, "currency_key");
  var parsed: MoonEntitlementEvent | MoonCurrencyEvent;
  try {
    parsed = isCurrency
      ? moonParseCurrencyEvent(JSON.stringify(eventValue))
      : moonParseEntitlementEvent(JSON.stringify(eventValue));
  } catch (_error) {
    throw moonError(
      "Purchase validation service returned an invalid event.",
      nkruntime.Codes.UNAVAILABLE
    );
  }
  var expectedOperation = expected.operation;
  if (isCurrency) {
    expectedOperation = expected.operation === "GRANT"
      ? "CREDIT"
      : expected.operation === "REVOKE" ? "REVERSE" : "REINSTATE";
  }
  var metadata = parsed.metadata;
  if (parsed.subject_id !== expected.subjectId ||
      parsed.operation !== expectedOperation ||
      parsed.source.provider !== expected.provider ||
      parsed.source.transaction_id !== expected.transactionId ||
      (!isCurrency && parsed.source.line_id !== expected.transactionId) ||
      !metadata ||
      metadata.product_id !== expected.productId) {
    throw moonError(
      "Purchase validation service response did not bind to this account.",
      nkruntime.Codes.UNAVAILABLE
    );
  }
  return {
    sequence: parsed.sequence,
    entitlementKey: isCurrency
      ? null
      : (parsed as MoonEntitlementEvent).entitlement_key,
    currencyKey: isCurrency
      ? (parsed as MoonCurrencyEvent).currency_key
      : null,
    amount: isCurrency ? (parsed as MoonCurrencyEvent).amount : null
  };
}

function moonRpcValidateIap(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw moonError("Authentication required.", nkruntime.Codes.UNAUTHENTICATED);
  }
  var request = moonParseIapRequest(ctx, payload);
  var providerUrl = moonRequireEnv(ctx, "SUCH_ENTITLEMENT_PROVIDER_URL", 2048);
  var providerToken = moonRequireEnv(
    ctx,
    "SUCH_ENTITLEMENT_PROVIDER_TOKEN",
    4096
  );
  if (!moonIsPlatformServiceUrl(
    providerUrl,
    "/v1/provider-events/" + MOON_APP_ID
  )) {
    throw moonError(
      "Purchase validation is temporarily unavailable.",
      nkruntime.Codes.UNAVAILABLE
    );
  }
  var subject = moonResolveSubject(ctx, nk);
  var validation = request.provider === "apple"
    ? nk.purchaseValidateApple(ctx.userId, request.receipt, true)
    : nk.purchaseValidateGoogle(ctx.userId, request.receipt, true);
  var purchase = moonSelectValidatedPurchase(validation, request, ctx.userId);
  var environment = moonProviderEnvironment(request.provider, String(purchase.environment));
  var operation = moonOperationForPurchase(nk, request.provider, purchase, subject);
  var occurredAt = moonEpochIso(purchase.refundTime > 0
    ? purchase.refundTime
    : Math.max(purchase.updateTime, purchase.purchaseTime));
  var verifiedAt = new Date().toISOString();
  var eventBody = {
    provider: request.provider,
    product_id: purchase.productId,
    transaction_id: purchase.transactionId,
    line_id: purchase.transactionId,
    operation: operation,
    subject_id: subject,
    occurred_at: occurredAt,
    effective_at: occurredAt,
    expires_at: null,
    environment: environment,
    validation: {
      authority: "nakama_iap_validate_v1",
      app_id: MOON_APP_ID,
      provider: request.provider,
      product_id: purchase.productId,
      transaction_id: purchase.transactionId,
      line_id: purchase.transactionId,
      operation: operation,
      environment: environment,
      occurred_at: occurredAt,
      effective_at: occurredAt,
      expires_at: null,
      verified_at: verifiedAt
    }
  };
  var response: nkruntime.HttpResponse;
  try {
    response = nk.httpRequest(
      providerUrl,
      "post",
      {
        "Authorization": "Bearer " + providerToken,
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      JSON.stringify(eventBody),
      5000,
      false
    );
  } catch (_error) {
    throw moonError(
      "Purchase validation is temporarily unavailable.",
      nkruntime.Codes.UNAVAILABLE
    );
  }
  if (response.code !== 200 && response.code !== 201) {
    if (response.code === 401 || response.code === 403) {
      throw moonError(
        "Purchase validation service authentication failed.",
        nkruntime.Codes.UNAVAILABLE
      );
    }
    if (response.code === 409 || response.code === 422) {
      throw moonError(
        "Purchase does not match the deployed entitlement catalog.",
        nkruntime.Codes.FAILED_PRECONDITION
      );
    }
    var errorCode = "";
    try {
      var errorBody = JSON.parse(response.body);
      if (moonIsObject(errorBody) && typeof errorBody.error === "string") {
        errorCode = errorBody.error;
      }
    } catch (_ignored) {
      // Fall through to the generic retryable failure.
    }
    if (errorCode === "original_credit_unavailable") {
      // A refund arrived for a consumable whose credit this ledger never saw.
      // Retrying cannot succeed; surface a terminal state instead of looping.
      throw moonError(
        "Purchase was refunded before its credit was recorded.",
        nkruntime.Codes.FAILED_PRECONDITION
      );
    }
    throw moonError(
      "Purchase validation is temporarily unavailable.",
      nkruntime.Codes.UNAVAILABLE
    );
  }
  var body: MoonJsonObject;
  try {
    body = moonParseObject(response.body, "Purchase validation response");
  } catch (_error) {
    throw moonError(
      "Purchase validation service returned an invalid response.",
      nkruntime.Codes.UNAVAILABLE
    );
  }
  if (!moonHasExactKeys(
    body,
    ["ok", "duplicate", "applied", "ignored_reason", "event"],
    []
  ) ||
      body.ok !== true ||
      typeof body.duplicate !== "boolean" ||
      typeof body.applied !== "boolean" ||
      (body.ignored_reason !== null &&
        !moonIsBoundedString(body.ignored_reason, 1, 128)) ||
      (body.applied === true && body.ignored_reason !== null) ||
      (body.applied === false && body.ignored_reason === null) ||
      !moonIsObject(body.event)) {
    throw moonError(
      "Purchase validation service returned an invalid response.",
      nkruntime.Codes.UNAVAILABLE
    );
  }
  var accepted = moonBindLedgerEvent(body.event, {
    subjectId: subject,
    operation: operation,
    provider: request.provider,
    productId: purchase.productId,
    transactionId: purchase.transactionId
  });
  if (body.applied === true) nk.sqlExec(
    "INSERT INTO such_platform_native_purchase " +
      "(provider, transaction_id, line_id, subject_id, product_id, " +
      "last_operation, last_validated_at, last_event_sequence) " +
      "VALUES ($1, $2, $2, $3, $4, $5, now(), $6) " +
      "ON CONFLICT (provider, transaction_id, line_id) DO UPDATE SET " +
      "subject_id = EXCLUDED.subject_id, " +
      "product_id = EXCLUDED.product_id, " +
      "last_operation = EXCLUDED.last_operation, " +
      "last_validated_at = now(), " +
      "last_event_sequence = EXCLUDED.last_event_sequence",
    [
      request.provider,
      purchase.transactionId,
      subject,
      purchase.productId,
      operation,
      accepted.sequence
    ]
  );
  return JSON.stringify({
    verified: true,
    provider: request.provider,
    product_id: purchase.productId,
    transaction_id: purchase.transactionId,
    operation: operation,
    seen_before: purchase.seenBefore === true,
    duplicate: body.duplicate,
    applied: body.applied,
    ignored_reason: body.ignored_reason,
    ledger_sequence: accepted.sequence,
    entitlement_key: accepted.entitlementKey,
    currency_key: accepted.currencyKey,
    amount: accepted.amount,
    projection_state: "pending",
    retry_after_ms: 750
  });
}
