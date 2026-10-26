// A D1 stand-in on Node's built-in SQLite, a fake R2 bucket, a fake Apple, and a clock, so the
// Worker runs unchanged in tests. The D1 stand-in also counts queries the way D1 does (a batch
// is one), and every request must stay within the free plan's 50.
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { handle } from '../src/worker.js';
import { resetSchemaCache } from '../src/schema.js';
import { b64url, randomToken, sha256Hex } from '../src/crypto.js';

export const QUERY_LIMIT = 50;

function d1() {
  const sqlite = new DatabaseSync(':memory:');
  const counter = { queries: 0 };
  const exec = (sql, args, mode) => {
    for (const a of args) if (a === undefined) throw new Error(`D1_TYPE_ERROR: undefined bound in ${sql}`);
    const stmt = sqlite.prepare(sql);
    const values = args.map((v) => (typeof v === 'boolean' ? (v ? 1 : 0) : v));
    if (mode === 'first') return stmt.get(...values) ?? null;
    if (mode === 'all') return { results: stmt.all(...values).map((r) => ({ ...r })) };
    const r = stmt.run(...values);
    return { success: true, meta: { changes: r.changes } };
  };
  const statement = (sql, args = []) => ({
    sql, args,
    bind: (...values) => statement(sql, values),
    first: async (column) => {
      counter.queries++;
      const row = exec(sql, args, 'first');
      return row && column ? row[column] : row ? { ...row } : null;
    },
    all: async () => { counter.queries++; return exec(sql, args, 'all'); },
    run: async () => { counter.queries++; return exec(sql, args, 'run'); },
  });
  return {
    sqlite,
    counter,
    prepare: (sql) => statement(sql),
    batch: async (statements) => {
      counter.queries++;
      sqlite.exec('BEGIN');
      try {
        const out = statements.map((s) => exec(s.sql, s.args, 'run'));
        sqlite.exec('COMMIT');
        return out;
      } catch (e) {
        sqlite.exec('ROLLBACK');
        throw e;
      }
    },
  };
}

const roundTrip = () => new Promise((resolve) => setTimeout(resolve, 1 + Math.random() * 4));

/** The same database as a Worker sees D1, across a network: every query waits a few milliseconds
 * on the way there and back, so requests sent together overlap the way they do on Cloudflare.
 * SQLite still runs one statement at a time, as D1 does. */
function overNetwork(db) {
  const statement = (s) => ({
    ...s,
    bind: (...values) => statement(s.bind(...values)),
    first: async (column) => { await roundTrip(); const row = await s.first(column); await roundTrip(); return row; },
    all: async () => { await roundTrip(); const rows = await s.all(); await roundTrip(); return rows; },
    run: async () => { await roundTrip(); const result = await s.run(); await roundTrip(); return result; },
  });
  return {
    ...db,
    prepare: (sql) => statement(db.prepare(sql)),
    batch: async (statements) => { await roundTrip(); const out = await db.batch(statements); await roundTrip(); return out; },
  };
}

/** R2, faked: the handful of bucket calls storage.js makes. */
export function r2() {
  const objects = new Map();
  return {
    objects,
    put: async (key, bytes) => { objects.set(key, new Uint8Array(bytes)); },
    get: async (key) => (objects.has(key) ? { arrayBuffer: async () => objects.get(key).slice().buffer } : null),
    delete: async (keys) => { for (const k of [keys].flat()) objects.delete(k); },
  };
}

/** Apple, faked: a key pair, and identity tokens for whoever we like. */
async function fakeApple() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'test', alg: 'RS256', use: 'sig' };
  const enc = new TextEncoder();
  return {
    keys: async () => [jwk],
    /** Like Apple, signs in the SHA-256 of the nonce the app asked for. */
    async token(sub, { aud = 'com.jonmooreai.sundae', exp = Math.floor(Date.now() / 1000) + 600, nonce } = {}) {
      const h = b64url(enc.encode(JSON.stringify({ alg: 'RS256', kid: 'test' })));
      const claims = { iss: 'https://appleid.apple.com', aud, sub, exp, ...(nonce ? { nonce: await sha256Hex(nonce) } : {}) };
      const p = b64url(enc.encode(JSON.stringify(claims)));
      const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, enc.encode(`${h}.${p}`));
      return `${h}.${p}.${b64url(sig)}`;
    },
  };
}

// October 25, 2026 is a Sunday; the 21st a Wednesday. Noon in New York.
export const SUNDAY = new Date('2026-10-25T16:00:00Z');
export const WEDNESDAY = new Date('2026-10-21T16:00:00Z');
export const NEXT_SUNDAY = new Date('2026-11-01T17:00:00Z');

