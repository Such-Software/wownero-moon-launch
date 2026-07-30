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
      SUCH_PLATFORM_SCHEMA_VERSION: "2",
      SUCH_PLATFORM_SOURCE_COMMIT: "a".repeat(40),
      SUCH_PLATFORM_RUNTIME_SHA256: "b".repeat(64),
      SUCH_PLATFORM_MIGRATION_SHA256: "c".repeat(64),
      SUCH_PLATFORM_CONTRACT_VERSION: "1",
      SUCH_PLATFORM_CONTRACT_COMMIT:
        "851456cafa1f0ed68aff2760da8b62e7db3ac0aa",
      SUCH_IDP_CONSUME_URL:
        "https://idp.internal.example/internal/consume-nakama-ticket",
      SUCH_IDP_CONSUMER_TOKEN: "i".repeat(32),
      SUCH_ENTITLEMENT_PROVIDER_URL:
        "https://entitlements.internal.example/v1/provider-events/moon_launch",
      SUCH_ENTITLEMENT_PROVIDER_TOKEN: "p".repeat(32),
      SUCH_ENTITLEMENT_PROJECTION_HMAC_KEY: "e".repeat(32),
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

  sqlQuery(query, args = []) {
    this.queryCalls.push({query, args});
    if (query.includes("such_platform_schema_migration")) {
      return this.options.migrationMissing
        ? []
        : [{migration_id: "002_friendly_room"}];
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

test("registers the complete common App Platform surface", () => {
  const {rpcs, hooks} = initialize();
  assert.deepEqual(
    [...rpcs.keys()].sort(),
    [
      "app_entitlement_projection",
      "app_platform_build_info",
      "app_platform_claim_guest",
      "app_platform_entitlements",
      "app_platform_health",
      "app_platform_prepare_guest_claim",
      "app_platform_readiness",
      "moon_launch_room_close",
      "moon_launch_room_register",
      "moon_launch_room_resolve"
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
  assert.equal(build.schema_version, 2);
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
    "such_moon_launch_friendly_room"
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
  assert.match(migrationSource, /ON CONFLICT \(schema_version\) DO NOTHING/);
  assert.doesNotMatch(
    migrationSource.toLowerCase(),
    /\b(?:drop\s+table|truncate|delete\s+from)\b/
  );
  assert.equal(path.basename(migrationPath), "migrations.sql");
});
