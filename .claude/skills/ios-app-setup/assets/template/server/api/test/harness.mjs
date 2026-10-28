// A D1 stand-in on Node's built-in SQLite, a fake Apple and a clock, so the Worker runs unchanged
// in tests. The D1 stand-in counts queries the way D1 does (a batch is one), and every request
// must stay within the free plan's 50.
import { DatabaseSync } from 'node:sqlite';
import { handle } from '../src/worker.js';
import { resetSchemaCache } from '../src/schema.js';
import { b64url, randomToken, sha256Hex } from '../src/crypto.js';

export const QUERY_LIMIT = 50;
export const BUNDLE_ID = '__BUNDLE_ID__';

function d1() {
  const sqlite = new DatabaseSync(':memory:');
  const counter = { queries: 0 };
  const exec = (sql, args, mode) => {
    // D1 refuses undefined; so does this, so a missing value fails here as it would there.
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

/** Apple, faked: a key pair, and identity tokens for whoever we like. */
async function fakeApple() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'test', alg: 'RS256', use: 'sig' };
  const enc = new TextEncoder();
  return {
    keys: async () => [jwk],
    /** Like Apple, signs in the SHA-256 of the nonce the app asked for. */
    async token(sub, { aud = BUNDLE_ID, exp = Math.floor(Date.now() / 1000) + 600, nonce } = {}) {
      const h = b64url(enc.encode(JSON.stringify({ alg: 'RS256', kid: 'test' })));
      const claims = { iss: 'https://appleid.apple.com', aud, sub, exp, ...(nonce ? { nonce: await sha256Hex(nonce) } : {}) };
      const p = b64url(enc.encode(JSON.stringify(claims)));
      const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, enc.encode(`${h}.${p}`));
      return `${h}.${p}.${b64url(sig)}`;
    },
  };
}

export async function server({ signups = 'open' } = {}) {
  resetSchemaCache();
  const apple = await fakeApple();
  let now = new Date();
  const env = { DB: d1(), APPLE_KEYS: apple.keys, APPLE_BUNDLE_ID: BUNDLE_ID, SIGNUPS: signups, CLOCK: () => now };
  const origin = 'https://__APP_SLUG__-api.test';

  async function call(method, path, { token, json, raw } = {}) {
    const headers = {};
    if (token) headers.authorization = `Bearer ${token}`;
    let body;
    if (json !== undefined) { headers['content-type'] = 'application/json'; body = JSON.stringify(json); }
    env.DB.counter.queries = 0;
    const response = await handle(new Request(`${origin}/${path}`, { method, headers, body }), env);
    const queries = env.DB.counter.queries;
    if (queries > QUERY_LIMIT) throw new Error(`${method} ${path} made ${queries} D1 queries; the free plan allows ${QUERY_LIMIT}`);
    if (raw) return response;
    const text = await response.text();
    return { status: response.status, headers: response.headers, body: text ? JSON.parse(text) : null };
  }

  /** Sign in with Apple as the app does it: a fresh nonce, Apple's token, and for someone new the
   * ticket spent on a username. */
  async function appleSignIn(sub, { nonce = randomToken(24), aud } = {}) {
    return call('POST', 'v1/auth/apple', {
      json: { identity_token: await apple.token(sub, { nonce, aud }), nonce, timezone: 'America/New_York' },
    });
  }

  async function signUp(sub, username, name = username) {
    const first = await appleSignIn(sub);
    if (first.status !== 200 || !first.body.signup_ticket) throw new Error(`sign in ${sub}: ${JSON.stringify(first.body)}`);
    const made = await call('POST', 'v1/auth/apple/signup', {
      json: { signup_ticket: first.body.signup_ticket, username, name, timezone: 'America/New_York' },
    });
    if (made.status !== 200) throw new Error(`sign up ${username}: ${JSON.stringify(made.body)}`);
    return { token: made.body.access_token, refresh: made.body.refresh_token, user: made.body.user };
  }

  return { env, apple, call, appleSignIn, signUp, setNow: (date) => { now = date; }, now: () => now };
}
