"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const runtimePath = process.env.NAKAMA_RUNTIME_ARTIFACT;
const migrationPath = process.env.NAKAMA_MIGRATION_ARTIFACT;

if (!runtimePath || !migrationPath) {
  throw new Error(
    "NAKAMA_RUNTIME_ARTIFACT and NAKAMA_MIGRATION_ARTIFACT are required."
  );
}

const runtimeSource = fs.readFileSync(runtimePath, "utf8");
const migrationSource = fs.readFileSync(migrationPath, "utf8");

function asArrayBuffer(buffer) {
  return buffer.buffer.slice(
    buffer.byteOffset,
    buffer.byteOffset + buffer.byteLength
  );
}

function completeContext(overrides = {}) {
  const context = {
    env: {
      SUCH_PLATFORM_APP_ID: "moon_launch",
      SUCH_PLATFORM_SCHEMA_VERSION: "4",
      SUCH_PLATFORM_SOURCE_COMMIT: "a".repeat(40),
      SUCH_PLATFORM_RUNTIME_SHA256: "b".repeat(64),
      SUCH_PLATFORM_MIGRATION_SHA256: "c".repeat(64),
      SUCH_PLATFORM_CONTRACT_VERSION: "1",
      SUCH_PLATFORM_CONTRACT_COMMIT:
        "90a11e5c21ff1fbe3cec2522c837edd3996a9bf2",
      SUCH_IDP_CONSUME_URL:
        "https://idp.internal.example/internal/consume-nakama-ticket",
      SUCH_IDP_CONSUMER_TOKEN: "i".repeat(32),
      SUCH_ENTITLEMENT_PROVIDER_URL:
        "https://entitlements.internal.example/v1/provider-events/moon_launch",
      SUCH_ENTITLEMENT_PROVIDER_TOKEN: "p".repeat(32),
      SUCH_ENTITLEMENT_PROJECTION_HMAC_KEY: "e".repeat(32),
      SUCH_CURRENCY_PROJECTION_HMAC_KEY: "u".repeat(32),
      SUCH_ROOM_SEED_HMAC_KEY: "r".repeat(32),
      SUCH_IAP_APPLE_PRODUCT_IDS: "software.such.moonlaunch.premium.test",
      SUCH_IAP_GOOGLE_PRODUCT_IDS: "software.such.moonlaunch.premium.test"
    },
    executionMode: "run_once",
    node: "test",
    version: "3.40.0"
  };
  return Object.assign(context, overrides);
}

function makeLogger() {
  const records = [];
  const logger = {records};
  for (const level of ["debug", "info", "warn", "error"]) {
    logger[level] = (...args) => records.push([level, ...args]);
  }
  logger.withField = () => logger;
  logger.withFields = () => logger;
  logger.getFields = () => ({});
  return logger;
}

class FakeNakama {
  constructor(options = {}) {
    this.options = options;
    this.execCalls = [];
    this.queryCalls = [];
    this.httpCalls = [];
    this.events = [];
    this.current = new Map();
    this.currencyEvents = [];
    this.currencyCurrent = new Map();
    this.leaderboards = [];
  }

  leaderboardCreate(id, authoritative, sortOrder, operator, resetSchedule, metadata) {
    this.leaderboards.push({
      id, authoritative, sortOrder, operator, resetSchedule, metadata
    });
  }

  sha256Hash(value) {
    return crypto.createHash("sha256").update(value, "utf8").digest("hex");
  }

  hmacSha256Hash(value, key) {
    return asArrayBuffer(
      crypto.createHmac("sha256", key).update(value, "utf8").digest()
    );
  }

  secureRandomBytes(count) {
    return asArrayBuffer(Buffer.alloc(count, 0x5a));
  }

  base64UrlEncode(value) {
    return Buffer.from(value).toString("base64url");
  }

  httpRequest(url, method, headers, body, timeout, insecure) {
    this.httpCalls.push({url, method, headers, body, timeout, insecure});
    if (this.options.httpError) {
      throw new Error("simulated private IdP outage");
    }
    const response = this.options.httpResponse || {
      contract_version: 1,
      app_id: "moon_launch",
      sub: "usr_01K1C8Q5MBK3Y0XN3V2ND5GXYZ"
    };
    return {
      code: this.options.httpCode || 200,
      headers: [],
      body: JSON.stringify(response)
    };
  }

  sqlExec(query, args = []) {
    this.execCalls.push({query, args});
    if (
      query.includes("SET state = 'EXPIRED'") &&
      this.room &&
      this.room.state === "OPEN" &&
      Date.parse(this.room.expires_at) <= Date.now()
    ) {
      this.room.state = "EXPIRED";
      this.room.closed_at = this.room.closed_at || new Date().toISOString();
      return {rowsAffected: 1};
    }
    if (query.includes("SET state = 'CLOSED'")) {
      if (
        this.room &&
        this.room.room_code === args[0] &&
        this.room.host_user_id === args[1] &&
        this.room.state === "OPEN"
      ) {
        this.room.state = "CLOSED";
        this.room.closed_at = new Date().toISOString();
        return {rowsAffected: 1};
      }
      return {rowsAffected: 0};
    }
    return {rowsAffected: this.options.execRowsAffected ?? 1};
  }

  purchaseValidateApple(userId, receipt, persist) {
    this.purchaseCalls = this.purchaseCalls || [];
    this.purchaseCalls.push({provider: "apple", userId, receipt, persist});
    if (this.options.purchaseError) {
      throw new Error("simulated store validation failure");
    }
    return this.options.validatePurchase || {validatedPurchases: []};
  }

  purchaseValidateGoogle(userId, purchase, persist) {
    this.purchaseCalls = this.purchaseCalls || [];
    this.purchaseCalls.push({provider: "google", userId, receipt: purchase, persist});
    if (this.options.purchaseError) {
      throw new Error("simulated store validation failure");
    }
    return this.options.validatePurchase || {validatedPurchases: []};
  }

