// Sundae's server: the contract in docs/API.md, on one Cloudflare Worker with one D1 database.
// Built for a dozen friends on Cloudflare's free plan. No dependencies, no build step.

import { b64url, hmac, newId, randomToken, sameString, sha256Hex, signToken, verifyAppleIdentityToken, verifyToken } from './crypto.js';
import { addDays, isSunday, isValidDay, recentWeekStarts, safeZone, weekStart, zonedMidnight } from './time.js';
import { ensureSchema } from './schema.js';
import { storage } from './storage.js';
import { PRIVACY_HTML } from './privacy.js';
import { stripJpegMetadata } from './jpeg.js';

const ACCESS_SECONDS = 15 * 60;
const REFRESH_SECONDS = 30 * 24 * 3600;
const UPLOAD_SECONDS = 30 * 60;
// How long someone new has, after Sign in with Apple, to choose a username.
const SIGNUP_SECONDS = 60 * 60;
// A used refresh token still works this long, so a reply lost on a bad connection does not sign
// anyone out. After that, a second use means the token leaked.
const REFRESH_GRACE_SECONDS = 60;
// The app sends 2048 px JPEGs of about 1 MB. These bound what a buggy or misused client can store.
const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
const MAX_UPLOADS_PER_DAY = 150;
const MAX_PHOTOS = 15;
// A line or two under one photo, and the same under each photo of one idea.
const MAX_PHOTO_CAPTION = 200;
const MAX_TAGS = 10;
const MAX_CAPTION = 300;
const MAX_COMMENT = 1000;
// Per person on each week, so nobody can bury a friend's week under comments.
const MAX_COMMENTS = 30;
// User ids are made by newId: 'u_' and twelve of its letters and digits.
const isUserId = (id) => typeof id === 'string' && /^u_[0-9a-hjkmnp-tv-z]{12}$/.test(id);

// A photo's width and height only lay it out before it loads: whole numbers of pixels, or 0 for
// none given. A fraction or a huge number would stop the app reading a whole feed.
const pixels = (value) => (Number.isInteger(value) && value > 0 && value <= 20_000 ? value : 0);

const DEFAULT_SETTINGS = {
  is_public: false, auto_approve_user_ids: [], comments_enabled: true, hide_challenges: false,
  notify_sunday_reminder: true, notify_last_call: true, notify_tags: true, notify_follow_requests: true,
  notify_likes_and_comments: true, notify_tag_approved: false,
};

// MARK: - Responses

// On every response. Nothing here is meant for a browser: no scripts may run, no page may frame
// it, no address leaks in a Referer, and only HTTPS is spoken.
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
  // Daily, from the cron in the repository's wrangler.jsonc.
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
      return new Response('Sundae\n', { headers: { ...SECURITY_HEADERS, 'content-type': 'text/plain; charset=utf-8' } });
    }
    if (!url.pathname.startsWith('/v1/')) fail(404, 'not_found');
    await ensureSchema(env.DB);
    // env.CLOCK exists only in tests, to stand on a Sunday or a Wednesday.
    const now = typeof env.CLOCK === 'function' ? env.CLOCK() : new Date();
    const ctx = { env, db: env.DB, url, origin: url.origin, request, now, me: null, blocked: null, secret: await tokenSecret(env), media: new Map() };
    return await route(ctx, request.method, url.pathname.slice(4).split('/').filter(Boolean));
  } catch (error) {
    if (error instanceof HttpError) return json({ error: { code: error.code, message: error.message } }, error.status);
    console.error('unhandled', error?.stack || error);
    return json({ error: { code: 'server_error', message: 'Something went wrong.' } }, 500);
  }
}

const secrets = new WeakMap();

/** TOKEN_SECRET when set; otherwise one generated on first use and kept in the database. */
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
  const [a, b, c, d] = parts;
  const key = `${method} ${parts.map((p, i) => (isParam(parts, i) ? ':' : p)).join('/')}`;
  switch (key) {
    // Session
    case 'POST auth/apple': return signInWithApple(ctx);
    case 'POST auth/apple/signup': return finishAppleSignUp(ctx);
    case 'POST auth/phone/start':
    case 'POST auth/phone/verify': fail(400, 'not_supported', 'Phone sign-in is not available. Use Sign in with Apple.');
    case 'POST auth/refresh': return refresh(ctx);
    case 'POST auth/signout': await auth(ctx); return signOut(ctx);

    // Uploads and photos carry their own signatures: no bearer token.
    case 'PUT uploads/:': return receiveUpload(ctx, b);
    case 'GET media/:': return serveMedia(ctx, b);
    case 'GET ideas/local': return json([], 200, { 'cache-control': 'public, max-age=86400' });
  }

  await auth(ctx);
  switch (key) {
    // Every day
    case 'GET me': return json(await meJSON(ctx, ctx.me));
    case 'PATCH me': return updateMe(ctx);
    case 'DELETE me': return deleteMe(ctx);
    case 'GET me/settings': return json(settingsOf(ctx.me));
    case 'PUT me/settings': return updateSettings(ctx);
    case 'GET me/taggable': return json(await usersJSON(ctx, await taggable(ctx)));
    case 'GET me/follow-requests': return followRequests(ctx);
    case 'POST me/follow-requests/:': return respondToFollow(ctx, c);
    case 'GET me/followers': return followers(ctx);
    case 'DELETE me/followers/:': return removeFollower(ctx, c);
    case 'GET me/tag-requests': return tagRequests(ctx);
    case 'GET me/suggestions/done': return suggestionsDone(ctx);
    case 'PUT me/suggestions/:/done': return markDone(ctx, c);
    case 'POST tags/:/respond': return respondToTag(ctx, b);
    case 'DELETE tags/:': return removeTag(ctx, b);
    case 'POST uploads': return createUpload(ctx);
    case 'DELETE dumps/:': return deleteDump(ctx, b);
    case 'POST users/:/block': return block(ctx, b);
    case 'POST reports': return report(ctx);
  }

  requireSunday(ctx);
  switch (key) {
    case 'GET feed': return feed(ctx);
    case 'GET dumps/:': return json(await dumpJSON(ctx, await readableDump(ctx, b)));
    case 'GET me/dumps/:': return myDump(ctx, c);
    case 'PUT me/dumps/:': return saveDump(ctx, c);
    case 'PUT dumps/:/like': return likeDump(ctx, b);
    case 'GET dumps/:/comments': return listComments(ctx, b);
    case 'POST dumps/:/comments': return addComment(ctx, b);
    case 'PATCH comments/:': return editComment(ctx, b);
    case 'DELETE comments/:': return deleteComment(ctx, b);
    case 'PUT comments/:/like': return likeComment(ctx, b, true);
    case 'DELETE comments/:/like': return likeComment(ctx, b, false);
    case 'GET users/search': return search(ctx);
    case 'GET users/suggested': return suggested(ctx);
    case 'GET users/:/profile': return profile(ctx, b);
    case 'POST users/:/follow': return follow(ctx, b);
    case 'DELETE users/:/follow': return unfollow(ctx, b);
  }
  void a; void d;
  fail(404, 'not_found');
}

/** Which path segments are ids. Everything after a known collection name is one. */
function isParam(parts, i) {
  const before = parts[i - 1];
  if (i === 0) return false;
  if (['me', 'auth', 'ideas'].includes(before) && i === 1) return false;
  if (before === 'users' && ['search', 'suggested'].includes(parts[i])) return false;
  if (before === 'suggestions' && parts[i] === 'done') return false;
  return ['uploads', 'media', 'dumps', 'comments', 'users', 'tags', 'follow-requests', 'followers', 'suggestions'].includes(before);
}

// MARK: - Auth

// The user row, plus whether they are in the admins table, in one query.
const USER_WITH_ADMIN = 'SELECT users.*, EXISTS (SELECT 1 FROM admins WHERE admins.user_id = users.id) AS is_admin FROM users';

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

function requireSunday(ctx) {
  // Admins can try the Sunday screens any day; nobody else sees a week before its Sunday.
  if (ctx.env.SUNDAY_EVERY_DAY === 'true' || ctx.me.is_admin) return;
  if (!isSunday(ctx.now, ctx.me.timezone)) fail(423, 'sunday_closed', 'Come back Sunday.');
}

