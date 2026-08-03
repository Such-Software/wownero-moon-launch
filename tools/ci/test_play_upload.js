'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  assertMonotonic,
  classifyGoogleError,
  createAssertion,
  googleApiError,
  observedVersionCodes,
  positiveInteger,
  runPreflight,
  runUpload,
} = require('./play_upload.js');

test('provider errors are classified without exposing response details', () => {
  const signingText = JSON.stringify({
    error: {
      status: 'PERMISSION_DENIED',
      message: 'Bundle was signed with the wrong key; expected SHA1: AA:BB, caller release@example.invalid',
      errors: [{ reason: 'forbidden' }],
    },
  });
  const error = googleApiError(403, signingText, 'upload-bundle');
  assert.match(error.message, /category=signing/);
  assert.match(error.message, /status=PERMISSION_DENIED/);
  assert.match(error.message, /reason=forbidden/);
  assert.doesNotMatch(error.message, /SHA1|AA:BB|example\.invalid|expected/);
  assert.equal(classifyGoogleError({}, 'The caller does not have permission'), 'authorization');
  assert.equal(
    googleApiError(500, 'opaque provider text with release@example.invalid', 'upload-bundle').message,
    'Google API upload-bundle failed: HTTP 500; category=unknown',
  );
});

test('service-account assertion has a valid RSA signature', () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
  const assertion = createAssertion({
    client_email: 'release@example.invalid',
    private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
  }, 1000);
  const [header, payload, signature] = assertion.split('.');
  assert.equal(JSON.parse(Buffer.from(header, 'base64url')).alg, 'RS256');
  assert.equal(JSON.parse(Buffer.from(payload, 'base64url')).exp, 4600);
  assert(crypto.verify(
    'RSA-SHA256',
    Buffer.from(`${header}.${payload}`),
    publicKey,
    Buffer.from(signature, 'base64url'),
  ));
});

test('version codes are joined and sorted across all observed surfaces', () => {
  assert.deepEqual(observedVersionCodes(
    { bundles: [{ versionCode: 30 }] },
    { apks: [{ versionCode: 27 }] },
    { tracks: [{ releases: [{ versionCodes: ['28', '30'] }] }] },
  ), [27, 28, 30]);
});

test('monotonic preflight rejects reused and lower codes', () => {
  assert.equal(assertMonotonic(31, [27, 30]), 30);
  assert.throws(() => assertMonotonic(30, [27, 30]), /already exists/);
  assert.throws(() => assertMonotonic(29, [27, 30]), /existing maximum/);
  assert.throws(() => positiveInteger('0', 'code'), /positive integer/);
});

test('preflight deletes its temporary edit and writes a receipt', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'moon-play-preflight-'));
  const receiptPath = path.join(root, 'receipt.json');
  const calls = [];
  const client = {
    request: async (method, suffix) => {
      calls.push([method, suffix]);
      if (method === 'POST') return { id: 'edit-1' };
      if (suffix.endsWith('/bundles')) return { bundles: [{ versionCode: 27 }] };
      if (suffix.endsWith('/apks')) return { apks: [] };
      if (suffix.endsWith('/tracks')) return { tracks: [] };
      return {};
    },
  };
  const receipt = await runPreflight({
    client,
    packageName: 'com.example.app',
    expectedVersionCode: 28,
    receiptPath,
  });
  assert.equal(receipt.maximum_existing_version_code, 27);
  assert.deepEqual(calls.at(-1), ['DELETE', '/edits/edit-1']);
  assert.equal(JSON.parse(fs.readFileSync(receiptPath)).result, 'passed');
});

test('upload verifies returned code, commits, and records candidate hash', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'moon-play-upload-'));
  const aabPath = path.join(root, 'candidate.aab');
  const receiptPath = path.join(root, 'receipt.json');
  fs.writeFileSync(aabPath, 'candidate');
  const calls = [];
  const client = {
    request: async (method, suffix, body) => {
      calls.push([method, suffix, body]);
      if (method === 'POST' && suffix === '/edits') return { id: 'edit-2' };
      if (suffix.endsWith(':commit')) return { id: 'commit-2' };
      return {};
    },
    upload: async () => ({ versionCode: 28 }),
  };
  const receipt = await runUpload({
    client,
    packageName: 'com.example.app',
    expectedVersionCode: 28,
    track: 'internal',
    aabPath,
    receiptPath,
    sourceSha: 'a'.repeat(40),
  });
  assert.equal(receipt.result, 'committed');
  assert.equal(receipt.version_code, 28);
  assert(calls.some(([method, suffix]) => method === 'PUT' && suffix.endsWith('/internal')));
  assert(calls.some(([method, suffix]) => method === 'POST' && suffix.endsWith(':commit')));
  assert.equal(JSON.parse(fs.readFileSync(receiptPath)).aab_sha256.length, 64);
});