  sqlQuery(query, args = []) {
    this.queryCalls.push({query, args});
    if (query.includes("such_platform_schema_migration")) {
      return this.options.migrationMissing
        ? []
        : [{migration_id: "004_native_purchase"}];
    }
    if (query.includes("SELECT subject_id FROM such_platform_identity")) {
      return this.options.identityMissing
        ? []
        : [{subject_id: "usr_01MOONLAUNCHSUBJECT"}];
    }
    if (query.includes("FROM such_platform_native_purchase")) {
      if (this.options.nativePurchaseRow) {
        return [this.options.nativePurchaseRow];
      }
      return this.options.nativePurchaseLastOperation
        ? [{
            last_operation: this.options.nativePurchaseLastOperation,
            subject_id: "usr_01MOONLAUNCHSUBJECT",
            product_id: "com.suchsoftware.suchmoonlaunch.remove_ads"
          }]
        : [];
    }
    if (query.includes("FROM users WHERE custom_id")) {
      return [{user_id: "11111111-1111-4111-8111-111111111111"}];
    }
    if (query.includes("SELECT 1 AS found FROM such_platform_identity")) {
      return this.options.canonicalSession ? [{found: 1}] : [];
    }
    if (query.includes("FROM such_platform_apply_entitlement_event")) {
      return this.applyEntitlement(args);
    }
    if (query.includes("FROM such_platform_apply_currency_event")) {
      return this.applyCurrency(args);
    }
    if (query.includes("LEFT JOIN such_platform_currency_balance")) {
      if (this.options.currencyIdentityMissing) {
        return [];
      }
      const state = this.currencyCurrent.get(
        "usr_01MOONLAUNCHSUBJECT\nmoonrocks"
      );
      const balance = this.options.currencyBalance ?? state?.balance ?? 0;
      const lastSequence = this.options.currencySequence ?? state?.sequence ?? 0;
      return [{
        balance: String(balance),
        available: String(Math.max(balance, 0)),
        debt: String(Math.max(-balance, 0)),
        last_sequence: String(lastSequence)
      }];
    }
    if (
      query.includes("SELECT 1 AS found FROM such_platform_entitlement e")
    ) {
      return this.options.premium ? [{found: 1}] : [];
    }
    if (query.includes("FROM such_platform_entitlement e")) {
      return this.options.capabilities || [];
    }
    if (query.includes("FROM such_moon_launch_claim_guest")) {
      return [{
        outcome: this.options.claimOutcome || "APPLIED",
        merge_result_hash: "d".repeat(64)
      }];
    }
    if (
      query.includes("FROM such_moon_launch_friendly_room") &&
      query.includes("WHERE match_id")
    ) {
      return (
        this.room &&
        this.room.match_id === args[0] &&
        this.room.host_user_id === args[1] &&
        this.room.state === "OPEN" &&
        Date.parse(this.room.expires_at) > Date.now()
      ) ? [Object.assign({}, this.room)] : [];
    }
    if (query.includes("INSERT INTO such_moon_launch_friendly_room")) {
      if (this.options.roomInsertConflict || this.room) {
        return [];
      }
      this.room = {
        room_code: args[0],
        match_id: args[1],
        host_user_id: args[2],
        guest_user_id: null,
        protocol_version: args[3],
        max_players: args[4],
        state: "OPEN",
        expires_at: args[5],
        closed_at: null
      };
      return [Object.assign({}, this.room)];
    }
    if (
      query.includes("FROM such_moon_launch_friendly_room") &&
      query.includes("WHERE room_code")
    ) {
      return (
        this.room &&
        this.room.room_code === args[0] &&
        this.room.state === "OPEN" &&
        Date.parse(this.room.expires_at) > Date.now()
      ) ? [Object.assign({}, this.room)] : [];
    }
    if (
      query.includes("UPDATE such_moon_launch_friendly_room") &&
      query.includes("guest_user_id = COALESCE")
    ) {
      if (
        this.room &&
        this.room.room_code === args[0] &&
        this.room.state === "OPEN" &&
        Date.parse(this.room.expires_at) > Date.now() &&
        this.room.host_user_id !== args[1] &&
        (
          this.room.guest_user_id === null ||
          this.room.guest_user_id === args[1]
        )
      ) {
        this.room.guest_user_id = args[1];
        return [Object.assign({}, this.room)];
      }
      return [];
    }
    throw new Error(`Unexpected SQL query: ${query}`);
  }

  matchGet(matchId) {
    if (typeof this.options.matchGet === "function") {
      return this.options.matchGet(matchId);
    }
    return this.options.match || null;
  }

  applyEntitlement(args) {
    const [
      eventId,
      subjectId,
      entitlementKey,
      sequence,
      operation,
      idempotencyKey,
      eventDigest,
      effectiveAt,
      expiresAt
    ] = args;
    const stateKey = `${subjectId}\n${entitlementKey}`;
    const prior = this.events.find((candidate) =>
      candidate.eventId === eventId ||
      candidate.idempotencyKey === idempotencyKey ||
      (
        candidate.stateKey === stateKey &&
        candidate.sequence === sequence
      )
    );
    if (prior) {
      if (
        prior.eventDigest === eventDigest &&
        prior.stateKey === stateKey &&
        prior.sequence === sequence
      ) {
        return [{outcome: "DUPLICATE", last_sequence: String(sequence)}];
      }
      throw new Error("conflicting entitlement event");
    }
    const current = this.current.get(stateKey);
    if (current && sequence <= current.sequence) {
      throw new Error("non-increasing entitlement sequence");
    }
    const applied = {
      eventId,
      idempotencyKey,
      eventDigest,
      stateKey,
      sequence,
      operation,
      effectiveAt,
      expiresAt
    };
    this.events.push(applied);
    this.current.set(stateKey, applied);
    return [{outcome: "APPLIED", last_sequence: String(sequence)}];
  }

  applyCurrency(args) {
    const [
      eventId,
      subjectId,
      currencyKey,
      sequence,
      operation,
      amount,
      originalEventId,
      idempotencyKey,
      eventDigest
    ] = args;
    const stateKey = `${subjectId}\n${currencyKey}`;
    const prior = this.currencyEvents.find((candidate) =>
      candidate.eventId === eventId ||
      candidate.idempotencyKey === idempotencyKey ||
      (
        candidate.stateKey === stateKey &&
        candidate.sequence === sequence
      )
    );
    if (prior) {
      if (
        prior.eventDigest === eventDigest &&
        prior.stateKey === stateKey &&
        prior.sequence === sequence
      ) {
        return [{
          outcome: "DUPLICATE",
          balance: String(prior.balance),
          last_sequence: String(sequence)
        }];
      }
      throw new Error("conflicting currency event");
    }
    const current = this.currencyCurrent.get(stateKey);
    if (current && sequence <= current.sequence) {
      throw new Error("non-increasing currency sequence");
    }

    let delta;
    if (operation === "CREDIT") {
      if (originalEventId !== null) {
        throw new Error("credit cannot reference an original event");
      }
      delta = amount;
    } else {
      const original = this.currencyEvents.find((candidate) =>
        candidate.eventId === originalEventId &&
        candidate.operation === "CREDIT" &&
        candidate.stateKey === stateKey &&
        candidate.amount === amount
      );
      if (!original) {
        throw new Error("currency lifecycle original is invalid");
      }
      const lifecycle = this.currencyEvents
        .filter((candidate) =>
          candidate.eventId === originalEventId ||
          candidate.originalEventId === originalEventId
        )
        .sort((left, right) => right.sequence - left.sequence)[0];
      if (
        operation === "REVERSE" &&
        lifecycle.operation !== "CREDIT" &&
        lifecycle.operation !== "REINSTATE"
      ) {
        throw new Error("currency credit is already reversed");
      }
      if (operation === "REINSTATE" && lifecycle.operation !== "REVERSE") {
        throw new Error("currency credit is not reversed");
      }
      delta = operation === "REVERSE" ? -amount : amount;
    }
    const balance = (current?.balance ?? 0) + delta;
    const applied = {
      eventId,
      originalEventId,
      idempotencyKey,
      eventDigest,
      stateKey,
      sequence,
      operation,
      amount,
      balance
    };
    this.currencyEvents.push(applied);
    this.currencyCurrent.set(stateKey, applied);
    return [{
      outcome: "APPLIED",
      balance: String(balance),
      last_sequence: String(sequence)
    }];
  }

  stateHash() {
    const material = [...this.current.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, value]) => [
        key,
        value.sequence,
        value.operation,
        value.effectiveAt,
        value.expiresAt
      ]);
    return crypto
      .createHash("sha256")
      .update(JSON.stringify(material), "utf8")
      .digest("hex");
  }

  currencyStateHash() {
    const material = [...this.currencyCurrent.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, value]) => [key, value.sequence, value.balance]);
    return crypto
      .createHash("sha256")
      .update(JSON.stringify(material), "utf8")
      .digest("hex");
  }
}