/** A new pair. Given the refresh token being swapped, the new one is written only while that one
 * is still live, in one statement, so a sign-out that lands mid-refresh catches it too. */
async function issueSession(ctx, userId, family = newId('fam'), parentHash = null) {
  const refreshToken = randomToken(32);
  const hash = await sha256Hex(refreshToken);
  const expires = Math.floor(ctx.now.getTime() / 1000) + REFRESH_SECONDS;
  if (parentHash) {
    const child = await ctx.db.prepare(`INSERT INTO refresh_tokens (hash, user_id, family, expires_at)
      SELECT ?1, user_id, family, ?2 FROM refresh_tokens WHERE hash = ?3 AND revoked = 0`).bind(hash, expires, parentHash).run();
    if (!child.meta?.changes) fail(401, 'unauthorized', 'Sign in again.');
  } else {
    await ctx.db.prepare('INSERT INTO refresh_tokens (hash, user_id, family, expires_at) VALUES (?, ?, ?, ?)')
      .bind(hash, userId, family, expires).run();
  }
  const accessToken = await signToken({ sub: userId, fam: family, typ: 'a', exp: Math.floor(ctx.now.getTime() / 1000) + ACCESS_SECONDS }, ctx.secret);
  return { access_token: accessToken, refresh_token: refreshToken, expires_in: ACCESS_SECONDS };
}

async function signInWithApple(ctx) {
  const input = await body(ctx.request);
  const sub = await verifyAppleIdentityToken(String(input.identity_token || ''), {
    bundleId: ctx.env.APPLE_BUNDLE_ID || 'com.jonmooreai.sundae',
    nonce: input.nonce,
    ...(ctx.env.APPLE_KEYS ? { fetchKeys: ctx.env.APPLE_KEYS } : {}),
    now: ctx.now.getTime(),
  });
  if (!sub) fail(401, 'unauthorized', 'Sign in with Apple did not go through. Try again.');
  // Apple's tokens last ten minutes; a day comfortably outlives any of them.
  const fresh = await ctx.db.prepare('INSERT INTO used_nonces (hash, expires_at) VALUES (?, ?) ON CONFLICT (hash) DO NOTHING')
    .bind(await sha256Hex(String(input.nonce)), Math.floor(ctx.now.getTime() / 1000) + 24 * 3600).run();
  if (!fresh.meta?.changes) fail(401, 'unauthorized', 'Sign in with Apple did not go through. Try again.');
  const timezone = safeZone(String(input.timezone || 'UTC'));
  const user = await ctx.db.prepare(`${USER_WITH_ADMIN} WHERE users.apple_sub = ?`).bind(sub).first();
  if (user) {
    // Someone coming back: straight in, with everything they set up before.
    await ctx.db.prepare('UPDATE users SET timezone = ? WHERE id = ?').bind(timezone, user.id).run();
    user.timezone = timezone;
    return json({ ...(await issueSession(ctx, user.id)), user: await meJSON(ctx, user) });
  }
  // SIGNUPS "closed" keeps out anyone new once everyone invited has joined. People with an
  // account still sign in.
  if (ctx.env.SIGNUPS === 'closed') fail(403, 'signups_closed', 'Sundae is invite only right now. Ask the person who invited you.');
  if (input.profile_first === true) {
    // The app asks a new person for a username before there is an account. This ticket is all
    // it holds meanwhile: it can create this Apple ID's account once, and do nothing else.
    const exp = Math.floor(ctx.now.getTime() / 1000) + SIGNUP_SECONDS;
    return json({ signup_ticket: await signToken({ typ: 'signup', apple: sub, exp }, ctx.secret), expires_in: SIGNUP_SECONDS });
  }
  // Builds from before profile_first send the username with the first request.
  const name = cleanName(input.name || input.full_name || '');
  const username = await uniqueUsername(ctx, input.username || name || 'friend');
  const created = await createAccount(ctx, { sub, username, name, timezone });
  if (!created) fail(409, 'username_taken', 'That username was just taken. Sign in with Apple again.');
  return json({ ...(await issueSession(ctx, created.id)), user: await meJSON(ctx, created) });
}

/** A new person's account, from the ticket Sign in with Apple gave them and the username they
 * chose. A username someone has already is refused rather than changed, so they choose again. */
async function finishAppleSignUp(ctx) {
  const input = await body(ctx.request);
  const ticket = await verifyToken(String(input.signup_ticket || ''), ctx.secret, ctx.now.getTime());
  if (!ticket || ticket.typ !== 'signup' || typeof ticket.apple !== 'string') {
    fail(401, 'unauthorized', 'That took a while. Sign in with Apple again.');
  }
  if (ctx.env.SIGNUPS === 'closed') fail(403, 'signups_closed', 'Sundae is invite only right now. Ask the person who invited you.');
  const username = normalizeUsername(input.username);
  if (username.length < 2) fail(400, 'invalid_username', 'Usernames are 2 to 24 letters, numbers, dots or underscores.');
  const taken = await ctx.db.prepare('SELECT apple_sub FROM users WHERE apple_sub = ? OR username = ?').bind(ticket.apple, username).all();
  // A ticket never signs in to an account that exists, so once it has made one it is spent.
  if (taken.results.some((row) => row.apple_sub === ticket.apple)) {
    fail(409, 'account_exists', 'This Apple ID has an account already. Sign in with Apple again.');
  }
  if (taken.results.length) fail(409, 'username_taken', 'That username is taken.');
  const created = await createAccount(ctx, {
    sub: ticket.apple, username, name: cleanName(input.name || ''), timezone: safeZone(String(input.timezone || 'UTC')),
  });
  if (!created) fail(409, 'username_taken', 'That username is taken.');
  return json({ ...(await issueSession(ctx, created.id)), user: await meJSON(ctx, created) });
}

