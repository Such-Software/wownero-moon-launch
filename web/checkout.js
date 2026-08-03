/*
 * Fail-closed web-game commerce wiring for Such Moon Launch.
 *
 * This is the Bauhaus Echo pattern adapted to Godot's web shell. Only a complete
 * Operations-supplied public config can start OIDC Authorization Code + S256
 * PKCE, hand off to the canonical Moon Launch storefront, and resolve the
 * provider-neutral `premium` capability through the user's own access token.
 * Source config is all-null/false, so the Hangar CTA follows its ordinary status
 * link and premium remains false. No provider credential or shared ledger token
 * is ever present in this client.
 */
(function () {
  "use strict";

  var CFG = window.SUCH_APP_CONFIG || {};
  var EXPECTED_SHOP_HOST = "shop.moonlaunch.space";
  var REDIRECT = window.location.origin + window.location.pathname;
  var SCOPE = "openid";

  function httpsUrl(value, expectedHost) {
    if (!value) return null;
    try {
      var parsed = new URL(String(value));
      if (
        parsed.protocol !== "https:" ||
        parsed.username ||
        parsed.password ||
        parsed.port ||
        (expectedHost && parsed.hostname.toLowerCase() !== expectedHost)
      ) {
        return null;
      }
      return parsed.toString().replace(/\/+$/, "");
    } catch (_error) {
      return null;
    }
  }

  var ISSUER = httpsUrl(CFG.oidcIssuer, null);
  var CLIENT = typeof CFG.oidcClientId === "string" && CFG.oidcClientId
    ? CFG.oidcClientId
    : null;
  var LEDGER = httpsUrl(CFG.ledgerBase, null);
  var SHOP_URL = httpsUrl(CFG.checkoutUrl, EXPECTED_SHOP_HOST);
  var CRYPTO_READY = !!(
    window.crypto &&
    window.crypto.subtle &&
    window.crypto.getRandomValues &&
    window.TextEncoder
  );
  var configured = !!(
    CFG.checkoutEnabled === true &&
    ISSUER &&
    CLIENT &&
    LEDGER &&
    SHOP_URL &&
    CRYPTO_READY
  );

  window.SUCH_APP = window.SUCH_APP || {};
  window.SUCH_APP.checkoutEnabled = configured;
  window.SUCH_APP.checkoutUrl = configured ? SHOP_URL : null;
  if (window.SUCH_APP.premium !== true) window.SUCH_APP.premium = false;

  var encode = encodeURIComponent;
  function form(values) {
    return Object.keys(values)
      .filter(function (key) { return values[key] != null; })
      .map(function (key) {
        return encode(key) + "=" + encode(values[key]);
      })
      .join("&");
  }

  function base64url(bytes) {
    var value = "";
    for (var index = 0; index < bytes.length; index += 1) {
      value += String.fromCharCode(bytes[index]);
    }
    return btoa(value)
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
  }

  function randomToken() {
    var bytes = new Uint8Array(32);
    window.crypto.getRandomValues(bytes);
    return base64url(bytes);
  }

  async function challengeFor(verifier) {
    var digest = await window.crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(verifier),
    );
    return base64url(new Uint8Array(digest));
  }

  var K_VERIFIER = "such_moon_launch_pkce_verifier";
  var K_STATE = "such_moon_launch_oidc_state";
  var K_TOKEN = "such_moon_launch_access_token";
  var K_PENDING = "such_moon_launch_pending_checkout";

  function clearLoginIntent() {
    sessionStorage.removeItem(K_VERIFIER);
    sessionStorage.removeItem(K_STATE);
    sessionStorage.removeItem(K_PENDING);
  }

  async function startLogin() {
    var verifier = randomToken();
    var state = randomToken();
    sessionStorage.setItem(K_VERIFIER, verifier);
    sessionStorage.setItem(K_STATE, state);
    sessionStorage.setItem(K_PENDING, "1");
    var challenge = await challengeFor(verifier);
    var authorizationUrl = ISSUER + "/authorize?" + form({
      client_id: CLIENT,
      redirect_uri: REDIRECT,
      response_type: "code",
      scope: SCOPE,
      code_challenge: challenge,
      code_challenge_method: "S256",
      state: state,
    });
    window.location.assign(authorizationUrl);
  }

  async function completeLoginIfCallback() {
    var query = new URLSearchParams(window.location.search);
    var code = query.get("code");
    var returnedState = query.get("state");
    var oauthError = query.get("error");
    if (!code && !oauthError) return false;

    var expectedState = sessionStorage.getItem(K_STATE);
    var verifier = sessionStorage.getItem(K_VERIFIER);
    history.replaceState({}, document.title, REDIRECT);
    sessionStorage.removeItem(K_VERIFIER);
    sessionStorage.removeItem(K_STATE);

    if (
      oauthError ||
      !configured ||
      !code ||
      !returnedState ||
      returnedState !== expectedState ||
      !verifier
    ) {
      sessionStorage.removeItem(K_PENDING);
      return false;
    }

    try {
      var response = await fetch(ISSUER + "/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form({
          grant_type: "authorization_code",
          code: code,
          redirect_uri: REDIRECT,
          client_id: CLIENT,
          code_verifier: verifier,
        }),
      });
      if (!response.ok) {
        sessionStorage.removeItem(K_PENDING);
        return false;
      }
      var tokenResponse = await response.json();
      if (!tokenResponse || !tokenResponse.access_token) {
        sessionStorage.removeItem(K_PENDING);
        return false;
      }
      sessionStorage.setItem(K_TOKEN, tokenResponse.access_token);
      return true;
    } catch (_error) {
      sessionStorage.removeItem(K_PENDING);
      return false;
    }
  }

  async function resolvePremium() {
    window.SUCH_APP.premium = false;
    var token = sessionStorage.getItem(K_TOKEN);
    if (!configured || !token) return false;
    try {
      var response = await fetch(LEDGER + "/me/entitlements", {
        headers: {
          Authorization: "Bearer " + token,
          Accept: "application/json",
        },
      });
      if (!response.ok) return false;
      var entitlements = await response.json();
      window.SUCH_APP.premium = !!(
        entitlements && entitlements.premium === true
      );
      window.dispatchEvent(new CustomEvent("such-app-entitlements-changed", {
        detail: { premium: window.SUCH_APP.premium },
      }));
      return window.SUCH_APP.premium;
    } catch (_error) {
      return false;
    }
  }

  window.SUCH_APP_startCheckout = function () {
    if (!configured) return false;
    startLogin().catch(clearLoginIntent);
    return true;
  };
  window.SUCH_APP_refreshEntitlements = resolvePremium;

  (async function () {
    await completeLoginIfCallback();
    await resolvePremium();
    if (
      configured &&
      sessionStorage.getItem(K_PENDING) === "1" &&
      sessionStorage.getItem(K_TOKEN)
    ) {
      sessionStorage.removeItem(K_PENDING);
      if (window.SUCH_APP.premium !== true) {
        window.location.assign(SHOP_URL);
      }
    }
  })();
})();