function initialize(nk = new FakeNakama()) {
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(runtimeSource, sandbox, {filename: runtimePath});
  assert.equal(typeof sandbox.InitModule, "function");

  const rpcs = new Map();
  const hooks = {};
  const initializer = {
    registerRpc(name, handler) {
      rpcs.set(name, handler);
    },
    registerBeforeAuthenticateCustom(handler) {
      hooks.beforeAuthenticateCustom = handler;
    },
    registerAfterAuthenticateCustom(handler) {
      hooks.afterAuthenticateCustom = handler;
    }
  };
  const logger = makeLogger();
  sandbox.InitModule(completeContext(), logger, nk, initializer);
  // Init declares the leaderboards, which issues real writes. Tests index the
  // recorded calls from zero, so drop the initialisation prefix here instead of
  // teaching every assertion to skip it. What init declared stays available on
  // nk.leaderboards for the tests that care.
  nk.execCalls.length = 0;
  nk.queryCalls.length = 0;
  return {rpcs, hooks, logger, nk};
}

function entitlementEvent(sequence, operation, suffix = String(sequence)) {
  return {
    contract_version: 1,
    event_id: `01MOONLAUNCHEVENT${suffix.padStart(4, "0")}`,
    sequence,
    operation,
    app_id: "moon_launch",
    subject_id: "usr_01MOONLAUNCHSUBJECT",
    entitlement_key: "premium",
    idempotency_key:
      `test:moon_launch:transaction:${suffix}:premium:${operation}`,
    effective_at: `2026-07-29T15:00:${String(sequence).padStart(2, "0")}Z`,
    expires_at: null,
    source: {
      provider: "test",
      transaction_id: `transaction-${suffix}`,
      line_id: "premium_lifetime_v1",
      occurred_at: "2026-07-29T14:59:58Z"
    }
  };
}

function signedContext(payload, key = "e".repeat(32), overrides = {}) {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = crypto
    .createHmac("sha256", key)
    .update(`${timestamp}\n${payload}`, "utf8")
    .digest("hex");
  return completeContext(Object.assign({
    headers: {
      "X-Such-Entitlement-Timestamp": [timestamp],
      "X-Such-Entitlement-Signature": [`v1=${signature}`]
    }
  }, overrides));
}

function currencyEvent(
  sequence,
  operation,
  suffix = String(sequence),
  originalEventId = null,
  amount = 10000,
  lineId = "moonrocks_10k_v1"
) {
  return {
    contract_version: 1,
    event_id: `01MOONCURRENCYEVENT${suffix.padStart(4, "0")}`,
    sequence,
    operation,
    app_id: "moon_launch",
    subject_id: "usr_01MOONLAUNCHSUBJECT",
    currency_key: "moonrocks",
    amount,
    original_event_id: originalEventId,
    idempotency_key:
      `test:moon_launch:transaction:${suffix}:moonrocks:${operation}`,
    effective_at: `2026-08-03T15:00:${String(sequence).padStart(2, "0")}Z`,
    source: {
      provider: "test",
      transaction_id: `transaction-${suffix}`,
      line_id: lineId,
      occurred_at: "2026-08-03T14:59:58Z"
    }
  };
}

function signedCurrencyContext(payload, key = "u".repeat(32), overrides = {}) {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = crypto
    .createHmac("sha256", key)
    .update(`${timestamp}\n${payload}`, "utf8")
    .digest("hex");
  return completeContext(Object.assign({
    headers: {
      "X-Such-Currency-Timestamp": [timestamp],
      "X-Such-Currency-Signature": [`v1=${signature}`]
    }
  }, overrides));
}

test("registers the complete common App Platform surface", () => {
  const {rpcs, hooks} = initialize();
  assert.deepEqual(
    [...rpcs.keys()].sort(),
    [
      "app_entitlement_projection",
      "app_currency_projection",
      "app_platform_build_info",
      "app_platform_claim_guest",
      "app_platform_currency_balance",
      "app_platform_entitlements",
      "app_platform_health",
      "app_platform_prepare_guest_claim",
      "app_platform_readiness",
      "app_platform_validate_iap",
      "moon_launch_leaderboard",
      "moon_launch_room_close",
      "moon_launch_room_register",
      "moon_launch_room_resolve",
      "moon_launch_submit_score"
    ].sort()
  );
  assert.equal(typeof hooks.beforeAuthenticateCustom, "function");
  assert.equal(typeof hooks.afterAuthenticateCustom, "function");
});

test("health is process-only and does not echo payload, user, or secrets", () => {
  const {rpcs, logger, nk} = initialize();
  const context = completeContext({
    userId: "11111111-1111-4111-8111-111111111111"
  });
  const response = rpcs.get("app_platform_health")(
    context,
    logger,
    nk,
    "secret-shaped-payload"
  );
  assert.deepEqual(JSON.parse(response), {
    status: "ok",
    app_id: "moon_launch",
    contract_version: 1
  });
  assert.doesNotMatch(response, /secret|11111111|IDP_/);
});

test("readiness and build info require exact pins and applied schema", () => {
  const {rpcs, logger, nk} = initialize();
  const context = completeContext();
  assert.equal(
    JSON.parse(
      rpcs.get("app_platform_readiness")(context, logger, nk, "")
    ).ready,
    true
  );
  const build = JSON.parse(
    rpcs.get("app_platform_build_info")(context, logger, nk, "")
  );
  assert.equal(build.app_id, "moon_launch");
  assert.equal(build.schema_version, 4);
  assert.equal(build.source_commit, "a".repeat(40));

  const unpinned = completeContext();
  unpinned.env = Object.assign({}, unpinned.env, {
    SUCH_PLATFORM_CONTRACT_COMMIT: "f".repeat(40)
  });
  assert.throws(
    () => rpcs.get("app_platform_readiness")(unpinned, logger, nk, ""),
    (error) => error.code === 9
  );

  const noNativeCatalog = completeContext();
  delete noNativeCatalog.env.SUCH_IAP_APPLE_PRODUCT_IDS;
  assert.throws(
    () => rpcs.get("app_platform_readiness")(
      noNativeCatalog,
      logger,
      nk,
      ""
    ),
    (error) => error.code === 9
  );

  const reusedSecret = completeContext();
  reusedSecret.env.SUCH_ROOM_SEED_HMAC_KEY =
    reusedSecret.env.SUCH_ENTITLEMENT_PROJECTION_HMAC_KEY;
  assert.throws(
    () => rpcs.get("app_platform_readiness")(reusedSecret, logger, nk, ""),
    (error) => error.code === 9
  );

  const reusedCurrencySecret = completeContext();
  reusedCurrencySecret.env.SUCH_CURRENCY_PROJECTION_HMAC_KEY =
    reusedCurrencySecret.env.SUCH_ENTITLEMENT_PROJECTION_HMAC_KEY;
  assert.throws(
    () => rpcs.get("app_platform_readiness")(
      reusedCurrencySecret,
      logger,
      nk,
      ""
    ),
    (error) => error.code === 9
  );
});