/** The new row, or null when the Apple ID or the username was claimed a moment earlier. */
async function createAccount(ctx, { sub, username, name, timezone }) {
  const id = newId('u');
  const inserted = await ctx.db.prepare('INSERT OR IGNORE INTO users (id, apple_sub, username, name, timezone, created_at) VALUES (?, ?, ?, ?, ?, ?)')
    .bind(id, sub, username, name, timezone, ctx.now.toISOString()).run();
  if (!inserted.meta?.changes) return null;
  return ctx.db.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
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

// MARK: - People

function clean(value, max) {
  // Line breaks stay; every other control character becomes a space.
  return String(value ?? '').replace(/[\u0000-\u0009\u000b-\u001f]/g, ' ').trim().slice(0, max);
}

/** A name, on one line, without the invisible characters that make two names look alike but
 * search differently. The zero width joiner stays, since emoji are built with it, and so do the
 * tag characters right after a black flag, which make the England, Scotland and Wales flags. */
function cleanName(value) {
  return clean(String(value ?? '').replace(/\p{Cc}/gu, ' ')
    .replace(/(?!\u200d|(?<=\u{1f3f4}[\u{e0020}-\u{e007e}]*)[\u{e0020}-\u{e007f}])[\p{Cf}\u2028\u2029]/gu, ''), 60);
}

function normalizeUsername(raw) {
  return String(raw || '').toLowerCase().normalize('NFKD').replace(/[^a-z0-9._]/g, '').slice(0, 24);
}

async function uniqueUsername(ctx, raw) {
  let base = normalizeUsername(raw);
  if (base.length < 2) base = 'friend';
  for (let i = 0; i < 50; i++) {
    const candidate = i === 0 ? base : `${base}${i + 1}`;
    const taken = await ctx.db.prepare('SELECT 1 FROM users WHERE username = ?').bind(candidate).first();
    if (!taken) return candidate;
  }
  return `${base}${Math.floor(Math.random() * 100000)}`;
}

async function mediaUrl(ctx, key) {
  if (ctx.media.has(key)) return ctx.media.get(key);
  // Expiry six to seven hours out, on a whole hour, so the same photo keeps one address for an
  // hour and the phone's image cache works.
  const exp = (Math.floor(ctx.now.getTime() / 3600_000) + 7) * 3600;
  const url = `${ctx.origin}/v1/media/${encodeURIComponent(key)}?e=${exp}&s=${await hmac(ctx.secret, `m|${key}|${exp}`)}`;
  ctx.media.set(key, url);
  return url;
}

async function userJSON(ctx, row) {
  return {
    id: row.id, username: row.username, name: row.name || null, bio: row.bio || null,
    avatar_url: row.avatar_key ? await mediaUrl(ctx, row.avatar_key) : null,
    // Nobody's time zone goes to anyone else: it says roughly where they are.
    is_public: Boolean(row.is_public), timezone: null, birthday: null, invited_by_me: null,
  };
}

/** Someone's own account, with their time zone. Only an admin's says so; nobody else's mentions it. */
async function meJSON(ctx, row) {
  return { ...(await userJSON(ctx, row)), timezone: row.timezone, ...(row.is_admin ? { is_admin: true } : {}) };
}

async function usersJSON(ctx, rows) {
  return Promise.all(rows.map((row) => userJSON(ctx, row)));
}

async function usersById(ctx, ids) {
  const unique = [...new Set(ids)].filter(Boolean);
  if (!unique.length) return new Map();
  const { results } = await ctx.db.prepare('SELECT * FROM users WHERE id IN (SELECT value FROM json_each(?))').bind(JSON.stringify(unique)).all();
  return new Map(results.map((r) => [r.id, r]));
}

function settingsOf(user) {
  let stored = {};
  try { stored = JSON.parse(user.settings || '{}'); } catch { stored = {}; }
  return { ...DEFAULT_SETTINGS, ...stored, is_public: Boolean(user.is_public) };
}

async function updateMe(ctx) {
  const input = await body(ctx.request);
  const me = ctx.me;
  if (input.avatar_upload_id) {
    const upload = await ownUpload(ctx, String(input.avatar_upload_id));
    const old = me.avatar_key;
    await ctx.db.prepare('UPDATE users SET avatar_key = ? WHERE id = ?').bind(upload.object_key, me.id).run();
    if (old && old !== upload.object_key) await storage(ctx.env).deleteMany([old]);
  }
  if ('username' in input || 'name' in input || 'bio' in input) {
    const username = 'username' in input ? normalizeUsername(input.username) : me.username;
    if (username.length < 2) fail(400, 'invalid_username', 'Usernames are 2 to 24 letters, numbers, dots or underscores.');
    if (username !== me.username) {
      const taken = await ctx.db.prepare('SELECT 1 FROM users WHERE username = ? AND id != ?').bind(username, me.id).first();
      if (taken) fail(409, 'username_taken', 'That username is taken.');
    }
    const name = 'name' in input ? cleanName(input.name) : me.name;
    const bio = 'bio' in input ? clean(input.bio, 160) : me.bio;
    await ctx.db.prepare('UPDATE users SET username = ?, name = ?, bio = ? WHERE id = ?').bind(username, name, bio, me.id).run();
  }
  const fresh = await ctx.db.prepare('SELECT * FROM users WHERE id = ?').bind(me.id).first();
  return json(await meJSON(ctx, { ...fresh, is_admin: me.is_admin }));
}

async function updateSettings(ctx) {
  const input = await body(ctx.request);
  const next = { ...settingsOf(ctx.me) };
  for (const [k, v] of Object.entries(DEFAULT_SETTINGS)) {
    if (!(k in input)) continue;
    // The one list, auto_approve_user_ids, keeps only user ids, each once, so it stays small.
    if (Array.isArray(v)) next[k] = Array.isArray(input[k]) ? [...new Set(input[k].filter(isUserId))].slice(0, 500) : v;
    else next[k] = Boolean(input[k]);
  }
  await ctx.db.prepare('UPDATE users SET settings = ?, is_public = ? WHERE id = ?')
    .bind(JSON.stringify(next), next.is_public ? 1 : 0, ctx.me.id).run();
  return empty();
}

/** Everything about the account, now, in one transaction. Tags of them on other people's photos
 * are removed, and so are reports they sent and reports about them. Their uploads rows are kept
 * with no owner, so the daily cleanup deletes any photo that could not be deleted here, or that
 * was still arriving. A handful of queries however many weeks they posted. */
async function deleteMe(ctx) {
  const me = ctx.me.id;
  const db = ctx.db;
  const mine = '(SELECT id FROM dumps WHERE author_id = ?1)';
  const { results } = await db.prepare(`
    SELECT object_key FROM uploads WHERE user_id = ?1
    UNION SELECT object_key FROM photos WHERE dump_id IN ${mine}`).bind(me).all();
  const keys = new Set(results.map((r) => r.object_key));
  if (ctx.me.avatar_key) keys.add(ctx.me.avatar_key);
  await db.batch([
    // First, while their weeks, photos and comments are still there to match.
    db.prepare(`DELETE FROM reports WHERE reporter_id = ?1
      OR (target_type = 'profile' AND target_id = ?1)
      OR (target_type = 'dump' AND target_id IN ${mine})
      OR (target_type = 'photo' AND target_id IN (SELECT id FROM photos WHERE dump_id IN ${mine}))
      OR (target_type = 'comment' AND target_id IN (SELECT id FROM comments WHERE author_id = ?1))`).bind(me),
    db.prepare(`DELETE FROM tags WHERE tagged_user_id = ?1 OR tagger_id = ?1 OR photo_id IN (SELECT id FROM photos WHERE dump_id IN ${mine})`).bind(me),
    db.prepare(`DELETE FROM comment_likes WHERE user_id = ?1 OR comment_id IN (SELECT id FROM comments WHERE author_id = ?1 OR dump_id IN ${mine})`).bind(me),
    db.prepare(`DELETE FROM comments WHERE author_id = ?1 OR dump_id IN ${mine}`).bind(me),
    db.prepare(`DELETE FROM likes WHERE user_id = ?1 OR dump_id IN ${mine}`).bind(me),
    db.prepare(`DELETE FROM photos WHERE dump_id IN ${mine}`).bind(me),
    db.prepare('DELETE FROM dumps WHERE author_id = ?1').bind(me),
    db.prepare('DELETE FROM follows WHERE follower_id = ?1 OR followee_id = ?1').bind(me),
    db.prepare('DELETE FROM blocks WHERE blocker_id = ?1 OR blocked_id = ?1').bind(me),
    db.prepare('DELETE FROM refresh_tokens WHERE user_id = ?1').bind(me),
    db.prepare("UPDATE uploads SET user_id = '', expires_at = 0 WHERE user_id = ?1").bind(me),
    db.prepare('DELETE FROM suggestions_done WHERE user_id = ?1').bind(me),
    db.prepare('DELETE FROM users WHERE id = ?1').bind(me),
  ]);
  try {
    await storage(ctx.env).deleteMany([...keys]);
  } catch (error) {
    // The account is gone either way; the daily cleanup deletes these photos.
    console.error('photos left for cleanup', error?.stack || error);
  }
  return empty();
}

/** Everyone the caller has blocked or been blocked by. One query a request, however often it is asked. */
function blockedIds(ctx) {
  ctx.blocked ??= ctx.db.prepare('SELECT blocker_id, blocked_id FROM blocks WHERE blocker_id = ?1 OR blocked_id = ?1').bind(ctx.me.id).all()
    .then(({ results }) => new Set(results.map((r) => (r.blocker_id === ctx.me.id ? r.blocked_id : r.blocker_id))));
  return ctx.blocked;
}

/** Of these authors, the ones whose weeks the caller can read: themselves, public people and people
 * they follow, never anyone blocked either way. One query for any number. */
async function readableAuthors(ctx, authorIds) {
  const unique = [...new Set(authorIds)];
  if (!unique.length) return new Set();
  const { results } = await ctx.db.prepare(`
    SELECT id FROM users WHERE id IN (SELECT value FROM json_each(?2)) AND (id = ?1 OR (${NOT_BLOCKED} AND (
      is_public = 1 OR id IN (SELECT followee_id FROM follows WHERE follower_id = ?1 AND status = 'accepted'))))`)
    .bind(ctx.me.id, JSON.stringify(unique)).all();
  return new Set(results.map((r) => r.id));
}

async function isBlockedBetween(ctx, a, b) {
  return Boolean(await ctx.db.prepare('SELECT 1 FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)')
    .bind(a, b, b, a).first());
}

async function followStatus(ctx, follower, followee) {
  const row = await ctx.db.prepare('SELECT status FROM follows WHERE follower_id = ? AND followee_id = ?').bind(follower, followee).first();
  return row?.status ?? null;
}

async function relationship(ctx, user) {
  if (user.id === ctx.me.id) return 'me';
  if (await isBlockedBetween(ctx, ctx.me.id, user.id)) return 'blocked';
  const status = await followStatus(ctx, ctx.me.id, user.id);
  return status === 'accepted' ? 'following' : status === 'requested' ? 'requested' : 'none';
}

const NOT_BLOCKED = `id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?1) AND id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?1)`;

/** People the caller follows or who follow them, both accepted. The only people they can tag. */
async function taggable(ctx) {
  const { results } = await ctx.db.prepare(`
    SELECT * FROM users WHERE id != ?1 AND ${NOT_BLOCKED} AND (
      id IN (SELECT followee_id FROM follows WHERE follower_id = ?1 AND status = 'accepted') OR
      id IN (SELECT follower_id FROM follows WHERE followee_id = ?1 AND status = 'accepted'))
    ORDER BY username`).bind(ctx.me.id).all();
  return results;
}

async function followRequests(ctx) {
  const { results } = await ctx.db.prepare(`
    SELECT * FROM users WHERE ${NOT_BLOCKED} AND id IN (SELECT follower_id FROM follows WHERE followee_id = ?1 AND status = 'requested')
    ORDER BY username`).bind(ctx.me.id).all();
  return json(await usersJSON(ctx, results));
}

async function respondToFollow(ctx, userId) {
  const input = await body(ctx.request);
  if (input.accept) {
    await ctx.db.prepare(`UPDATE follows SET status = 'accepted' WHERE follower_id = ? AND followee_id = ? AND status = 'requested'`).bind(userId, ctx.me.id).run();
  } else {
    await ctx.db.prepare(`DELETE FROM follows WHERE follower_id = ? AND followee_id = ? AND status = 'requested'`).bind(userId, ctx.me.id).run();
  }
  return empty();
}

/** People who follow the caller, accepted, never anyone blocked either way. */
async function followers(ctx) {
  const { results } = await ctx.db.prepare(`
    SELECT * FROM users WHERE ${NOT_BLOCKED} AND id IN (SELECT follower_id FROM follows WHERE followee_id = ?1 AND status = 'accepted')
    ORDER BY username`).bind(ctx.me.id).all();
  return json(await usersJSON(ctx, results));
}

/** Takes away someone's follow of the caller, or their request. Asking again is a new request
 * while the caller is private. Photos they already saw, and photo addresses already sent, stay
 * with them until those run out. */
async function removeFollower(ctx, userId) {
  await ctx.db.prepare('DELETE FROM follows WHERE follower_id = ? AND followee_id = ?').bind(userId, ctx.me.id).run();
  return empty();
}

async function follow(ctx, userId) {
  if (userId === ctx.me.id) fail(400, 'bad_request', 'That is you.');
  const user = await ctx.db.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!user || (await isBlockedBetween(ctx, ctx.me.id, userId))) fail(404, 'not_found');
  await ctx.db.prepare('INSERT OR IGNORE INTO follows (follower_id, followee_id, status, created_at) VALUES (?, ?, ?, ?)')
    .bind(ctx.me.id, userId, user.is_public ? 'accepted' : 'requested', ctx.now.toISOString()).run();
  const status = await followStatus(ctx, ctx.me.id, userId);
  return json({ relationship: status === 'accepted' ? 'following' : 'requested' });
}

