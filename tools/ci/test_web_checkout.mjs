#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const APP_CONFIG_SOURCE = fs.readFileSync(path.join(ROOT, "web/app-config.js"), "utf8");
const CHECKOUT_SOURCE = fs.readFileSync(path.join(ROOT, "web/checkout.js"), "utf8");

const LIVE_CONFIG = {
  oidcIssuer: "https://identity.example.test",
  oidcClientId: "public-client-test-fixture",
  ledgerBase: "https://ledger.example.test",
  checkoutUrl: "https://shop.moonlaunch.space",
  checkoutEnabled: true,
};

function memoryStorage(seed = {}) {
  const values = new Map(Object.entries(seed));
  return {
    values,
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
    setItem(key, value) {
      values.set(key, String(value));
    },
    removeItem(key) {
      values.delete(key);
    },
  };
}

function testCrypto() {
  return {
    getRandomValues(bytes) {
      for (let index = 0; index < bytes.length; index += 1) {
        bytes[index] = (index * 17 + 23) % 256;
      }
      return bytes;
    },
    subtle: {
      async digest() {
        return Uint8Array.from({ length: 32 }, (_, index) => index + 1).buffer;
      },
    },
  };
}

async function flushTasks() {
  for (let index = 0; index < 6; index += 1) {
    await new Promise((resolve) => setImmediate(resolve));
  }
}

async function boot({
  config,
  search = "",
  storage,
  entitled = false,
  raceUnlimited = false,
} = {}) {
  const sessionStorage = storage || memoryStorage();
  const assignments = [];
  const requests = [];
  const events = [];
  const replacements = [];
  const window = {
    location: {
      origin: "https://moonlaunch.space",
      pathname: "/play",
      search,
      assign(value) {
        assignments.push(String(value));
      },
    },
    crypto: testCrypto(),
    TextEncoder,
    dispatchEvent(event) {
      events.push(event);
    },
  };
  if (config) window.SUCH_APP_CONFIG = config;

  const context = {
    window,
    URL,
    URLSearchParams,
    Uint8Array,
    TextEncoder,
    btoa(value) {
      return Buffer.from(value, "binary").toString("base64");
    },
    sessionStorage,
    history: {
      replaceState(...args) {
        replacements.push(args);
      },
    },
    document: { title: "Such Moon Launch" },
    CustomEvent: class CustomEvent {
      constructor(type, options) {
        this.type = type;
        this.detail = options && options.detail;
      }
    },
    async fetch(url, options = {}) {
      requests.push({ url: String(url), options });
      if (String(url).endsWith("/token")) {
        return { ok: true, async json() { return { access_token: "user-token" }; } };
      }
      if (String(url).endsWith("/me/apps/moon_launch/commerce")) {
        return {
          ok: true,
          async json() {
            return {
              premium: entitled,
              race_unlimited: raceUnlimited,
              entitlements: raceUnlimited
                ? [{ entitlement_key: "race_unlimited", state: "active" }]
                : [],
            };
          },
        };
      }
      throw new Error(`unexpected request: ${url}`);
    },
  };

  if (!config) vm.runInNewContext(APP_CONFIG_SOURCE, context, { filename: "app-config.js" });
  vm.runInNewContext(CHECKOUT_SOURCE, context, { filename: "checkout.js" });
  await flushTasks();
  return { assignments, events, replacements, requests, sessionStorage, window };
}

async function testCheckedInConfigIsInert() {
  const result = await boot();
  assert.deepEqual(JSON.parse(JSON.stringify(result.window.SUCH_APP_CONFIG)), {
    oidcIssuer: null,
    oidcClientId: null,
    ledgerBase: null,
    checkoutUrl: null,
    checkoutEnabled: false,
  });
  assert.equal(result.window.SUCH_APP.checkoutEnabled, false);
  assert.equal(result.window.SUCH_APP.checkoutUrl, null);
  assert.equal(result.window.SUCH_APP.premium, false);
  assert.equal(result.window.SUCH_APP.raceUnlimited, false);
  assert.deepEqual(
    JSON.parse(JSON.stringify(result.window.SUCH_APP.catalogOfferIds)),
    [
      "race_unlimited_lifetime_v1",
      "moonrocks_10k_v1",
      "moonrocks_50k_v1",
    ],
  );
  assert.equal(result.window.SUCH_APP_startCheckout(), false);
  assert.equal(await result.window.SUCH_APP_refreshEntitlements(), false);
  assert.deepEqual(result.assignments, []);
  assert.deepEqual(result.requests, []);
  assert.equal(result.sessionStorage.values.size, 0);
}