test("custom authentication consumes an app-bound ticket and derives a private ID", () => {
  const {hooks, logger, nk} = initialize();
  const ticket = "ticket_01MOONLAUNCH_ONE_USE";
  const request = {
    account: {
      id: ticket,
      vars: {premium: "true", subject_id: "client-injected"}
    },
    create: true
  };
  const rewritten = hooks.beforeAuthenticateCustom(
    completeContext(),
    logger,
    nk,
    request
  );
  const expectedDigest = crypto
    .createHash("sha256")
    .update("moon_launch\nusr_01K1C8Q5MBK3Y0XN3V2ND5GXYZ", "utf8")
    .digest("hex");
  assert.equal(rewritten.account.id, `moon-launch-${expectedDigest}`);
  assert.deepEqual(JSON.parse(nk.httpCalls[0].body), {
    contract_version: 1,
    app_id: "moon_launch",
    ticket
  });
  assert.equal(nk.httpCalls[0].method, "post");
  assert.equal(nk.httpCalls[0].insecure, false);
  assert.equal(nk.execCalls[0].args[1], rewritten.account.id);
  assert.deepEqual(Object.keys(rewritten.account.vars), []);
  assert.doesNotMatch(JSON.stringify(logger.records), new RegExp(ticket));
});

test("custom authentication rejects wrong-audience and malformed IdP responses", () => {
  const wrongAudience = new FakeNakama({
    httpResponse: {
      contract_version: 1,
      app_id: "vegan_iq",
      sub: "usr_01K1C8Q5MBK3Y0XN3V2ND5GXYZ"
    }
  });
  const wrong = initialize(wrongAudience);
  assert.throws(
    () => wrong.hooks.beforeAuthenticateCustom(
      completeContext(),
      wrong.logger,
      wrong.nk,
      {account: {id: "ticket_01MOONLAUNCH_WRONG_APP"}}
    ),
    (error) => error.code === 16
  );

  const extraField = new FakeNakama({
    httpResponse: {
      contract_version: 1,
      app_id: "moon_launch",
      sub: "usr_01K1C8Q5MBK3Y0XN3V2ND5GXYZ",
      email: "must-not-be-returned@example.invalid"
    }
  });
  const extra = initialize(extraField);
  assert.throws(
    () => extra.hooks.beforeAuthenticateCustom(
      completeContext(),
      extra.logger,
      extra.nk,
      {account: {id: "ticket_01MOONLAUNCH_EXTRA_FIELD"}}
    ),
    (error) => error.code === 16
  );
});

test("entitlement parser, HMAC, duplicate, revoke, and reinstate are replay-safe", () => {
  const nk = new FakeNakama();
  const {rpcs, logger} = initialize(nk);
  const projection = rpcs.get("app_entitlement_projection");

  const grantPayload = JSON.stringify(entitlementEvent(1, "GRANT", "grant"));
  assert.equal(
    JSON.parse(
      projection(signedContext(grantPayload), logger, nk, grantPayload)
    ).outcome,
    "applied"
  );
  assert.equal(
    JSON.parse(
      projection(signedContext(grantPayload), logger, nk, grantPayload)
    ).outcome,
    "duplicate"
  );

  const reorderedPayload = JSON.stringify(
    entitlementEvent(1, "REVOKE", "reordered")
  );
  assert.throws(
    () => projection(
      signedContext(reorderedPayload),
      logger,
      nk,
      reorderedPayload
    ),
    /conflicting|non-increasing/
  );

  const revokePayload = JSON.stringify(entitlementEvent(2, "REVOKE", "revoke"));
  projection(signedContext(revokePayload), logger, nk, revokePayload);
  const reinstatePayload = JSON.stringify(
    entitlementEvent(3, "REINSTATE", "reinstate")
  );
  projection(signedContext(reinstatePayload), logger, nk, reinstatePayload);

  const current = nk.current.get("usr_01MOONLAUNCHSUBJECT\npremium");
  assert.equal(current.sequence, 3);
  assert.equal(current.operation, "REINSTATE");
});

test("entitlement projection rejects client sessions, bad MACs, and duplicate headers", () => {
  const {rpcs, logger, nk} = initialize();
  const projection = rpcs.get("app_entitlement_projection");
  const payload = JSON.stringify(entitlementEvent(1, "GRANT", "guards"));

  assert.throws(
    () => projection(
      signedContext(payload, "e".repeat(32), {
        userId: "11111111-1111-4111-8111-111111111111"
      }),
      logger,
      nk,
      payload
    ),
    (error) => error.code === 7
  );

  assert.throws(
    () => projection(signedContext(payload, "x".repeat(32)), logger, nk, payload),
    (error) => error.code === 16
  );

  const duplicate = signedContext(payload);
  duplicate.headers["x-such-entitlement-timestamp"] =
    duplicate.headers["X-Such-Entitlement-Timestamp"];
  assert.throws(
    () => projection(duplicate, logger, nk, payload),
    (error) => error.code === 16
  );
});

test("entitlement parser rejects impossible dates and additional fields", () => {
  const {rpcs, logger, nk} = initialize();
  const projection = rpcs.get("app_entitlement_projection");

  const impossible = entitlementEvent(1, "GRANT", "bad-date");
  impossible.effective_at = "2026-02-30T15:00:00Z";
  const impossiblePayload = JSON.stringify(impossible);
  assert.throws(
    () => projection(
      signedContext(impossiblePayload),
      logger,
      nk,
      impossiblePayload
    ),
    (error) => error.code === 3
  );

  const additional = entitlementEvent(1, "GRANT", "extra");
  additional.email = "not-allowed@example.invalid";
  const additionalPayload = JSON.stringify(additional);
  assert.throws(
    () => projection(
      signedContext(additionalPayload),
      logger,
      nk,
      additionalPayload
    ),
    (error) => error.code === 3
  );
});

test("full entitlement replay converges to the same projection hash", () => {
  const events = [
    entitlementEvent(10, "GRANT", "full-grant"),
    entitlementEvent(11, "REVOKE", "full-revoke"),
    entitlementEvent(12, "REINSTATE", "full-reinstate")
  ];
  const replay = (includeDuplicates) => {
    const nk = new FakeNakama();
    const {rpcs, logger} = initialize(nk);
    const projection = rpcs.get("app_entitlement_projection");
    for (const event of events) {
      const payload = JSON.stringify(event);
      projection(signedContext(payload), logger, nk, payload);
      if (includeDuplicates) {
        projection(signedContext(payload), logger, nk, payload);
      }
    }
    return nk.stateHash();
  };
  assert.equal(replay(false), replay(true));
});

test("currency credit, reverse, and reinstate are exact and replay-safe", () => {
  const nk = new FakeNakama();
  const {rpcs, logger} = initialize(nk);
  const projection = rpcs.get("app_currency_projection");
  const credit = currencyEvent(1, "CREDIT", "credit");
  const creditPayload = JSON.stringify(credit);
  assert.deepEqual(
    JSON.parse(
      projection(
        signedCurrencyContext(creditPayload),
        logger,
        nk,
        creditPayload
      )
    ),
    {
      outcome: "applied",
      currency_key: "moonrocks",
      balance: "10000",
      last_sequence: "1"
    }
  );
  assert.equal(
    JSON.parse(
      projection(
        signedCurrencyContext(creditPayload),
        logger,
        nk,
        creditPayload
      )
    ).outcome,
    "duplicate"
  );

  const reverse = currencyEvent(2, "REVERSE", "reverse", credit.event_id);
  const reversePayload = JSON.stringify(reverse);
  assert.equal(
    JSON.parse(
      projection(
        signedCurrencyContext(reversePayload),
        logger,
        nk,
        reversePayload
      )
    ).balance,
    "0"
  );

  const reinstate = currencyEvent(
    3,
    "REINSTATE",
    "reinstate",
    credit.event_id
  );
  const reinstatePayload = JSON.stringify(reinstate);
  assert.equal(
    JSON.parse(
      projection(
        signedCurrencyContext(reinstatePayload),
        logger,
        nk,
        reinstatePayload
      )
    ).balance,
    "10000"
  );
});