async function unfollow(ctx, userId) {
  await ctx.db.prepare('DELETE FROM follows WHERE follower_id = ? AND followee_id = ?').bind(ctx.me.id, userId).run();
  return empty();
}

/** Hides the two people from each other for good, and takes away everything between them that
 * others could still see: follows, tags, and each one's comments and likes on the other's weeks
 * and comments. There is no unblock, so nothing is kept to bring back. */
async function block(ctx, userId) {
  if (userId === ctx.me.id) fail(400, 'bad_request', 'That is you.');
  const db = ctx.db;
  // Rows one of them left on the other's weeks; ?1 is the caller, ?2 the person blocked.
  const onEachOthers = (person) => `(${person} = ?2 AND dump_id IN (SELECT id FROM dumps WHERE author_id = ?1))
    OR (${person} = ?1 AND dump_id IN (SELECT id FROM dumps WHERE author_id = ?2))`;
  const comments = `SELECT id FROM comments WHERE ${onEachOthers('author_id')}`;
  await db.batch([
    // Only someone who exists, so made-up ids never fill the database.
    db.prepare('INSERT OR IGNORE INTO blocks (blocker_id, blocked_id) SELECT ?1, id FROM users WHERE id = ?2').bind(ctx.me.id, userId),
    db.prepare('DELETE FROM follows WHERE (follower_id = ?1 AND followee_id = ?2) OR (follower_id = ?2 AND followee_id = ?1)').bind(ctx.me.id, userId),
    db.prepare('DELETE FROM tags WHERE (tagger_id = ?1 AND tagged_user_id = ?2) OR (tagger_id = ?2 AND tagged_user_id = ?1)').bind(ctx.me.id, userId),
    db.prepare(`DELETE FROM comment_likes WHERE comment_id IN (${comments})
      OR (user_id = ?2 AND comment_id IN (SELECT id FROM comments WHERE author_id = ?1))
      OR (user_id = ?1 AND comment_id IN (SELECT id FROM comments WHERE author_id = ?2))`).bind(ctx.me.id, userId),
    db.prepare(`DELETE FROM comments WHERE id IN (${comments})`).bind(ctx.me.id, userId),
    db.prepare(`DELETE FROM likes WHERE ${onEachOthers('user_id')}`).bind(ctx.me.id, userId),
  ]);
  return empty();
}

