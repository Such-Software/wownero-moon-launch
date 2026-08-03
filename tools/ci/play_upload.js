#!/usr/bin/env node
/* Candidate preflight and Play delivery using Node built-ins only. */
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const path = require('path');

function base64Url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function requiredEnvironment(name, environment = process.env) {
  const value = environment[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function positiveInteger(value, name) {
  if (!/^[1-9][0-9]*$/.test(String(value))) {
    throw new Error(`${name} must be a positive integer`);
  }
  return Number(value);
}

function createAssertion(serviceAccount, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (!serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error('service account lacks required signing fields');
  }
  const signingInput =
    `${base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.` +
    base64Url(JSON.stringify({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token',
      iat: nowSeconds,
      exp: nowSeconds + 3600,
    }));
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(signingInput)
    .sign(serviceAccount.private_key);
  return `${signingInput}.${base64Url(signature)}`;
}

function safeProviderToken(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_.-]{1,80}$/.test(value)
    ? value
    : '';
}

function classifyGoogleError(payload, text) {
  const message = payload && payload.error && typeof payload.error.message === 'string'
    ? payload.error.message
    : '';
  const lowered = `${message} ${text}`.toLowerCase();
  if (/wrong (?:signing )?(?:key|certificate)|signed with the wrong|certificate.*(?:expected|mismatch)/.test(lowered)) {
    return 'signing';
  }
  if (/does not have permission|permission denied|not authorized|forbidden/.test(lowered)) {
    return 'authorization';
  }
  if (/version\s*code|versioncode|already exists/.test(lowered)) {
    return 'version';
  }
  if (/permission declaration|policy|compliance|sensitive permission/.test(lowered)) {
    return 'policy';
  }
  if (/quota|rate limit|too many requests/.test(lowered)) {
    return 'quota';
  }
  return 'unknown';
}

function googleApiError(statusCode, text, operation) {
  let payload = {};
  try {
    payload = JSON.parse(text);
  } catch (_) {
    // Classification still works against the in-memory response text. Raw provider
    // text is never returned, printed, or persisted.
  }
  const error = payload && payload.error && typeof payload.error === 'object'
    ? payload.error
    : {};
  const providerStatus = safeProviderToken(error.status);
  const reasons = [];
  const errorItems = Array.isArray(error.errors) ? error.errors : [];
  const detailItems = Array.isArray(error.details) ? error.details : [];
  for (const item of [...errorItems, ...detailItems]) {
    const reason = safeProviderToken(item && item.reason);
    if (reason && !reasons.includes(reason)) reasons.push(reason);
  }
  const safeOperation = safeProviderToken(operation) || 'request';
  const parts = [
    `Google API ${safeOperation} failed: HTTP ${statusCode}`,
    `category=${classifyGoogleError(payload, text)}`,
  ];
  if (providerStatus) parts.push(`status=${providerStatus}`);
  if (reasons.length) parts.push(`reason=${reasons.slice(0, 3).join(',')}`);
  return new Error(parts.join('; '));
}

function request(options, body) {
  return new Promise((resolve, reject) => {
    const { operation = 'request', ...requestOptions } = options;
    const outgoing = https.request(requestOptions, (incoming) => {
      const chunks = [];
      incoming.on('data', (chunk) => chunks.push(chunk));
      incoming.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        if (incoming.statusCode >= 200 && incoming.statusCode < 300) {
          if (!text) return resolve({});
          try {
            return resolve(JSON.parse(text));
          } catch (_) {
            return reject(new Error(
              `Google API ${safeProviderToken(operation) || 'request'} returned invalid JSON`,
            ));
          }
        }
        return reject(googleApiError(incoming.statusCode, text, operation));
      });
    });
    outgoing.on('error', reject);
    outgoing.setTimeout(180000, () => outgoing.destroy(new Error('request timeout')));
    if (body && typeof body.pipe === 'function') body.pipe(outgoing);
    else {
      if (body) outgoing.write(body);
      outgoing.end();
    }
  });
}