test("currency projection rejects client sessions, wrong keys, and bad packs", () => {
  const {rpcs, logger, nk} = initialize();
  const projection = rpcs.get("app_currency_projection");
  const event = currencyEvent(1, "CREDIT", "guards");
  const payload = JSON.stringify(event);

  assert.throws(
    () => projection(
      signedCurrencyContext(payload, "u".repeat(32), {
        userId: "11111111-1111-4111-8111-111111111111"
      }),
      logger,
      nk,
      payload
    ),
    (error) => error.code === 7
  );
  assert.throws(
    () => projection(
      signedCurrencyContext(payload, "e".repeat(32)),
      logger,
      nk,
      payload
    ),
    (error) => error.code === 16
  );

  const wrongAmount = currencyEvent(
    1,
    "CREDIT",
    "wrong-amount",
    null,
    50000,
    "moonrocks_10k_v1"
  );
  const wrongAmountPayload = JSON.stringify(wrongAmount);
  assert.throws(
    () => projection(
      signedCurrencyContext(wrongAmountPayload),
      logger,
      nk,
      wrongAmountPayload
    ),
    (error) => error.code === 3
  );

  const extra = currencyEvent(1, "CREDIT", "extra-field");
  extra.price = 1.99;
  const extraPayload = JSON.stringify(extra);
  assert.throws(
    () => projection(
      signedCurrencyContext(extraPayload),
      logger,
      nk,
      extraPayload
    ),
    (error) => error.code === 3
  );
});

test("full currency replay converges with duplicate delivery", () => {
  const credit = currencyEvent(1, "CREDIT", "replay-credit");
  const events = [
    credit,
    currencyEvent(2, "REVERSE", "replay-reverse", credit.event_id),
    currencyEvent(3, "REINSTATE", "replay-reinstate", credit.event_id)
  ];
  const replay = (includeDuplicates) => {
    const nk = new FakeNakama();
    const {rpcs, logger} = initialize(nk);
    const projection = rpcs.get("app_currency_projection");
    for (const event of events) {
      const payload = JSON.stringify(event);
      projection(signedCurrencyContext(payload), logger, nk, payload);
      if (includeDuplicates) {
        projection(signedCurrencyContext(payload), logger, nk, payload);
      }
    }
    return nk.currencyStateHash();
  };
  assert.equal(replay(false), replay(true));
});

test("authenticated currency balance exposes available funds and refund debt", () => {
  const nk = new FakeNakama({
    currencyBalance: -9000,
    currencySequence: 7
  });
  const {rpcs, logger} = initialize(nk);
  const response = JSON.parse(
    rpcs.get("app_platform_currency_balance")(
      completeContext({
        userId: "11111111-1111-4111-8111-111111111111"
      }),
      logger,
      nk,
      ""
    )
  );
  assert.deepEqual(response, {
    contract_version: 1,
    currency_key: "moonrocks",
    balance: "-9000",
    available: "0",
    debt: "9000",
    last_sequence: "7"
  });
  assert.doesNotMatch(JSON.stringify(response), /apple|google|stripe|crypto/);
});

test("authenticated clients receive only neutral current capabilities", () => {
  const nk = new FakeNakama({
    capabilities: [{
      entitlement_key: "premium",
      operation: "GRANT",
      expires_at: null,
      last_sequence: "41"
    }]
  });
  const {rpcs, logger} = initialize(nk);
  const response = JSON.parse(
    rpcs.get("app_platform_entitlements")(
      completeContext({
        userId: "11111111-1111-4111-8111-111111111111"
      }),
      logger,
      nk,
      ""
    )
  );
  assert.deepEqual(response.capabilities, [{
    key: "premium",
    active: true,
    expires_at: null,
    last_sequence: "41"
  }]);
  assert.doesNotMatch(JSON.stringify(response), /apple|google|stripe|crypto/);
});

test("guest claim preparation stores only the token hash", () => {
  const {rpcs, logger, nk} = initialize();
  const response = JSON.parse(
    rpcs.get("app_platform_prepare_guest_claim")(
      completeContext({
        userId: "22222222-2222-4222-8222-222222222222"
      }),
      logger,
      nk,
      ""
    )
  );
  const insert = nk.execCalls.find((call) =>
    call.query.includes("such_platform_guest_claim_token")
  );
  assert.equal(response.expires_in_seconds, 600);
  assert.equal(insert.args[0], nk.sha256Hash(response.claim_token));
  assert.notEqual(insert.args[0], response.claim_token);
  assert.doesNotMatch(JSON.stringify(insert.args), new RegExp(response.claim_token));
});

test("guest claim hashes the proof and delegates the atomic merge", () => {
  const {rpcs, logger, nk} = initialize();
  const claimToken = "claim_token_01MOONLAUNCH_RECOVERY_PROOF";
  const payload = JSON.stringify({
    claim_token: claimToken,
    idempotency_key: "claim-idempotency-01MOONLAUNCH"
  });
  const response = JSON.parse(
    rpcs.get("app_platform_claim_guest")(
      completeContext({
        userId: "11111111-1111-4111-8111-111111111111"
      }),
      logger,
      nk,
      payload
    )
  );
  const call = nk.queryCalls.find((candidate) =>
    candidate.query.includes("such_moon_launch_claim_guest")
  );
  assert.equal(call.args[0], nk.sha256Hash(claimToken));
  assert.notEqual(call.args[0], claimToken);
  assert.equal(response.outcome, "applied");
  assert.equal(response.merge_result_hash, "d".repeat(64));
});

test("friendly room hosting is Premium-gated and verifies a relayed match", () => {
  const hostId = "11111111-1111-4111-8111-111111111111";
  const matchId = "relayed.match-01";
  const payload = JSON.stringify({
    match_id: matchId,
    protocol_version: 1,
    max_players: 2
  });

  const free = initialize(new FakeNakama({
    match: {matchId, authoritative: false, size: 1, label: ""}
  }));
  assert.throws(
    () => free.rpcs.get("moon_launch_room_register")(
      completeContext({userId: hostId}),
      free.logger,
      free.nk,
      payload
    ),
    (error) => error.code === 7
  );

  const premium = initialize(new FakeNakama({
    premium: true,
    match: {matchId, authoritative: false, size: 1, label: ""}
  }));
  const descriptor = JSON.parse(
    premium.rpcs.get("moon_launch_room_register")(
      completeContext({userId: hostId}),
      premium.logger,
      premium.nk,
      payload
    )
  );
  assert.match(descriptor.room_code, /^[A-HJ-NP-Z2-9]{6}$/);
  assert.equal(descriptor.match_id, matchId);
  assert.equal(descriptor.protocol_version, 1);
  assert.equal(descriptor.max_players, 2);
  assert.deepEqual(Object.keys(descriptor).sort(), [
    "expires_at",
    "match_id",
    "max_players",
    "protocol_version",
    "room_code"
  ]);
  assert.doesNotMatch(JSON.stringify(descriptor), /user|premium|purchase/);

  const authoritative = initialize(new FakeNakama({
    premium: true,
    match: {matchId, authoritative: true, size: 1, label: ""}
  }));
  assert.throws(
    () => authoritative.rpcs.get("moon_launch_room_register")(
      completeContext({userId: hostId}),
      authoritative.logger,
      authoritative.nk,
      payload
    ),
    (error) => error.code === 5
  );
});