async function report(ctx) {
  const input = await body(ctx.request);
  const targetType = clean(input.target_type, 20);
  const targetId = clean(input.target_id, 80);
  if (!targetType || !targetId) fail(400, 'bad_request', 'What are you reporting?');
  await ctx.db.prepare('INSERT INTO reports (id, reporter_id, target_type, target_id, reason, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(newId('r'), ctx.me.id, targetType, targetId, clean(input.reason, 40) || 'other', input.note ? clean(input.note, 1000) : null, ctx.now.toISOString()).run();
  return empty();
}

async function search(ctx) {
  const q = clean(ctx.url.searchParams.get('q'), 40).toLowerCase().replace(/[%_\\]/g, '');
  if (!q) return json([]);
  const { results } = await ctx.db.prepare(`
    SELECT * FROM users WHERE id != ?1 AND ${NOT_BLOCKED} AND (username LIKE ?2 OR lower(name) LIKE ?3)
    ORDER BY username LIMIT 20`).bind(ctx.me.id, `${q}%`, `%${q}%`).all();
  return json(await usersJSON(ctx, results));
}

/** Public accounts the caller has not followed or asked to follow yet, newest first. Never built
 * from who anyone follows, which nobody else gets to see. */
async function suggested(ctx) {
  const { results } = await ctx.db.prepare(`
    SELECT * FROM users WHERE id != ?1 AND is_public = 1 AND ${NOT_BLOCKED}
      AND id NOT IN (SELECT followee_id FROM follows WHERE follower_id = ?1)
    ORDER BY created_at DESC, username LIMIT 20`).bind(ctx.me.id).all();
  return json(await usersJSON(ctx, results));
}

// MARK: - Uploads and photos

async function createUpload(ctx) {
  const input = await body(ctx.request);
  if (input.content_type !== 'image/jpeg') fail(400, 'invalid_photo', 'Photos are uploaded as JPEG.');
  const size = Number(input.byte_size);
  if (!Number.isInteger(size) || size <= 0 || size > MAX_UPLOAD_BYTES) fail(400, 'invalid_photo', 'That photo is too large.');
  const exp = Math.floor(ctx.now.getTime() / 1000) + UPLOAD_SECONDS;
  const id = newId('up');
  // Counted and written in one statement, so requests sent together cannot all see room for one
  // more. Every ticket expires UPLOAD_SECONDS after it is made, so this counts the last 24 hours.
  const inserted = await ctx.db.prepare(`
    INSERT INTO uploads (id, user_id, object_key, byte_size, width, height, expires_at)
      SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7 WHERE (SELECT COUNT(*) FROM uploads WHERE user_id = ?2 AND expires_at > ?8) < ?9`)
    .bind(id, ctx.me.id, `${id}.jpg`, size, pixels(input.width), pixels(input.height), exp, exp - 24 * 3600, MAX_UPLOADS_PER_DAY).run();
  if (!inserted.meta?.changes) fail(429, 'too_many_uploads', 'That is a lot of photos for one day. Try again tomorrow.');
  const url = `${ctx.origin}/v1/uploads/${id}?e=${exp}&s=${await hmac(ctx.secret, `u|${id}|${exp}`)}`;
  return json({ upload_id: id, url, headers: {}, expires_at: new Date(exp * 1000).toISOString() });
}

async function receiveUpload(ctx, id) {
  const exp = Number(ctx.url.searchParams.get('e'));
  const sig = ctx.url.searchParams.get('s') || '';
  if (!exp || exp * 1000 < ctx.now.getTime() || !sameString(sig, await hmac(ctx.secret, `u|${id}|${exp}`))) fail(403, 'forbidden');
  const upload = await ctx.db.prepare('SELECT * FROM uploads WHERE id = ?').bind(id).first();
  if (!upload || !upload.user_id) fail(404, 'not_found');
  if (upload.uploaded) return empty();
  const bytes = new Uint8Array(await ctx.request.arrayBuffer());
  if (!bytes.length || bytes.length > Math.min(MAX_UPLOAD_BYTES, upload.byte_size + 1024)) fail(400, 'invalid_photo', 'Unexpected size.');
  const clean = stripJpegMetadata(bytes);
  if (!clean) fail(400, 'invalid_photo', 'Not a JPEG, or over 4096 pixels a side.');
  // Claimed before anything is written, so a second PUT on the same ticket, however long its
  // body took, or one still arriving after the account was deleted, writes nothing.
  const claim = await ctx.db.prepare("UPDATE uploads SET uploaded = 1 WHERE id = ? AND uploaded = 0 AND user_id != ''").bind(id).run();
  if (!claim.meta?.changes) return empty();
  try {
    await storage(ctx.env).put(upload.object_key, clean);
  } catch (error) {
    await ctx.db.prepare('UPDATE uploads SET uploaded = 0 WHERE id = ?').bind(id).run();
    throw error;
  }
  // An account deleted while the photo was being stored takes the photo with it.
  const kept = await ctx.db.prepare("UPDATE uploads SET uploaded = 1 WHERE id = ? AND user_id != ''").bind(id).run();
  if (!kept.meta?.changes) {
    await storage(ctx.env).deleteMany([upload.object_key]);
    fail(404, 'not_found');
  }
  return empty();
}

async function serveMedia(ctx, encodedKey) {
  const key = decodeURIComponent(encodedKey);
  const exp = Number(ctx.url.searchParams.get('e'));
  const sig = ctx.url.searchParams.get('s') || '';
  if (!exp || exp * 1000 < ctx.now.getTime() || !sameString(sig, await hmac(ctx.secret, `m|${key}|${exp}`))) fail(403, 'forbidden');
  const bytes = await storage(ctx.env).get(key);
  if (!bytes) fail(404, 'not_found');
  return new Response(bytes, { headers: { ...SECURITY_HEADERS, 'content-type': 'image/jpeg', 'cache-control': 'private, max-age=3600' } });
}

async function ownUpload(ctx, uploadId) {
  const upload = await ctx.db.prepare('SELECT * FROM uploads WHERE id = ? AND user_id = ?').bind(uploadId, ctx.me.id).first();
  if (!upload || !upload.uploaded) fail(400, 'invalid_photo', 'That photo did not finish uploading.');
  return upload;
}

// MARK: - Dumps

function lockedAt(dump, author, now) {
  if (dump.week_start >= weekStart(now, author.timezone)) return null;
  return zonedMidnight(addDays(dump.week_start, 7), author.timezone).toISOString();
}

/** Photos with their visible tags, keyed by photo id. Nobody blocked either way shows up tagged. */
async function photosJSON(ctx, photos) {
  if (!photos.length) return new Map();
  const [{ results: tags }, blocked] = await Promise.all([
    ctx.db.prepare(`
      SELECT * FROM tags WHERE photo_id IN (SELECT value FROM json_each(?)) AND status IN ('pending', 'approved') ORDER BY created_at`)
      .bind(JSON.stringify(photos.map((p) => p.id))).all(),
    blockedIds(ctx),
  ]);
  const people = await usersById(ctx, tags.map((t) => t.tagged_user_id));
  const out = new Map();
  for (const photo of photos) {
    const photoTags = [];
    for (const tag of tags.filter((t) => t.photo_id === photo.id)) {
      const tagged = !blocked.has(tag.tagged_user_id) && people.get(tag.tagged_user_id);
      if (tagged) photoTags.push(await tagJSON(ctx, tag, tagged));
    }
    out.set(photo.id, {
      id: photo.id, dump_id: photo.dump_id, order: photo.ord, url: await mediaUrl(ctx, photo.object_key),
      width: pixels(photo.width) || 1, height: pixels(photo.height) || 1, alt_text: photo.alt_text || null,
      caption: photo.caption || null, tags: photoTags,
    });
  }
  return out;
}

async function tagJSON(ctx, tag, taggedUser) {
  return {
    id: tag.id, photo_id: tag.photo_id, tagger_id: tag.tagger_id, tagged_user: await userJSON(ctx, taggedUser),
    status: tag.status, responded_at: tag.responded_at || null,
  };
}

async function dumpsJSON(ctx, dumps) {
  if (!dumps.length) return [];
  const ids = JSON.stringify(dumps.map((d) => d.id));
  const db = ctx.db;
  // Likes and comments from anyone blocked either way are left out, as the comment list leaves them out.
  const [{ results: photos }, { results: likes }, { results: counts }, { results: firsts }, blocked] = await Promise.all([
    db.prepare('SELECT * FROM photos WHERE dump_id IN (SELECT value FROM json_each(?)) ORDER BY ord').bind(ids).all(),
    db.prepare('SELECT dump_id, user_id FROM likes WHERE dump_id IN (SELECT value FROM json_each(?)) ORDER BY created_at DESC').bind(ids).all(),
    db.prepare(`
      SELECT dump_id, COUNT(*) AS n FROM comments WHERE dump_id IN (SELECT value FROM json_each(?1))
        AND author_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?2)
        AND author_id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?2)
      GROUP BY dump_id`).bind(ids, ctx.me.id).all(),
    db.prepare('SELECT author_id, MIN(week_start) AS first FROM dumps WHERE author_id IN (SELECT value FROM json_each(?)) GROUP BY author_id')
      .bind(JSON.stringify(dumps.map((d) => d.author_id))).all(),
    blockedIds(ctx),
  ]);
  const photoMap = await photosJSON(ctx, photos);
  const people = await usersById(ctx, [...dumps.map((d) => d.author_id), ...likes.map((l) => l.user_id)]);
  const out = [];
  for (const dump of dumps) {
    const author = people.get(dump.author_id);
    if (!author) continue;
    const likers = likes.filter((l) => l.dump_id === dump.id && !blocked.has(l.user_id)).map((l) => people.get(l.user_id)).filter(Boolean);
    out.push({
      id: dump.id, author: await userJSON(ctx, author), week_start: dump.week_start, caption: dump.caption || null,
      created_at: dump.created_at, locked_at: lockedAt(dump, author, ctx.now),
      photos: photos.filter((p) => p.dump_id === dump.id).map((p) => photoMap.get(p.id)),
      comments_enabled: Boolean(dump.comments_enabled),
      liked_by: await usersJSON(ctx, likers),
      liked_by_me: likes.some((l) => l.dump_id === dump.id && l.user_id === ctx.me.id),
      comment_count: counts.find((c) => c.dump_id === dump.id)?.n ?? 0,
      is_authors_first: firsts.find((f) => f.author_id === dump.author_id)?.first === dump.week_start,
    });
  }
  return out;
}

async function dumpJSON(ctx, dump) {
  return (await dumpsJSON(ctx, [dump]))[0];
}

async function readableDump(ctx, id) {
  const dump = await ctx.db.prepare('SELECT * FROM dumps WHERE id = ?').bind(id).first();
  if (!dump || !(await readableAuthors(ctx, [dump.author_id])).has(dump.author_id)) fail(404, 'not_found');
  return dump;
}

async function feed(ctx) {
  const limit = Math.min(Math.max(Number(ctx.url.searchParams.get('limit')) || 10, 1), 30);
  const before = ctx.url.searchParams.get('before');
  const { results } = await ctx.db.prepare(`
    SELECT d.* FROM dumps d
    WHERE (d.author_id = ?1 OR d.author_id IN (SELECT followee_id FROM follows WHERE follower_id = ?1 AND status = 'accepted'))
      AND d.author_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?1)
      AND d.author_id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?1)
      AND (?2 IS NULL OR d.created_at < ?2)
      AND EXISTS (SELECT 1 FROM photos p WHERE p.dump_id = d.id)
    ORDER BY d.created_at DESC LIMIT ?3`).bind(ctx.me.id, before || null, limit).all();
  return json(await dumpsJSON(ctx, results));
}

async function myDump(ctx, week) {
  if (!isValidDay(week)) fail(400, 'bad_request', 'Expected YYYY-MM-DD.');
  const dump = await ctx.db.prepare('SELECT * FROM dumps WHERE author_id = ? AND week_start = ?').bind(ctx.me.id, week).first();
  if (!dump) fail(404, 'not_found');
  return json(await dumpJSON(ctx, dump));
}

/** Creates or edits this week's dump. Reads everything first, then writes it all in one
 * transaction: about twenty queries whether the week has one photo or fifteen. */
async function saveDump(ctx, week) {
  const me = ctx.me;
  if (!isValidDay(week) || week !== weekStart(ctx.now, me.timezone)) fail(423, 'dump_locked', 'That week is closed.');
  const input = await body(ctx.request);
  const caption = clean(input.caption, 10_000);
  if (caption.length > MAX_CAPTION) fail(400, 'caption_too_long', 'Captions are up to 300 characters.');
  const inputs = Array.isArray(input.photos) ? input.photos : [];
  if (inputs.length > MAX_PHOTOS) fail(400, 'too_many_photos', 'Up to 15 photos.');
  if (!inputs.length) fail(400, 'bad_request', 'Add at least one photo.');
  if (inputs.some((p) => Array.isArray(p.tagged_user_ids) && p.tagged_user_ids.length > MAX_TAGS)) fail(400, 'too_many_tags', 'Up to 10 people per photo.');

  const db = ctx.db;
  const nowIso = ctx.now.toISOString();
  const commentsEnabled = input.comments_enabled === false ? 0 : 1;
  const uploadIds = [...new Set(inputs.map((p) => p.upload_id).filter(Boolean).map(String))];
  const found = await db.prepare('SELECT * FROM dumps WHERE author_id = ? AND week_start = ?').bind(me.id, week).first();
  const dumpId = found?.id ?? newId('d');
  const weekDump = '(SELECT id FROM dumps WHERE author_id = ? AND week_start = ?)';
  const [{ results: existing }, { results: uploads }, { results: claimed }, people] = await Promise.all([
    db.prepare('SELECT * FROM photos WHERE dump_id = ?').bind(dumpId).all(),
    db.prepare('SELECT * FROM uploads WHERE user_id = ? AND uploaded = 1 AND id IN (SELECT value FROM json_each(?))').bind(me.id, JSON.stringify(uploadIds)).all(),
    db.prepare('SELECT upload_id, dump_id FROM photos WHERE upload_id IN (SELECT value FROM json_each(?))').bind(JSON.stringify(uploadIds)).all(),
    taggable(ctx),
  ]);
  const { results: currentTags } = existing.length
    ? await db.prepare('SELECT * FROM tags WHERE photo_id IN (SELECT value FROM json_each(?))').bind(JSON.stringify(existing.map((p) => p.id))).all()
    : { results: [] };
  const allowed = new Map(people.map((u) => [u.id, u]));

  const writes = [];
  const kept = [];
  for (const [index, photo] of inputs.entries()) {
    const width = pixels(photo.width);
    const height = pixels(photo.height);
    const alt = photo.alt_text ? clean(photo.alt_text, 500) : null;
    const caption = photo.caption ? clean(photo.caption, MAX_PHOTO_CAPTION) || null : null;
    let row = (photo.id && existing.find((p) => p.id === photo.id)) || null;
    if (!row && photo.upload_id) {
      const uploadId = String(photo.upload_id);
      row = existing.find((p) => p.upload_id === uploadId) || null;
      if (!row) {
        const upload = uploads.find((u) => u.id === uploadId);
        if (!upload) fail(400, 'invalid_photo', 'That photo did not finish uploading.');
        if (claimed.some((c) => c.upload_id === uploadId && c.dump_id !== dumpId)) fail(400, 'invalid_photo', 'That photo is already in another week.');
        row = { id: newId('p'), object_key: upload.object_key, width: pixels(upload.width) || 1, height: pixels(upload.height) || 1, upload_id: uploadId, isNew: true };
        writes.push(db.prepare(`INSERT INTO photos (id, dump_id, ord, object_key, width, height, alt_text, upload_id, caption) VALUES (?, ${weekDump}, ?, ?, ?, ?, ?, ?, ?)`)
          .bind(row.id, me.id, week, index, row.object_key, width || row.width, height || row.height, alt, uploadId, caption));
        existing.push(row);
      }
    }
    if (!row || kept.includes(row.id)) continue;
    kept.push(row.id);
    if (!row.isNew) {
      // A build without captions sends none: it keeps what the photo has rather than clearing it.
      writes.push(db.prepare(`UPDATE photos SET ord = ?, alt_text = ?, width = ?, height = ?${'caption' in photo ? ', caption = ?' : ''} WHERE id = ?`)
        .bind(...[index, alt, width || row.width, height || row.height, ...('caption' in photo ? [caption] : []), row.id]));
    }
    writes.push(...tagWrites(ctx, row.id, currentTags.filter((t) => t.photo_id === row.id), photo.tagged_user_ids, allowed));
  }
  if (!kept.length) fail(400, 'bad_request', 'None of those photos finished uploading.');

  // Whatever in the week this save does not keep goes before any photo is added, chosen by what
  // is kept rather than by what was read: saves sent together cannot each add fifteen, as the
  // last to land leaves only its own. Files of photos it never read go with the daily cleanup.
  // Every write finds the week by author and day, so first saves sent together share one week.
  const keptIds = JSON.stringify(kept);
  const removed = existing.filter((p) => !kept.includes(p.id) && !p.isNew);
  await db.batch([
    db.prepare('INSERT OR IGNORE INTO dumps (id, author_id, week_start, caption, comments_enabled, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .bind(dumpId, me.id, week, caption, commentsEnabled, nowIso, nowIso),
    db.prepare(`DELETE FROM tags WHERE photo_id IN (SELECT id FROM photos WHERE dump_id = ${weekDump} AND id NOT IN (SELECT value FROM json_each(?)))`).bind(me.id, week, keptIds),
    db.prepare(`DELETE FROM photos WHERE dump_id = ${weekDump} AND id NOT IN (SELECT value FROM json_each(?))`).bind(me.id, week, keptIds),
    ...writes,
    db.prepare('UPDATE dumps SET caption = ?, comments_enabled = ?, updated_at = ? WHERE author_id = ? AND week_start = ?').bind(caption, commentsEnabled, nowIso, me.id, week),
  ]);
  await storage(ctx.env).deleteMany(removed.map((p) => p.object_key));
  return json(await dumpJSON(ctx, await db.prepare('SELECT * FROM dumps WHERE author_id = ? AND week_start = ?').bind(me.id, week).first()));
}

/** The writes that bring one photo's tags in line with who is tagged now. Someone still tagged
 * keeps their answer, including a no; new tags wait unless that person auto-approves the tagger.
 * Only people the author can tag count. */
function tagWrites(ctx, photoId, current, requested, allowed) {
  const wanted = [...new Set((Array.isArray(requested) ? requested : []).map(String))].filter((id) => allowed.has(id));
  const writes = [];
  for (const tag of current) {
    if (!wanted.includes(tag.tagged_user_id) && (tag.status === 'pending' || tag.status === 'approved')) {
      writes.push(ctx.db.prepare('DELETE FROM tags WHERE id = ?').bind(tag.id));
    }
  }
  for (const userId of wanted) {
    if (current.some((t) => t.tagged_user_id === userId)) continue;
    const auto = settingsOf(allowed.get(userId)).auto_approve_user_ids.includes(ctx.me.id);
    writes.push(ctx.db.prepare('INSERT OR IGNORE INTO tags (id, photo_id, tagger_id, tagged_user_id, status, responded_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .bind(newId('t'), photoId, ctx.me.id, userId, auto ? 'approved' : 'pending', auto ? ctx.now.toISOString() : null, ctx.now.toISOString()));
  }
  return writes;
}

async function deleteDump(ctx, id) {
  const dump = await ctx.db.prepare('SELECT * FROM dumps WHERE id = ?').bind(id).first();
  if (!dump || dump.author_id !== ctx.me.id) fail(404, 'not_found');
  const db = ctx.db;
  const { results: photos } = await db.prepare('SELECT object_key FROM photos WHERE dump_id = ?').bind(id).all();
  await db.batch([
    db.prepare('DELETE FROM tags WHERE photo_id IN (SELECT id FROM photos WHERE dump_id = ?)').bind(id),
    db.prepare('DELETE FROM photos WHERE dump_id = ?').bind(id),
    db.prepare('DELETE FROM comment_likes WHERE comment_id IN (SELECT id FROM comments WHERE dump_id = ?)').bind(id),
    db.prepare('DELETE FROM comments WHERE dump_id = ?').bind(id),
    db.prepare('DELETE FROM likes WHERE dump_id = ?').bind(id),
    db.prepare('DELETE FROM dumps WHERE id = ?').bind(id),
  ]);
  await storage(ctx.env).deleteMany(photos.map((p) => p.object_key));
  return empty();
}

async function likeDump(ctx, id) {
  const dump = await readableDump(ctx, id);
  const input = await body(ctx.request);
  if (input.liked) {
    await ctx.db.prepare('INSERT OR IGNORE INTO likes (dump_id, user_id, created_at) VALUES (?, ?, ?)').bind(dump.id, ctx.me.id, ctx.now.toISOString()).run();
  } else {
    await ctx.db.prepare('DELETE FROM likes WHERE dump_id = ? AND user_id = ?').bind(dump.id, ctx.me.id).run();
  }
  return json(await dumpJSON(ctx, dump));
}

// MARK: - Comments

async function commentsJSON(ctx, rows) {
  if (!rows.length) return [];
  const ids = JSON.stringify(rows.map((r) => r.id));
  const [{ results: counts }, { results: mine }] = await Promise.all([
    ctx.db.prepare('SELECT comment_id, COUNT(*) AS n FROM comment_likes WHERE comment_id IN (SELECT value FROM json_each(?)) GROUP BY comment_id').bind(ids).all(),
    ctx.db.prepare('SELECT comment_id FROM comment_likes WHERE user_id = ? AND comment_id IN (SELECT value FROM json_each(?))').bind(ctx.me.id, ids).all(),
  ]);
  const people = await usersById(ctx, rows.map((r) => r.author_id));
  const out = [];
  for (const row of rows) {
    const author = people.get(row.author_id);
    if (!author) continue;
    out.push({
      id: row.id, dump_id: row.dump_id, author: await userJSON(ctx, author), body: row.body,
      created_at: row.created_at, edited_at: row.edited_at || null,
      like_count: counts.find((c) => c.comment_id === row.id)?.n ?? 0,
      liked_by_me: mine.some((m) => m.comment_id === row.id),
    });
  }
  return out;
}

async function listComments(ctx, dumpId) {
  const dump = await readableDump(ctx, dumpId);
  const { results } = await ctx.db.prepare(`
    SELECT * FROM comments WHERE dump_id = ?1
      AND author_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?2)
      AND author_id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?2)
    ORDER BY created_at`).bind(dump.id, ctx.me.id).all();
  return json(await commentsJSON(ctx, results));
}

async function addComment(ctx, dumpId) {
  const dump = await readableDump(ctx, dumpId);
  if (!dump.comments_enabled) fail(403, 'forbidden', 'Comments are off for this week.');
  const text = clean((await body(ctx.request)).body, MAX_COMMENT + 1);
  if (!text) fail(400, 'bad_request', 'Say something first.');
  if (text.length > MAX_COMMENT) fail(400, 'bad_request', 'That comment is too long.');
  const id = newId('c');
  // Counted and written in one statement, so comments sent together cannot pass the limit.
  const inserted = await ctx.db.prepare(`
    INSERT INTO comments (id, dump_id, author_id, body, created_at)
      SELECT ?1, ?2, ?3, ?4, ?5 WHERE (SELECT COUNT(*) FROM comments WHERE dump_id = ?2 AND author_id = ?3) < ?6`)
    .bind(id, dump.id, ctx.me.id, text, ctx.now.toISOString(), MAX_COMMENTS).run();
  if (!inserted.meta?.changes) fail(429, 'too_many_comments', 'That is a lot of comments for one week. Up to 30 each.');
  const row = await ctx.db.prepare('SELECT * FROM comments WHERE id = ?').bind(id).first();
  return json((await commentsJSON(ctx, [row]))[0]);
}

async function commentFor(ctx, id) {
  const row = await ctx.db.prepare('SELECT * FROM comments WHERE id = ?').bind(id).first();
  if (!row) fail(404, 'not_found');
  const dump = await readableDump(ctx, row.dump_id);
  return { row, dump };
}

async function editComment(ctx, id) {
  const { row } = await commentFor(ctx, id);
  if (row.author_id !== ctx.me.id) fail(403, 'forbidden', 'Only the author can edit a comment.');
  const text = clean((await body(ctx.request)).body, MAX_COMMENT + 1);
  if (!text || text.length > MAX_COMMENT) fail(400, 'bad_request', 'Comments are 1 to 1000 characters.');
  await ctx.db.prepare('UPDATE comments SET body = ?, edited_at = ? WHERE id = ?').bind(text, ctx.now.toISOString(), id).run();
  const fresh = await ctx.db.prepare('SELECT * FROM comments WHERE id = ?').bind(id).first();
  return json((await commentsJSON(ctx, [fresh]))[0]);
}

async function deleteComment(ctx, id) {
  const row = await ctx.db.prepare('SELECT * FROM comments WHERE id = ?').bind(id).first();
  if (!row) fail(404, 'not_found');
  // Anyone can take back their own comment, even on a week they can no longer open.
  if (row.author_id !== ctx.me.id && (await readableDump(ctx, row.dump_id)).author_id !== ctx.me.id) fail(403, 'forbidden');
  await ctx.db.batch([
    ctx.db.prepare('DELETE FROM comment_likes WHERE comment_id = ?').bind(id),
    ctx.db.prepare('DELETE FROM comments WHERE id = ?').bind(id),
  ]);
  return empty();
}

async function likeComment(ctx, id, liked) {
  const { row } = await commentFor(ctx, id);
  if (liked) await ctx.db.prepare('INSERT OR IGNORE INTO comment_likes (comment_id, user_id) VALUES (?, ?)').bind(id, ctx.me.id).run();
  else await ctx.db.prepare('DELETE FROM comment_likes WHERE comment_id = ? AND user_id = ?').bind(id, ctx.me.id).run();
  return json((await commentsJSON(ctx, [row]))[0]);
}

// MARK: - Tags

async function tagRequests(ctx) {
  const { results } = await ctx.db.prepare(`
    SELECT t.*, d.week_start AS week_start, p.dump_id AS dump_id FROM tags t
      JOIN photos p ON p.id = t.photo_id JOIN dumps d ON d.id = p.dump_id
    WHERE t.tagged_user_id = ? AND t.status = 'pending' ORDER BY t.created_at DESC`).bind(ctx.me.id).all();
  if (!results.length) return json([]);
  const { results: photos } = await ctx.db.prepare('SELECT * FROM photos WHERE id IN (SELECT value FROM json_each(?))')
    .bind(JSON.stringify(results.map((r) => r.photo_id))).all();
  const photoMap = await photosJSON(ctx, photos);
  const people = await usersById(ctx, results.map((r) => r.tagger_id));
  const blocked = await blockedIds(ctx);
  const out = [];
  for (const tag of results) {
    const tagger = people.get(tag.tagger_id);
    const photo = photoMap.get(tag.photo_id);
    if (!tagger || !photo || blocked.has(tagger.id)) continue;
    out.push({ tag: await tagJSON(ctx, tag, ctx.me), photo, tagger: await userJSON(ctx, tagger), week_start: tag.week_start });
  }
  return json(out);
}

async function ownTag(ctx, id) {
  const tag = await ctx.db.prepare('SELECT * FROM tags WHERE id = ?').bind(id).first();
  if (!tag || tag.tagged_user_id !== ctx.me.id) fail(404, 'not_found');
  return tag;
}

async function respondToTag(ctx, id) {
  const tag = await ownTag(ctx, id);
  const input = await body(ctx.request);
  await ctx.db.prepare('UPDATE tags SET status = ?, responded_at = ? WHERE id = ?')
    .bind(input.approve ? 'approved' : 'declined', ctx.now.toISOString(), tag.id).run();
  return empty();
}

async function removeTag(ctx, id) {
  const tag = await ownTag(ctx, id);
  await ctx.db.prepare(`UPDATE tags SET status = 'removed', responded_at = ? WHERE id = ?`).bind(ctx.now.toISOString(), tag.id).run();
  return empty();
}

// MARK: - Profiles

async function profile(ctx, userId) {
  const user = await ctx.db.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!user) fail(404, 'not_found');
  const rel = await relationship(ctx, user);
  if (rel === 'blocked') fail(404, 'not_found');
  const canSee = rel === 'me' || rel === 'following' || Boolean(user.is_public);
  const weeks = [];
  if (canSee) {
    const starts = recentWeekStarts(ctx.now, ctx.me.timezone, 12);
    const oldest = starts[starts.length - 1];
    const { results: own } = await ctx.db.prepare('SELECT * FROM dumps WHERE author_id = ? AND week_start >= ?').bind(user.id, oldest).all();
    const ownJSON = await dumpsJSON(ctx, own);
    const { results: taggedRows } = await ctx.db.prepare(`
      SELECT t.*, d.week_start AS week_start, d.author_id AS author_id, d.id AS dump_id FROM tags t
        JOIN photos p ON p.id = t.photo_id JOIN dumps d ON d.id = p.dump_id
      WHERE t.tagged_user_id = ? AND t.status = 'approved' AND d.author_id != ? AND d.week_start >= ?
      ORDER BY t.responded_at`).bind(user.id, user.id, oldest).all();
    // Someone looking at their own profile sees every tag of them, even on a week they cannot
    // open, so they can remove it; never from anyone blocked either way.
    const blocked = rel === 'me' ? await blockedIds(ctx) : null;
    const readable = rel === 'me' ? null : await readableAuthors(ctx, taggedRows.map((r) => r.author_id));
    const visible = taggedRows.filter((r) => (rel === 'me' ? !blocked.has(r.author_id) : readable.has(r.author_id)));
    const { results: taggedPhotos } = visible.length
      ? await ctx.db.prepare('SELECT * FROM photos WHERE id IN (SELECT value FROM json_each(?))').bind(JSON.stringify(visible.map((r) => r.photo_id))).all()
      : { results: [] };
    const photoMap = await photosJSON(ctx, taggedPhotos);
    const people = await usersById(ctx, visible.map((r) => r.author_id));
    for (const [i, start] of starts.entries()) {
      const dump = ownJSON.find((d) => d.week_start === start) || null;
      const tagged = [];
      for (const row of visible.filter((r) => r.week_start === start)) {
        const from = people.get(row.author_id);
        const photo = photoMap.get(row.photo_id);
        if (from && photo) tagged.push({ photo, from: await userJSON(ctx, from), tag: await tagJSON(ctx, row, user) });
      }
      const isEmpty = !dump && !tagged.length;
      if (i === 0 && rel !== 'me' && isEmpty) continue;
      weeks.push({ week_start: start, dump, tagged });
    }
    while (weeks.length > 1 && !weeks[weeks.length - 1].dump && !weeks[weeks.length - 1].tagged.length) weeks.pop();
  }
  const out = { user: await userJSON(ctx, user), relationship: rel === 'none' ? 'none' : rel, weeks, follower_count: null, following_count: null };
  if (rel === 'me') {
    const followers = await ctx.db.prepare(`SELECT COUNT(*) AS n FROM follows WHERE followee_id = ? AND status = 'accepted'`).bind(user.id).first();
    const following = await ctx.db.prepare(`SELECT COUNT(*) AS n FROM follows WHERE follower_id = ? AND status = 'accepted'`).bind(user.id).first();
    out.follower_count = followers.n;
    out.following_count = following.n;
  }
  return json(out);
}

// MARK: - Suggestions done

async function suggestionsDone(ctx) {
  const week = ctx.url.searchParams.get('week_start');
  if (!isValidDay(week || '')) fail(400, 'bad_request', 'Expected week_start=YYYY-MM-DD.');
  const from = zonedMidnight(week, ctx.me.timezone).toISOString();
  const to = zonedMidnight(addDays(week, 7), ctx.me.timezone).toISOString();
  const { results } = await ctx.db.prepare('SELECT suggestion_id, done_on FROM suggestions_done WHERE user_id = ? AND done_on >= ? AND done_on < ?')
    .bind(ctx.me.id, from, to).all();
  return json(results.map((r) => ({ suggestion_id: r.suggestion_id, done_on: r.done_on })));
}

async function markDone(ctx, suggestionId) {
  const input = await body(ctx.request);
  const day = new Date(input.done_on);
  const doneOn = Number.isNaN(day.getTime()) ? ctx.now.toISOString() : day.toISOString();
  await ctx.db.prepare(`INSERT INTO suggestions_done (user_id, suggestion_id, done_on) VALUES (?, ?, ?)
    ON CONFLICT (user_id, suggestion_id) DO UPDATE SET done_on = excluded.done_on`).bind(ctx.me.id, clean(suggestionId, 80), doneOn).run();
  return empty();
}

// MARK: - Daily cleanup

/** Photos uploaded but never posted or left by a deleted account, and sign-ins long expired.
 * Runs once a day; each run clears up to 500 uploads, far more than a dozen friends leave behind. */
export async function cleanUp(env, now = new Date()) {
  await ensureSchema(env.DB);
  const nowSeconds = Math.floor(now.getTime() / 1000);
  const { results } = await env.DB.prepare(`
    SELECT id, object_key FROM uploads WHERE expires_at < ?
      AND object_key NOT IN (SELECT object_key FROM photos)
      AND object_key NOT IN (SELECT avatar_key FROM users WHERE avatar_key IS NOT NULL)
    LIMIT 500`).bind(nowSeconds - 2 * 24 * 3600).all();
  // Photos first: if that fails, the rows stay for tomorrow's run.
  await storage(env).deleteMany(results.map((r) => r.object_key));
  await env.DB.batch([
    env.DB.prepare('DELETE FROM uploads WHERE id IN (SELECT value FROM json_each(?))').bind(JSON.stringify(results.map((r) => r.id))),
    env.DB.prepare('DELETE FROM refresh_tokens WHERE expires_at < ?').bind(nowSeconds),
    env.DB.prepare('DELETE FROM used_nonces WHERE expires_at < ?').bind(nowSeconds),
  ]);
  return { uploads: results.length };
}

export const _internal = { b64url, isParam };
