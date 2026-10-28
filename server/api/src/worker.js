// Tally's server: the contract in docs/API.md, on one Cloudflare Worker with one D1
// database, on the free plan. No dependencies, no build step.

import { newId, randomToken, sha256Hex, signToken, verifyAppleIdentityToken, verifyToken } from './crypto.js';
import { ensureSchema } from './schema.js';
import { PRIVACY_HTML } from './privacy.js';

const APP_NAME = 'Tally';
const ACCESS_SECONDS = 15 * 60;
const REFRESH_SECONDS = 30 * 24 * 3600;
// How long someone new has, after Sign in with Apple, to choose a username.
const SIGNUP_SECONDS = 60 * 60;
// A used refresh token still works this long, so a reply lost on a bad connection does not sign
// anyone out. After that, a second use means the token leaked: the whole session is revoked.
const REFRESH_GRACE_SECONDS = 60;
const MAX_NOTE = 1000;
const MAX_NOTES = 500;

// MARK: - Responses

// On every response. Nothing here is meant for a browser: no scripts may run, no page may frame
// it, no address leaks in a Referer, and only HTTPS is spoken. No CORS headers, so no website can
// read the API from a browser.
const SECURITY_HEADERS = {
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'content-security-policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  'strict-transport-security': 'max-age=31536000',
};
// The privacy page's own styles are inline; it has no scripts and shows nothing anyone typed.
const PAGE_CSP = "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";

class HttpError extends Error {
  constructor(status, code, message) {
    super(message ?? code);
    this.status = status;
    this.code = code;
  }
}

const fail = (status, code, message) => { throw new HttpError(status, code, message); };

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status, headers: { ...SECURITY_HEADERS, 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers },
  });
}

const empty = () => new Response(null, { status: 204, headers: { ...SECURITY_HEADERS, 'cache-control': 'no-store' } });

async function body(request) {
  try {
    return await request.json();
  } catch {
    fail(400, 'bad_request', 'Expected a JSON body.');
  }
}

// MARK: - Entry

export default {
  async fetch(request, env) {
    return handle(request, env);
  },
  // Daily, from the cron in wrangler.jsonc.
  async scheduled(_event, env, context) {
    context.waitUntil(cleanUp(env));
  },
};