test("free authenticated guests resolve once and hosts close their rooms", () => {
  const hostId = "11111111-1111-4111-8111-111111111111";
  const guestId = "22222222-2222-4222-8222-222222222222";
  const otherId = "33333333-3333-4333-8333-333333333333";
  const matchId = "relayed.match-02";
  const nk = new FakeNakama({
    premium: true,
    match: {matchId, authoritative: false, size: 1, label: ""}
  });
  const {rpcs, logger} = initialize(nk);
  const descriptor = JSON.parse(
    rpcs.get("moon_launch_room_register")(
      completeContext({userId: hostId}),
      logger,
      nk,
      JSON.stringify({
        match_id: matchId,
        protocol_version: 1,
        max_players: 2
      })
    )
  );
  const codePayload = JSON.stringify({room_code: descriptor.room_code});

  const joined = JSON.parse(
    rpcs.get("moon_launch_room_resolve")(
      completeContext({userId: guestId}),
      logger,
      nk,
      codePayload
    )
  );
  assert.equal(joined.match_id, matchId);
  assert.equal(nk.room.guest_user_id, guestId);

  assert.throws(
    () => rpcs.get("moon_launch_room_resolve")(
      completeContext({userId: otherId}),
      logger,
      nk,
      codePayload
    ),
    (error) => error.code === 9
  );
  assert.throws(
    () => rpcs.get("moon_launch_room_close")(
      completeContext({userId: guestId}),
      logger,
      nk,
      codePayload
    ),
    (error) => error.code === 5
  );
  assert.deepEqual(
    JSON.parse(
      rpcs.get("moon_launch_room_close")(
        completeContext({userId: hostId}),
        logger,
        nk,
        codePayload
      )
    ),
    {closed: true}
  );
  assert.equal(nk.room.state, "CLOSED");
});

test("room requests reject expiry, host self-join, and oversized payloads", () => {
  const hostId = "11111111-1111-4111-8111-111111111111";
  const matchId = "relayed.match-03";
  const nk = new FakeNakama({
    premium: true,
    match: {matchId, authoritative: false, size: 1, label: ""}
  });
  const {rpcs, logger} = initialize(nk);
  const descriptor = JSON.parse(
    rpcs.get("moon_launch_room_register")(
      completeContext({userId: hostId}),
      logger,
      nk,
      JSON.stringify({
        match_id: matchId,
        protocol_version: 1,
        max_players: 2
      })
    )
  );
  const codePayload = JSON.stringify({room_code: descriptor.room_code});
  assert.throws(
    () => rpcs.get("moon_launch_room_resolve")(
      completeContext({userId: hostId}),
      logger,
      nk,
      codePayload
    ),
    (error) => error.code === 9
  );
  nk.room.expires_at = new Date(Date.now() - 1000).toISOString();
  assert.throws(
    () => rpcs.get("moon_launch_room_resolve")(
      completeContext({
        userId: "22222222-2222-4222-8222-222222222222"
      }),
      logger,
      nk,
      codePayload
    ),
    (error) => error.code === 5
  );
  assert.throws(
    () => rpcs.get("moon_launch_room_register")(
      completeContext({userId: hostId}),
      logger,
      nk,
      "x".repeat(1025)
    ),
    (error) => error.code === 3
  );
});

test("migration bundle is ordered, transactional, additive, and repeatable", () => {
  assert.match(migrationSource, /\\set ON_ERROR_STOP on/);
  assert.match(migrationSource, /\bBEGIN;/);
  assert.match(migrationSource, /\bCOMMIT;/);
  for (const table of [
    "such_platform_identity",
    "such_platform_entitlement",
    "such_platform_guest_claim",
    "such_platform_migration_operation",
    "such_moon_launch_friendly_room",
    "such_platform_currency_balance",
    "such_platform_currency_event"
  ]) {
    assert.match(
      migrationSource,
      new RegExp(`CREATE TABLE IF NOT EXISTS ${table}`)
    );
  }
  assert.match(
    migrationSource,
    /CREATE OR REPLACE FUNCTION such_platform_apply_entitlement_event/
  );
  assert.match(
    migrationSource,
    /CREATE OR REPLACE FUNCTION such_moon_launch_claim_guest/
  );
  assert.match(
    migrationSource,
    /CREATE OR REPLACE FUNCTION such_platform_apply_currency_event/
  );
  assert.match(migrationSource, /ON CONFLICT \(schema_version\) DO NOTHING/);
  assert.doesNotMatch(
    migrationSource.toLowerCase(),
    /\b(?:drop\s+table|truncate|delete\s+from)\b/
  );
  assert.equal(path.basename(migrationPath), "migrations.sql");
});

// --- app_platform_validate_iap -------------------------------------------

function validatedApplePurchase(overrides = {}) {
  return Object.assign({
    userId: "11111111-1111-4111-8111-111111111111",
    productId: "com.suchsoftware.suchmoonlaunch.remove_ads",
    transactionId: "2000000123456789",
    store: "APPLE_APP_STORE",
    purchaseTime: 1767200000000,
    createTime: 1767200000000,
    updateTime: 1767200001000,
    refundTime: 0,
    providerResponse: "{}",
    environment: "PRODUCTION",
    seenBefore: false
  }, overrides);
}

function ledgerEntitlementEvent(overrides = {}) {
  return Object.assign({
    $schema: "https://such.software/contracts/app-platform/v1/entitlement-event.schema.json",
    contract_version: 1,
    event_id: "01MOONLAUNCHIAPEVENT0001",
    sequence: 41,
    operation: "GRANT",
    app_id: "moon_launch",
    subject_id: "usr_01MOONLAUNCHSUBJECT",
    entitlement_key: "race_unlimited",
    idempotency_key:
      "apple:2000000123456789:2000000123456789:GRANT:moon_launch:race_unlimited",
    effective_at: "2026-08-15T12:00:00.000Z",
    expires_at: null,
    source: {
      provider: "apple",
      transaction_id: "2000000123456789",
      line_id: "2000000123456789",
      occurred_at: "2026-08-15T11:59:58.000Z"
    },
    metadata: {
      product_id: "com.suchsoftware.suchmoonlaunch.remove_ads",
      offer_id: "race_unlimited_lifetime_v1",
      catalog_version: "portfolio-v1-test",
      environment: "production",
      provider_line_id: "2000000123456789",
      validation_authority: "nakama_iap_validate_v1",
      validation_verified_at: "2026-08-15T12:00:00.000Z"
    }
  }, overrides);
}