async function accessToken(serviceAccount, requester = request) {
  const assertion = createAssertion(serviceAccount);
  const form =
    'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=' +
    encodeURIComponent(assertion);
  const response = await requester({
    host: 'oauth2.googleapis.com',
    path: '/token',
    method: 'POST',
    operation: 'oauth-token',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Content-Length': Buffer.byteLength(form),
    },
  }, form);
  if (!response.access_token) throw new Error('OAuth response lacks access token');
  return response.access_token;
}

function apiClient(packageName, token, requester = request) {
  const application = `/androidpublisher/v3/applications/${encodeURIComponent(packageName)}`;
  const headers = (extra = {}) => ({ Authorization: `Bearer ${token}`, ...extra });
  return {
    request: (method, suffix, body, extraHeaders = {}, operation = 'publisher-request') => requester({
      host: 'androidpublisher.googleapis.com',
      path: `${application}${suffix}`,
      method,
      operation,
      headers: headers(extraHeaders),
    }, body),
    upload: (editId, aabPath) => requester({
      host: 'androidpublisher.googleapis.com',
      path:
        `/upload/androidpublisher/v3/applications/${encodeURIComponent(packageName)}` +
        `/edits/${encodeURIComponent(editId)}/bundles?uploadType=media`,
      method: 'POST',
      operation: 'upload-bundle',
      headers: headers({
        'Content-Type': 'application/octet-stream',
        'Content-Length': fs.statSync(aabPath).size,
      }),
    }, fs.createReadStream(aabPath)),
  };
}

function observedVersionCodes(bundlesResponse, apksResponse, tracksResponse) {
  const codes = new Set();
  for (const bundle of bundlesResponse.bundles || []) {
    if (bundle.versionCode !== undefined) {
      codes.add(positiveInteger(bundle.versionCode, 'observed bundle versionCode'));
    }
  }
  for (const apk of apksResponse.apks || []) {
    if (apk.versionCode !== undefined) {
      codes.add(positiveInteger(apk.versionCode, 'observed APK versionCode'));
    }
  }
  for (const track of tracksResponse.tracks || []) {
    for (const release of track.releases || []) {
      for (const code of release.versionCodes || []) {
        codes.add(positiveInteger(code, 'observed track versionCode'));
      }
    }
  }
  return [...codes].sort((left, right) => left - right);
}

function assertMonotonic(candidate, observed) {
  const maximum = observed.length ? Math.max(...observed) : 0;
  if (observed.includes(candidate)) {
    throw new Error(`versionCode ${candidate} already exists in Google Play`);
  }
  if (candidate <= maximum) {
    throw new Error(`versionCode ${candidate} does not exceed the existing maximum`);
  }
  return maximum;
}

function sha256File(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function writeJson(file, value) {
  if (!file) return;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, file);
}

async function openEdit(client) {
  const edit = await client.request('POST', '/edits', '{}', {
    'Content-Type': 'application/json',
  }, 'open-edit');
  if (!edit.id) throw new Error('Google Play did not return an edit ID');
  return edit.id;
}

async function deleteEdit(client, editId) {
  await client.request('DELETE', `/edits/${encodeURIComponent(editId)}`, undefined, {}, 'delete-edit');
}

async function fetchObservedCodes(client, editId) {
  const prefix = `/edits/${encodeURIComponent(editId)}`;
  const [bundles, apks, tracks] = await Promise.all([
    client.request('GET', `${prefix}/bundles`, undefined, {}, 'list-bundles'),
    client.request('GET', `${prefix}/apks`, undefined, {}, 'list-apks'),
    client.request('GET', `${prefix}/tracks`, undefined, {}, 'list-tracks'),
  ]);
  return observedVersionCodes(bundles, apks, tracks);
}

async function runPreflight(context) {
  const editId = await openEdit(context.client);
  try {
    const observed = await fetchObservedCodes(context.client, editId);
    const maximum = assertMonotonic(context.expectedVersionCode, observed);
    const receipt = {
      schema_version: 1,
      command: 'assert-monotonic',
      result: 'passed',
      package_name: context.packageName,
      candidate_version_code: context.expectedVersionCode,
      maximum_existing_version_code: maximum,
      observed_version_codes: observed,
      checked_at: new Date().toISOString(),
    };
    writeJson(context.receiptPath, receipt);
    return receipt;
  } finally {
    await deleteEdit(context.client, editId);
  }
}