export async function handle(request, env) {
  try {
    const url = new URL(request.url);
    if (request.method === 'GET' && (url.pathname === '/privacy' || url.pathname === '/privacy/')) {
      return new Response(PRIVACY_HTML, {
        headers: { ...SECURITY_HEADERS, 'content-security-policy': PAGE_CSP, 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=3600' },
      });
    }
    if (request.method === 'GET' && url.pathname === '/') {
      return new Response(`${APP_NAME}\n`, { headers: { ...SECURITY_HEADERS, 'content-type': 'text/plain; charset=utf-8' } });
    }
    if (!url.pathname.startsWith('/v1/')) fail(404, 'not_found');
    await ensureSchema(env.DB);
    // env.CLOCK exists only in tests.
    const now = typeof env.CLOCK === 'function' ? env.CLOCK() : new Date();
    const ctx = { env, db: env.DB, request, now, me: null, family: null, secret: await tokenSecret(env) };
    return await route(ctx, request.method, url.pathname.slice(4).split('/').filter(Boolean));
  } catch (error) {
    if (error instanceof HttpError) return json({ error: { code: error.code, message: error.message } }, error.status);
    console.error('unhandled', error?.stack || error);
    return json({ error: { code: 'server_error', message: 'Something went wrong.' } }, 500);
  }
}

const secrets = new WeakMap();

/** TOKEN_SECRET when set as a Worker secret; otherwise one generated on first use and kept in the
 * database, so a new app needs no secret set up by hand. */
async function tokenSecret(env) {
  if (env.TOKEN_SECRET) return env.TOKEN_SECRET;
  if (secrets.has(env.DB)) return secrets.get(env.DB);
  const read = () => env.DB.prepare(`SELECT value FROM config WHERE key = 'token_secret'`).first('value');
  let value = await read();
  if (!value) {
    await env.DB.prepare(`INSERT OR IGNORE INTO config (key, value) VALUES ('token_secret', ?)`).bind(randomToken(48)).run();
    value = await read();
  }
  secrets.set(env.DB, value);
  return value;
}

// MARK: - Routing

async function route(ctx, method, parts) {
  const path = parts.join('/');

  // Signing in needs no session.
  if (method === 'POST' && path === 'auth/apple') return signInWithApple(ctx);
  if (method === 'POST' && path === 'auth/apple/signup') return finishAppleSignUp(ctx);
  if (method === 'POST' && path === 'auth/refresh') return refresh(ctx);

  await auth(ctx);
  if (method === 'POST' && path === 'auth/signout') return signOut(ctx);
  if (path === 'me') {
    if (method === 'GET') return json(meJSON(ctx.me));
    if (method === 'PATCH') return updateMe(ctx);
    if (method === 'DELETE') return deleteMe(ctx);
  }
  if (path === 'notes') {
    if (method === 'GET') return listNotes(ctx);
    if (method === 'POST') return addNote(ctx);
  }
  if (parts[0] === 'notes' && parts.length === 2 && method === 'DELETE') return deleteNote(ctx, parts[1]);
  fail(404, 'not_found');
}

// MARK: - Auth

// The user row, plus whether their Apple id is an admin's, in one query.
const USER_WITH_ADMIN = 'SELECT users.*, EXISTS (SELECT 1 FROM admin_apple_ids WHERE admin_apple_ids.apple_sub = users.apple_sub) AS is_admin FROM users';

async function auth(ctx) {
  const header = ctx.request.headers.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const payload = token && (await verifyToken(token, ctx.secret, ctx.now.getTime()));
  if (!payload || payload.typ !== 'a') fail(401, 'unauthorized', 'Sign in again.');
  const me = await ctx.db.prepare(`${USER_WITH_ADMIN} WHERE users.id = ?`).bind(payload.sub).first();
  if (!me) fail(401, 'unauthorized', 'Sign in again.');
  ctx.me = me;
  ctx.family = payload.fam;
}

/** A new pair of tokens. Given the refresh token being swapped, the new one is written only while
 * that one is still live, in one statement, so a sign-out that lands mid-refresh catches it too. */
async function issueSession(ctx, userId, family = newId('fam'), parentHash = null) {
  const refreshToken = randomToken(32);
  const hash = await sha256Hex(refreshToken);
  const nowSeconds = Math.floor(ctx.now.getTime() / 1000);
  if (parentHash) {
    const child = await ctx.db.prepare(`INSERT INTO refresh_tokens (hash, user_id, family, expires_at)
      SELECT ?1, user_id, family, ?2 FROM refresh_tokens WHERE hash = ?3 AND revoked = 0`).bind(hash, nowSeconds + REFRESH_SECONDS, parentHash).run();
    if (!child.meta?.changes) fail(401, 'unauthorized', 'Sign in again.');
  } else {
    await ctx.db.prepare('INSERT INTO refresh_tokens (hash, user_id, family, expires_at) VALUES (?, ?, ?, ?)')
      .bind(hash, userId, family, nowSeconds + REFRESH_SECONDS).run();
  }
  const accessToken = await signToken({ sub: userId, fam: family, typ: 'a', exp: nowSeconds + ACCESS_SECONDS }, ctx.secret);
  return { access_token: accessToken, refresh_token: refreshToken, expires_in: ACCESS_SECONDS };
}

/** Sign in with Apple. Someone coming back is signed straight in. Someone new gets a signed
 * ticket that can create this Apple Account's one account, once, after they choose a username. */
async function signInWithApple(ctx) {
  const input = await body(ctx.request);
  const sub = await verifyAppleIdentityToken(String(input.identity_token || ''), {
    bundleId: ctx.env.APPLE_BUNDLE_ID,
    nonce: input.nonce,
    ...(ctx.env.APPLE_KEYS ? { fetchKeys: ctx.env.APPLE_KEYS } : {}),
    now: ctx.now.getTime(),
  });
  if (!sub) fail(401, 'unauthorized', 'Sign in with Apple did not go through. Try again.');
  // Each nonce works once. Apple's tokens last ten minutes; a day comfortably outlives them.
  const fresh = await ctx.db.prepare('INSERT INTO used_nonces (hash, expires_at) VALUES (?, ?) ON CONFLICT (hash) DO NOTHING')
    .bind(await sha256Hex(String(input.nonce)), Math.floor(ctx.now.getTime() / 1000) + 24 * 3600).run();
  if (!fresh.meta?.changes) fail(401, 'unauthorized', 'Sign in with Apple did not go through. Try again.');

  const user = await ctx.db.prepare(`${USER_WITH_ADMIN} WHERE users.apple_sub = ?`).bind(sub).first();
  if (user) {
    const timezone = safeZone(input.timezone);
    if (timezone !== user.timezone) {
      await ctx.db.prepare('UPDATE users SET timezone = ? WHERE id = ?').bind(timezone, user.id).run();
      user.timezone = timezone;
    }
    return json({ ...(await issueSession(ctx, user.id)), user: meJSON(user) });
  }
  // SIGNUPS "closed" keeps out anyone new; people with an account still sign in.
  if (ctx.env.SIGNUPS === 'closed') fail(403, 'signups_closed', `${APP_NAME} is invite only right now.`);
  const exp = Math.floor(ctx.now.getTime() / 1000) + SIGNUP_SECONDS;
  return json({ signup_ticket: await signToken({ typ: 'signup', apple: sub, exp }, ctx.secret), expires_in: SIGNUP_SECONDS });
}

/** A new person's account, from their ticket and the username they chose. A username someone has
 * already is refused rather than changed, so they choose again. */
async function finishAppleSignUp(ctx) {
  const input = await body(ctx.request);
  const ticket = await verifyToken(String(input.signup_ticket || ''), ctx.secret, ctx.now.getTime());
  if (!ticket || ticket.typ !== 'signup' || typeof ticket.apple !== 'string') {
    fail(401, 'unauthorized', 'That took a while. Sign in with Apple again.');
  }
  if (ctx.env.SIGNUPS === 'closed') fail(403, 'signups_closed', `${APP_NAME} is invite only right now.`);
  const username = normalizeUsername(input.username);
  if (username.length < 2) fail(400, 'invalid_username', 'Usernames are 2 to 24 letters, numbers, dots or underscores.');
  const taken = await ctx.db.prepare('SELECT apple_sub FROM users WHERE apple_sub = ? OR username = ?').bind(ticket.apple, username).all();
  // A ticket never signs in to an account that exists, so once it has made one it is spent.
  if (taken.results.some((row) => row.apple_sub === ticket.apple)) {
    fail(409, 'account_exists', 'This Apple Account has an account already. Sign in with Apple again.');
  }
  if (taken.results.length) fail(409, 'username_taken', 'That username is taken.');
  const id = newId('u');
  const inserted = await ctx.db.prepare('INSERT OR IGNORE INTO users (id, apple_sub, username, name, timezone, created_at) VALUES (?, ?, ?, ?, ?, ?)')
    .bind(id, ticket.apple, username, cleanName(input.name), safeZone(input.timezone), ctx.now.toISOString()).run();
  if (!inserted.meta?.changes) fail(409, 'username_taken', 'That username is taken.');
  const user = await ctx.db.prepare(`${USER_WITH_ADMIN} WHERE users.id = ?`).bind(id).first();
  return json({ ...(await issueSession(ctx, id)), user: meJSON(user) });
}

/** Rotates the refresh token. A token used again after the grace period means it leaked: the
 * whole family is revoked. `used` holds when it was first used, in seconds. */
async function refresh(ctx) {
  const input = await body(ctx.request);
  const hash = await sha256Hex(String(input.refresh_token || ''));
  const row = await ctx.db.prepare('SELECT * FROM refresh_tokens WHERE hash = ?').bind(hash).first();
  const nowSeconds = Math.floor(ctx.now.getTime() / 1000);
  if (!row || row.revoked || row.expires_at <= nowSeconds) fail(401, 'unauthorized', 'Sign in again.');
  if (row.used && nowSeconds - row.used > REFRESH_GRACE_SECONDS) {
    await ctx.db.prepare('UPDATE refresh_tokens SET revoked = 1 WHERE family = ?').bind(row.family).run();
    fail(401, 'unauthorized', 'Sign in again.');
  }
  if (!row.used) await ctx.db.prepare('UPDATE refresh_tokens SET used = ? WHERE hash = ? AND used = 0').bind(nowSeconds, hash).run();
  return json(await issueSession(ctx, row.user_id, row.family, hash));
}

/** This device, or with {"everywhere": true} every device. Access tokens elsewhere run out within
 * 15 minutes, since nothing can renew them. */
async function signOut(ctx) {
  const input = await ctx.request.json().catch(() => ({}));
  if (input?.everywhere === true) {
    await ctx.db.prepare('UPDATE refresh_tokens SET revoked = 1 WHERE user_id = ?').bind(ctx.me.id).run();
  } else {
    await ctx.db.prepare('UPDATE refresh_tokens SET revoked = 1 WHERE family = ?').bind(ctx.family || '').run();
  }
  return empty();
}

// MARK: - Me

function meJSON(user) {
  return { id: user.id, username: user.username, name: user.name || '', is_admin: Boolean(user.is_admin) };
}

async function updateMe(ctx) {
  const input = await body(ctx.request);
  const name = input.name === undefined ? ctx.me.name : cleanName(input.name);
  let username = ctx.me.username;
  if (input.username !== undefined) {
    username = normalizeUsername(input.username);
    if (username.length < 2) fail(400, 'invalid_username', 'Usernames are 2 to 24 letters, numbers, dots or underscores.');
  }
  const changed = await ctx.db.prepare(`UPDATE users SET name = ?1, username = ?2 WHERE id = ?3
    AND NOT EXISTS (SELECT 1 FROM users WHERE username = ?2 AND id != ?3)`).bind(name, username, ctx.me.id).run();
  if (!changed.meta?.changes) fail(409, 'username_taken', 'That username is taken.');
  return json(meJSON({ ...ctx.me, name, username }));
}

/** Apple requires that an app with accounts can delete them from inside the app. Everything the
 * person made goes in one batch, so nothing is left half deleted. Add each new table here. */
async function deleteMe(ctx) {
  const db = ctx.db;
  await db.batch([
    db.prepare('DELETE FROM notes WHERE user_id = ?').bind(ctx.me.id),
    db.prepare('DELETE FROM refresh_tokens WHERE user_id = ?').bind(ctx.me.id),
    db.prepare('DELETE FROM users WHERE id = ?').bind(ctx.me.id),
  ]);
  return empty();
}

// MARK: - Notes (the example data; replace with the app's own)

async function listNotes(ctx) {
  const { results } = await ctx.db.prepare('SELECT id, text, created_at FROM notes WHERE user_id = ? ORDER BY created_at DESC LIMIT ?')
    .bind(ctx.me.id, MAX_NOTES).all();
  return json(results);
}

async function addNote(ctx) {
  const input = await body(ctx.request);
  const text = clean(input.text, MAX_NOTE);
  if (!text) fail(400, 'bad_request', 'A note needs some words.');
  const id = newId('n');
  const createdAt = ctx.now.toISOString();
  // One statement checks the limit and writes, so two requests at once cannot both slip past it.
  const inserted = await ctx.db.prepare(`INSERT INTO notes (id, user_id, text, created_at)
    SELECT ?1, ?2, ?3, ?4 WHERE (SELECT COUNT(*) FROM notes WHERE user_id = ?2) < ?5`).bind(id, ctx.me.id, text, createdAt, MAX_NOTES).run();
  if (!inserted.meta?.changes) fail(400, 'too_many', `Up to ${MAX_NOTES} notes.`);
  return json({ id, text, created_at: createdAt });
}

async function deleteNote(ctx, id) {
  // Someone else's note answers exactly like a missing one, so ids reveal nothing.
  const deleted = await ctx.db.prepare('DELETE FROM notes WHERE id = ? AND user_id = ?').bind(id, ctx.me.id).run();
  if (!deleted.meta?.changes) fail(404, 'not_found');
  return empty();
}

// MARK: - Cleaning input

function clean(value, max) {
  // Line breaks stay; every other control character becomes a space.
  return String(value ?? '').replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g, ' ').trim().slice(0, max);
}

function cleanName(value) {
  return clean(value, 60).replace(/\s+/g, ' ');
}

/** Lowercase letters, numbers, dots and underscores, 24 at most. The app filters the same way. */
function normalizeUsername(value) {
  return String(value ?? '').toLowerCase().replace(/[^a-z0-9._]/g, '').slice(0, 24);
}

function safeZone(value) {
  const zone = String(value || 'UTC');
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zone });
    return zone;
  } catch {
    return 'UTC';
  }
}

// MARK: - Daily cleanup

/** Sessions and sign-in nonces long expired. Add anything else that should not be kept forever. */
export async function cleanUp(env, now = new Date()) {
  await ensureSchema(env.DB);
  const nowSeconds = Math.floor(now.getTime() / 1000);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM refresh_tokens WHERE expires_at < ?').bind(nowSeconds),
    env.DB.prepare('DELETE FROM used_nonces WHERE expires_at < ?').bind(nowSeconds),
  ]);
}