function ledgerCurrencyEvent(overrides = {}) {
  return Object.assign({
    $schema: "https://such.software/contracts/app-platform/v1/currency-event.schema.json",
    contract_version: 1,
    event_id: "01MOONLAUNCHIAPCURR0001",
    sequence: 7,
    operation: "CREDIT",
    app_id: "moon_launch",
    subject_id: "usr_01MOONLAUNCHSUBJECT",
    currency_key: "moonrocks",
    amount: 10000,
    original_event_id: null,
    idempotency_key:
      "apple:2000000123456790:2000000123456790:CREDIT:moon_launch:moonrocks",
    effective_at: "2026-08-15T12:00:00.000Z",
    // The ledger sets a currency event's source.line_id to the catalog
    // offer_id, NOT the transaction id Nakama submitted as line_id. The
    // binding check must tolerate exactly this and nothing else.
    source: {
      provider: "apple",
      transaction_id: "2000000123456790",
      line_id: "moonrocks_10k_v1",
      occurred_at: "2026-08-15T11:59:58.000Z"
    },
    metadata: {
      product_id: "com.suchsoftware.suchmoonlaunch.moonrocks_10k",
      offer_id: "moonrocks_10k_v1",
      catalog_version: "portfolio-v1-test",
      environment: "production",
      provider_line_id: "2000000123456790",
      validation_authority: "nakama_iap_validate_v1",
      validation_verified_at: "2026-08-15T12:00:00.000Z"
    }
  }, overrides);
}

function ledgerAccepted(event) {
  return {ok: true, duplicate: false, applied: true, ignored_reason: null, event};
}

function iapContext(overrides = {}) {
  return completeContext(Object.assign({
    userId: "11111111-1111-4111-8111-111111111111",
    env: Object.assign({}, completeContext().env, {
      SUCH_IAP_APPLE_PRODUCT_IDS:
        "com.suchsoftware.suchmoonlaunch.remove_ads," +
        "com.suchsoftware.suchmoonlaunch.moonrocks_10k," +
        "com.suchsoftware.suchmoonlaunch.moonrocks_50k",
      SUCH_IAP_GOOGLE_PRODUCT_IDS: "com.suchsoftware.suchmoonlaunch.remove_ads"
    })
  }, overrides));
}

function iapRequest(overrides = {}) {
  return JSON.stringify(Object.assign({
    provider: "apple",
    product_id: "com.suchsoftware.suchmoonlaunch.remove_ads",
    receipt: "r".repeat(64)
  }, overrides));
}

test("validate_iap requires authentication", () => {
  const nk = new FakeNakama();
  const {rpcs, logger} = initialize(nk);
  const rpc = rpcs.get("app_platform_validate_iap");
  assert.equal(typeof rpc, "function");
  assert.throws(
    () => rpc(iapContext({userId: ""}), logger, nk, iapRequest()),
    (error) => /Authentication required/.test(String(error && error.message))
  );
});

test("validate_iap rejects malformed and off-catalog requests", () => {
  const nk = new FakeNakama();
  const {rpcs, logger} = initialize(nk);
  const rpc = rpcs.get("app_platform_validate_iap");
  for (const bad of [
    "",
    "not json",
    JSON.stringify({provider: "apple", product_id: "x"}),
    iapRequest({extra: 1}),
    iapRequest({provider: "amazon"}),
    iapRequest({receipt: "short"})
  ]) {
    assert.throws(() => rpc(iapContext(), logger, nk, bad),
      (error) => /Purchase validation request is|Purchase product is not/.test(String(error && error.message)));
  }
  // In catalog form but not deployed for this provider.
  assert.throws(
    () => rpc(iapContext(), logger, nk,
      iapRequest({provider: "google",
        product_id: "com.suchsoftware.suchmoonlaunch.moonrocks_10k"})),
    (error) => /Purchase product is not in the deployed catalog/.test(String(error && error.message))
  );
});

test("validate_iap grants a lifetime product end to end", () => {
  const nk = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase()]},
    httpCode: 201,
    httpResponse: ledgerAccepted(ledgerEntitlementEvent())
  });
  const {rpcs, logger} = initialize(nk);
  const result = JSON.parse(
    rpcs.get("app_platform_validate_iap")(iapContext(), logger, nk, iapRequest())
  );
  assert.equal(result.verified, true);
  assert.equal(result.operation, "GRANT");
  assert.equal(result.entitlement_key, "race_unlimited");
  assert.equal(result.currency_key, null);
  assert.equal(result.ledger_sequence, 41);
  assert.equal(result.projection_state, "pending");
  // The store was asked to validate for the calling user, with persist on.
  assert.deepEqual(nk.purchaseCalls[0], {
    provider: "apple",
    userId: "11111111-1111-4111-8111-111111111111",
    receipt: "r".repeat(64),
    persist: true
  });
  // The ledger call carried the bearer token and an exact-mirror assertion.
  const call = nk.httpCalls.at(-1);
  assert.match(call.url, /\/v1\/provider-events\/moon_launch$/);
  assert.equal(call.headers.Authorization, "Bearer " + "p".repeat(32));
  const sent = JSON.parse(call.body);
  assert.equal(sent.validation.authority, "nakama_iap_validate_v1");
  for (const key of ["provider", "product_id", "transaction_id", "line_id",
    "operation", "environment", "occurred_at", "effective_at", "expires_at"]) {
    assert.deepEqual(sent.validation[key], sent[key],
      `assertion field ${key} must mirror the event body`);
  }
  assert.match(sent.validation.verified_at,
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  // The accepted sequence was recorded locally.
  const insert = nk.execCalls.find((c) =>
    c.query.includes("INSERT INTO such_platform_native_purchase"));
  assert.ok(insert, "native purchase upsert must run");
  assert.deepEqual([...insert.args], [
    "apple", "2000000123456789", "usr_01MOONLAUNCHSUBJECT",
    "com.suchsoftware.suchmoonlaunch.remove_ads", "GRANT", 41
  ]);
});

test("validate_iap accepts a currency response for a consumable", () => {
  const nk = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase({
      productId: "com.suchsoftware.suchmoonlaunch.moonrocks_10k",
      transactionId: "2000000123456790"
    })]},
    httpCode: 201,
    httpResponse: ledgerAccepted(ledgerCurrencyEvent())
  });
  const {rpcs, logger} = initialize(nk);
  const result = JSON.parse(rpcs.get("app_platform_validate_iap")(
    iapContext(), logger, nk,
    iapRequest({product_id: "com.suchsoftware.suchmoonlaunch.moonrocks_10k"})
  ));
  assert.equal(result.verified, true);
  assert.equal(result.entitlement_key, null);
  assert.equal(result.currency_key, "moonrocks");
  assert.equal(result.amount, 10000);
  assert.equal(result.ledger_sequence, 7);
});

test("validate_iap maps a refund to REVOKE and a revoked replay to REINSTATE", () => {
  const refunded = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase({
      refundTime: 1767200002000
    })]},
    httpCode: 201,
    httpResponse: ledgerAccepted(ledgerEntitlementEvent({operation: "REVOKE"}))
  });
  const one = initialize(refunded);
  const revoked = JSON.parse(one.rpcs.get("app_platform_validate_iap")(
    iapContext(), one.logger, refunded, iapRequest()));
  assert.equal(revoked.operation, "REVOKE");

  const reinstated = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase()]},
    nativePurchaseLastOperation: "REVOKE",
    httpCode: 201,
    httpResponse: ledgerAccepted(ledgerEntitlementEvent({operation: "REINSTATE"}))
  });
  const two = initialize(reinstated);
  const result = JSON.parse(two.rpcs.get("app_platform_validate_iap")(
    iapContext(), two.logger, reinstated, iapRequest()));
  assert.equal(result.operation, "REINSTATE");
});