async function runUpload(context) {
  const track = context.track || 'internal';
  if (!/^[A-Za-z0-9._-]+$/.test(track)) throw new Error('invalid Play track');
  if (!context.aabPath || !fs.statSync(context.aabPath).isFile()) {
    throw new Error('AAB does not exist');
  }
  const editId = await openEdit(context.client);
  let committed = false;
  try {
    const bundle = await context.client.upload(editId, context.aabPath);
    const returnedCode = positiveInteger(bundle.versionCode, 'uploaded versionCode');
    if (returnedCode !== context.expectedVersionCode) {
      throw new Error('uploaded versionCode differs from the reviewed contract');
    }
    const prefix = `/edits/${encodeURIComponent(editId)}`;
    await context.client.request(
      'PUT',
      `${prefix}/tracks/${encodeURIComponent(track)}`,
      JSON.stringify({
        track,
        releases: [{ versionCodes: [String(returnedCode)], status: 'completed' }],
      }),
      { 'Content-Type': 'application/json' },
      'update-track',
    );
    const commit = await context.client.request(
      'POST', `${prefix}:commit`, undefined, {}, 'commit-edit',
    );
    committed = true;
    const receipt = {
      schema_version: 1,
      command: 'upload',
      result: 'committed',
      package_name: context.packageName,
      track,
      version_code: returnedCode,
      edit_id: editId,
      aab: path.basename(context.aabPath),
      aab_bytes: fs.statSync(context.aabPath).size,
      aab_sha256: sha256File(context.aabPath),
      source_sha: context.sourceSha || '',
      commit_id: commit.id || '',
      committed_at: new Date().toISOString(),
    };
    writeJson(context.receiptPath, receipt);
    return receipt;
  } finally {
    if (!committed) {
      try {
        await deleteEdit(context.client, editId);
      } catch (_) {
        process.stderr.write('Warning: failed to delete an uncommitted Play edit\n');
      }
    }
  }
}

async function main(environment = process.env) {
  const command = process.argv[2];
  if (!['assert-monotonic', 'upload'].includes(command)) {
    throw new Error('command must be assert-monotonic or upload');
  }
  const serviceAccountPath = requiredEnvironment('SA_JSON', environment);
  const packageName = requiredEnvironment('PKG', environment);
  const expectedVersionCode = positiveInteger(
    requiredEnvironment('EXPECTED_VERSION_CODE', environment),
    'EXPECTED_VERSION_CODE',
  );
  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
  const token = await accessToken(serviceAccount);
  const context = {
    client: apiClient(packageName, token),
    packageName,
    expectedVersionCode,
    receiptPath: environment.PLAY_RECEIPT_PATH,
    sourceSha: environment.SOURCE_SHA,
    track: environment.TRACK,
    aabPath: environment.AAB,
  };
  const receipt = command === 'assert-monotonic'
    ? await runPreflight(context)
    : await runUpload(context);
  process.stdout.write(`Play ${command} passed for reviewed versionCode ${expectedVersionCode}\n`);
  return receipt;
}

module.exports = {
  assertMonotonic,
  base64Url,
  createAssertion,
  classifyGoogleError,
  googleApiError,
  observedVersionCodes,
  positiveInteger,
  runPreflight,
  runUpload,
};

if (require.main === module) {
  main().catch((error) => {
    writeJson(process.env.PLAY_RECEIPT_PATH, {
      schema_version: 1,
      command: process.argv[2] || '',
      result: 'failed',
      package_name: process.env.PKG || '',
      candidate_version_code: process.env.EXPECTED_VERSION_CODE || '',
      error: error.message,
      failed_at: new Date().toISOString(),
    });
    process.stderr.write(`PLAY RELEASE FAILED: ${error.message}\n`);
    process.exitCode = 1;
  });
}