async function testPkceLoginAndConsumableHandoff() {
  const login = await boot({ config: LIVE_CONFIG });
  assert.equal(
    login.window.SUCH_APP_startCheckout("moonrocks_10k_v1"),
    true,
  );
  await flushTasks();
  assert.equal(login.assignments.length, 1);

  const authorization = new URL(login.assignments[0]);
  assert.equal(authorization.origin, "https://identity.example.test");
  assert.equal(authorization.pathname, "/authorize");
  assert.equal(authorization.searchParams.get("client_id"), LIVE_CONFIG.oidcClientId);
  assert.equal(authorization.searchParams.get("redirect_uri"), "https://moonlaunch.space/play");
  assert.equal(authorization.searchParams.get("response_type"), "code");
  assert.equal(authorization.searchParams.get("code_challenge_method"), "S256");
  assert.ok(authorization.searchParams.get("code_challenge"));
  const state = authorization.searchParams.get("state");
  assert.equal(state, login.sessionStorage.getItem("such_moon_launch_oidc_state"));
  assert.equal(
    login.sessionStorage.getItem("such_moon_launch_pending_checkout"),
    "moonrocks_10k_v1",
  );

  const callback = await boot({
    config: LIVE_CONFIG,
    search: `?code=one-use-code&state=${encodeURIComponent(state)}`,
    storage: login.sessionStorage,
    entitled: false,
  });
  assert.equal(callback.requests.length, 2);
  assert.equal(callback.requests[0].url, "https://identity.example.test/token");
  assert.match(callback.requests[0].options.body, /code_verifier=/);
  assert.equal(
    callback.requests[1].url,
    "https://ledger.example.test/me/apps/moon_launch/commerce",
  );
  assert.equal(callback.requests[1].options.headers.Authorization, "Bearer user-token");
  assert.deepEqual(callback.assignments, [
    "https://shop.moonlaunch.space/offers/moonrocks_10k_v1",
  ]);
  assert.equal(callback.window.SUCH_APP.premium, false);
  assert.equal(callback.sessionStorage.getItem("such_moon_launch_pending_checkout"), null);
  assert.equal(callback.replacements.length, 1);
}

async function testLifetimeOwnerDoesNotReturnToCheckout() {
  const storage = memoryStorage({
    such_moon_launch_pkce_verifier: "verifier",
    such_moon_launch_oidc_state: "expected-state",
    such_moon_launch_pending_checkout: "race_unlimited_lifetime_v1",
  });
  const result = await boot({
    config: LIVE_CONFIG,
    search: "?code=one-use-code&state=expected-state",
    storage,
    entitled: true,
    raceUnlimited: true,
  });
  assert.equal(result.window.SUCH_APP.premium, true);
  assert.deepEqual(result.assignments, []);
  assert.equal(result.events.length, 1);
  assert.equal(result.events[0].type, "such-app-entitlements-changed");
  assert.deepEqual(JSON.parse(JSON.stringify(result.events[0].detail)), {
    premium: true,
    race_unlimited: true,
  });
}

async function testCatalogBrowseAndInvalidOfferHandling() {
  const browse = await boot({ config: LIVE_CONFIG });
  assert.equal(browse.window.SUCH_APP_startCheckout(), true);
  await flushTasks();
  assert.equal(
    browse.sessionStorage.getItem("such_moon_launch_pending_checkout"),
    "__catalog__",
  );

  const invalid = await boot({ config: LIVE_CONFIG });
  assert.equal(
    invalid.window.SUCH_APP_startCheckout("moonrocks_9999999_v1"),
    false,
  );
  assert.equal(
    invalid.sessionStorage.getItem("such_moon_launch_pending_checkout"),
    null,
  );
  assert.deepEqual(invalid.assignments, []);
}

async function testStateMismatchFailsClosed() {
  const storage = memoryStorage({
    such_moon_launch_pkce_verifier: "verifier",
    such_moon_launch_oidc_state: "expected-state",
    such_moon_launch_pending_checkout: "1",
  });
  const result = await boot({
    config: LIVE_CONFIG,
    search: "?code=one-use-code&state=attacker-state",
    storage,
  });
  assert.deepEqual(result.requests, []);
  assert.deepEqual(result.assignments, []);
  assert.equal(result.window.SUCH_APP.premium, false);
  assert.equal(result.sessionStorage.getItem("such_moon_launch_pending_checkout"), null);
  assert.equal(result.replacements.length, 1);
}

async function testMalformedProjectedUrlsFailClosed() {
  const variants = [
    { ...LIVE_CONFIG, checkoutUrl: "https://shop.moonlaunch.space/not-root" },
    { ...LIVE_CONFIG, checkoutUrl: "https://shop.moonlaunch.space?offer=forged" },
    { ...LIVE_CONFIG, checkoutUrl: "https://other.example.test" },
    { ...LIVE_CONFIG, oidcIssuer: "https://identity.example.test#fragment" },
    { ...LIVE_CONFIG, ledgerBase: "https://ledger.example.test?token=leak" },
  ];
  for (const config of variants) {
    const result = await boot({ config });
    assert.equal(result.window.SUCH_APP.checkoutEnabled, false);
    assert.equal(result.window.SUCH_APP_startCheckout("moonrocks_10k_v1"), false);
    assert.deepEqual(result.assignments, []);
    assert.deepEqual(result.requests, []);
  }
}

await testCheckedInConfigIsInert();
await testPkceLoginAndConsumableHandoff();
await testLifetimeOwnerDoesNotReturnToCheckout();
await testCatalogBrowseAndInvalidOfferHandling();
await testStateMismatchFailsClosed();
await testMalformedProjectedUrlsFailClosed();
console.log("PASS Moon Launch fail-closed web checkout");