test("validate_iap refuses a receipt the store bound to another account", () => {
  const nk = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase({
      userId: "22222222-2222-4222-8222-222222222222"
    })]}
  });
  const {rpcs, logger} = initialize(nk);
  assert.throws(
    () => rpcs.get("app_platform_validate_iap")(
      iapContext(), logger, nk, iapRequest()),
    (error) => /did not validate this product for the current account/.test(String(error && error.message))
  );
});

test("validate_iap surfaces ledger rejection and outage distinctly", () => {
  for (const [code, pattern] of [
    [422, /does not match the deployed entitlement catalog/],
    [503, /temporarily unavailable/],
    [401, /authentication failed/]
  ]) {
    const nk = new FakeNakama({
      validatePurchase: {validatedPurchases: [validatedApplePurchase()]},
      httpCode: code,
      httpResponse: {error: "x"}
    });
    const {rpcs, logger} = initialize(nk);
    assert.throws(
      () => rpcs.get("app_platform_validate_iap")(
        iapContext(), logger, nk, iapRequest()),
      (error) => pattern.test(String(error && error.message))
    );
  }
});

test("validate_iap rejects a ledger event that does not bind to the caller", () => {
  const cases = [
    // Ledger answered for a different subject.
    ledgerEntitlementEvent({subject_id: "usr_01SOMEBODYELSE0000000"}),
    // Ledger answered about a different transaction.
    ledgerEntitlementEvent({source: Object.assign(
      {}, ledgerEntitlementEvent().source, {transaction_id: "other-txn-0001"})}),
    // Ledger answered about a different product.
    ledgerEntitlementEvent({metadata: Object.assign(
      {}, ledgerEntitlementEvent().metadata,
      {product_id: "com.suchsoftware.suchmoonlaunch.moonrocks_50k"})}),
    // Currency response whose operation does not map from ours
    // (we sent GRANT, so only CREDIT binds).
    ledgerCurrencyEvent({operation: "REVERSE",
      original_event_id: "01MOONLAUNCHIAPCURR0000"})
  ];
  for (const event of cases) {
    const isCurrency = Object.prototype.hasOwnProperty.call(event, "currency_key");
    const requestProduct = isCurrency
      ? "com.suchsoftware.suchmoonlaunch.moonrocks_10k"
      : "com.suchsoftware.suchmoonlaunch.remove_ads";
    const transaction = isCurrency ? "2000000123456790" : "2000000123456789";
    const nk = new FakeNakama({
      validatePurchase: {validatedPurchases: [validatedApplePurchase({
        productId: requestProduct,
        transactionId: transaction
      })]},
      httpCode: 201,
      httpResponse: ledgerAccepted(event)
    });
    const {rpcs, logger} = initialize(nk);
    assert.throws(
      () => rpcs.get("app_platform_validate_iap")(
        iapContext(), logger, nk, iapRequest({product_id: requestProduct})),
      (error) => /did not bind to this account|is invalid/
        .test(String(error && error.message))
    );
    // Nothing may be recorded locally when binding fails.
    assert.equal(nk.execCalls.some((c) =>
      c.query.includes("such_platform_native_purchase")), false);
  }
});

test("validate_iap requires a platform identity row", () => {
  const nk = new FakeNakama({
    identityMissing: true,
    validatePurchase: {validatedPurchases: [validatedApplePurchase()]}
  });
  const {rpcs, logger} = initialize(nk);
  assert.throws(
    () => rpcs.get("app_platform_validate_iap")(
      iapContext(), logger, nk, iapRequest()),
    (error) => /requires a platform identity/.test(String(error && error.message))
  );
});


test("validate_iap uses environment 'test' for Google sandbox purchases", () => {
  const nk = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase({
      store: "GOOGLE_PLAY_STORE",
      environment: "SANDBOX"
    })]},
    httpCode: 201,
    httpResponse: ledgerAccepted(ledgerEntitlementEvent({
      source: Object.assign({}, ledgerEntitlementEvent().source,
        {provider: "google"}),
      metadata: Object.assign({}, ledgerEntitlementEvent().metadata,
        {environment: "test"})
    }))
  });
  const {rpcs, logger} = initialize(nk);
  JSON.parse(rpcs.get("app_platform_validate_iap")(
    iapContext(), logger, nk, iapRequest({provider: "google"})));
  const sent = JSON.parse(nk.httpCalls.at(-1).body);
  assert.equal(sent.environment, "test");
  assert.equal(sent.validation.environment, "test");
});

test("validate_iap rejects prototype-chain product ids", () => {
  const nk = new FakeNakama();
  const {rpcs, logger} = initialize(nk);
  for (const productId of ["constructor", "toString", "hasOwnProperty"]) {
    assert.throws(
      () => rpcs.get("app_platform_validate_iap")(
        iapContext(), logger, nk, iapRequest({product_id: productId})),
      (error) => /Purchase product is not in the deployed catalog/
        .test(String(error && error.message))
    );
  }
});

test("validate_iap refuses a transaction already bound to another account", () => {
  const nk = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase()]},
    nativePurchaseRow: {
      last_operation: "GRANT",
      subject_id: "usr_01SOMEBODYELSE0000000",
      product_id: "com.suchsoftware.suchmoonlaunch.remove_ads"
    }
  });
  const {rpcs, logger} = initialize(nk);
  assert.throws(
    () => rpcs.get("app_platform_validate_iap")(
      iapContext(), logger, nk, iapRequest()),
    (error) => /already bound to another account or product/
      .test(String(error && error.message))
  );
  assert.equal(nk.httpCalls.length, 0,
    "a rebound transaction must never reach the ledger");
});

test("validate_iap does not record locally what the ledger ignored", () => {
  const nk = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase()]},
    httpCode: 200,
    httpResponse: {
      ok: true,
      duplicate: true,
      applied: false,
      ignored_reason: "stale_sequence",
      event: ledgerEntitlementEvent()
    }
  });
  const {rpcs, logger} = initialize(nk);
  const result = JSON.parse(rpcs.get("app_platform_validate_iap")(
    iapContext(), logger, nk, iapRequest()));
  assert.equal(result.applied, false);
  assert.equal(result.ignored_reason, "stale_sequence");
  assert.equal(nk.execCalls.some((c) =>
    c.query.includes("such_platform_native_purchase")), false);
});

test("validate_iap treats a refund without its credit as terminal", () => {
  const nk = new FakeNakama({
    validatePurchase: {validatedPurchases: [validatedApplePurchase({
      productId: "com.suchsoftware.suchmoonlaunch.moonrocks_10k",
      transactionId: "2000000123456790",
      refundTime: 1767200002000
    })]},
    httpCode: 503,
    httpResponse: {error: "original_credit_unavailable"}
  });
  const {rpcs, logger} = initialize(nk);
  assert.throws(
    () => rpcs.get("app_platform_validate_iap")(
      iapContext(), logger, nk,
      iapRequest({product_id: "com.suchsoftware.suchmoonlaunch.moonrocks_10k"})),
    (error) => error.code === 9 &&
      /refunded before its credit was recorded/
        .test(String(error && error.message))
  );
});