export async function server({ photos } = {}) {
  resetSchemaCache();
  const apple = await fakeApple();
  let now = SUNDAY;
  const env = { DB: d1(), APPLE_KEYS: apple.keys, APPLE_BUNDLE_ID: 'com.jonmooreai.sundae', CLOCK: () => now };
  if (photos) env.PHOTOS = photos;
  let busiest = { queries: 0, path: '' };
  const origin = 'https://sundae-api.test';

  function request(method, path, { token, json, bytes } = {}) {
    const headers = {};
    if (token) headers.authorization = `Bearer ${token}`;
    let body;
    if (json !== undefined) { headers['content-type'] = 'application/json'; body = JSON.stringify(json); }
    if (bytes) { headers['content-type'] = 'image/jpeg'; body = bytes; }
    return new Request(path.startsWith('http') ? path : `${origin}/${path}`, { method, headers, body });
  }

  async function read(response) {
    const text = await response.text();
    return { status: response.status, body: text ? JSON.parse(text) : null };
  }

  async function call(method, path, options = {}) {
    const req = request(method, path, options);
    env.DB.counter.queries = 0;
    const response = await handle(req, env);
    const queries = env.DB.counter.queries;
    if (queries > busiest.queries) busiest = { queries, path: `${method} ${new URL(req.url).pathname}` };
    if (queries > QUERY_LIMIT) throw new Error(`${method} ${path} made ${queries} D1 queries; the free plan allows ${QUERY_LIMIT}`);
    return options.raw ? response : read(response);
  }

  /** Requests sent all at once, as a script could, each [method, path, options]. They share one
   * query counter, so the per-request limit is left to call(). */
  async function together(requests) {
    const network = { ...env, DB: overNetwork(env.DB) };
    return Promise.all(requests.map(([method, path, options]) => handle(request(method, path, options), network).then(read)));
  }

  /** A PUT whose body is still on its way, as over a slow connection, until finish() sends it. */
  async function slowPut(path) {
    let stream;
    const body = new ReadableStream({ start: (controller) => { stream = controller; } });
    const response = handle(new Request(path, { method: 'PUT', headers: { 'content-type': 'image/jpeg' }, body, duplex: 'half' }), env).then(read);
    // Long enough for the server to have read the ticket and to be waiting on the body.
    await new Promise((resolve) => setTimeout(resolve, 20));
    return { response, finish: (bytes) => { stream.enqueue(bytes); stream.close(); } };
  }

  async function signUp(sub, username, name = username) {
    const nonce = randomToken(24);
    const r = await call('POST', 'v1/auth/apple', {
      json: { identity_token: await apple.token(sub, { nonce }), nonce, username, name, timezone: 'America/New_York' },
    });
    if (r.status !== 200) throw new Error(`sign up ${username}: ${JSON.stringify(r.body)}`);
    return { token: r.body.access_token, refresh: r.body.refresh_token, user: r.body.user };
  }

  return { env, apple, call, together, slowPut, signUp, setNow: (date) => { now = date; }, now: () => now, busiest: () => busiest };
}

const segment = (marker, text) => {
  const data = new TextEncoder().encode(text);
  return [0xff, marker, (data.length + 2) >> 8, (data.length + 2) & 0xff, ...data];
};

/** A start-of-frame header: 8-bit samples, the size, three components. */
export const frame = (width, height, marker = 0xc0) => [
  0xff, marker, 0x00, 0x11, 8, height >> 8, height & 0xff, width >> 8, width & 0xff, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1,
];

/** A JPEG laid out like a real one: JFIF, EXIF carrying a GPS position, a comment, a color
 * profile, the frame's size, then the scan. The scan is filler with no FF in it, which is all the
 * server's checks look at. `marker` picks the kind of frame: C0 is baseline, C2 progressive. */
export function jpeg(size = 2000, { width = 2048, height = 1536, frames = 1, marker = 0xc0 } = {}) {
  const head = [
    0xff, 0xd8,
    ...segment(0xe0, 'JFIF\0'),
    ...segment(0xe1, 'Exif\0\0GPS 40.7128 N 74.0060 W'),
    ...segment(0xfe, 'shot at home'),
    ...segment(0xe2, 'ICC_PROFILE\0sRGB'),
    ...Array.from({ length: frames }, () => frame(width, height, marker)).flat(),
    0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 0x3f, 0,
  ];
  const bytes = new Uint8Array(Math.max(size, head.length + 2));
  bytes.set(head);
  for (let i = head.length; i < bytes.length - 2; i++) bytes[i] = i % 251;
  bytes.set([0xff, 0xd9], bytes.length - 2);
  return bytes;
}

// MARK: - Helpers shared by the tests

export async function friends(s) {
  const jon = await s.signUp('apple-jon', 'jon', 'Jon');
  const maya = await s.signUp('apple-maya', 'maya', 'Maya');
  // Jon follows Maya and Maya follows Jon, both private, both accepted.
  await s.call('POST', `v1/users/${maya.user.id}/follow`, { token: jon.token });
  await s.call('POST', `v1/me/follow-requests/${jon.user.id}`, { token: maya.token, json: { accept: true } });
  await s.call('POST', `v1/users/${jon.user.id}/follow`, { token: maya.token });
  await s.call('POST', `v1/me/follow-requests/${maya.user.id}`, { token: jon.token, json: { accept: true } });
  return { jon, maya };
}

/** After a clock jump the access token has expired, so sign back in the way the app does. */
export async function refresh(s, who) {
  const r = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: who.refresh } });
  assert.equal(r.status, 200);
  who.token = r.body.access_token;
  who.refresh = r.body.refresh_token;
}

export async function uploadPhoto(s, who, size = 3000) {
  const ticket = await s.call('POST', 'v1/uploads', { token: who.token, json: { content_type: 'image/jpeg', byte_size: size, width: 2048, height: 1536 } });
  assert.equal(ticket.status, 200, JSON.stringify(ticket.body));
  const put = await s.call('PUT', ticket.body.url, { bytes: jpeg(size) });
  assert.equal(put.status, 204);
  return ticket.body.upload_id;
}
