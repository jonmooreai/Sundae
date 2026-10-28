import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { randomToken } from '../src/crypto.js';
import { SCHEMA_VERSION } from '../src/schema.js';
import { cleanUp } from '../src/worker.js';
import { server } from './harness.mjs';

const later = (s, seconds) => s.setNow(new Date(s.now().getTime() + seconds * 1000));

test('the address says its name, and the privacy page says what the app says, from one shared file', async () => {
  const s = await server();
  const home = await s.call('GET', '', { raw: true });
  assert.equal(await home.text(), '__APP_NAME__\n');
  const page = await (await s.call('GET', 'privacy', { raw: true })).text();
  const policy = JSON.parse(readFileSync(new URL('../../../Shared/privacy.json', import.meta.url), 'utf8'));
  for (const section of policy.sections) {
    assert.ok(page.includes(section.title.replaceAll("'", '&#39;')), section.title);
  }
});

test('every response forbids sniffing, framing and scripts, and none allows a browser to read it', async () => {
  const s = await server();
  const r = await s.call('GET', 'v1/me');
  assert.equal(r.status, 401);
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  assert.match(r.headers.get('content-security-policy'), /default-src 'none'/);
  assert.equal(r.headers.get('access-control-allow-origin'), null);
  assert.equal((await s.call('GET', 'v1/nothing-here')).status, 401, 'unknown paths still need a session');
  assert.equal((await s.call('GET', 'elsewhere')).status, 404);
});

test('someone new gets a ticket, chooses a username, and the ticket makes one account only', async () => {
  const s = await server();
  const first = await s.appleSignIn('apple-pat');
  assert.equal(first.status, 200);
  assert.ok(first.body.signup_ticket);
  assert.equal(first.body.access_token, undefined, 'no session before there is an account');

  const signup = (username) => s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: first.body.signup_ticket, username, name: 'Pat Doe' } });
  assert.equal((await signup('x')).status, 400, 'too short');
  const made = await signup('Pat.Doe!');
  assert.equal(made.status, 200);
  assert.deepEqual(made.body.user, { id: made.body.user.id, username: 'pat.doe', name: 'Pat Doe', is_admin: false });
  assert.ok(made.body.access_token && made.body.refresh_token);

  const again = await signup('pat2');
  assert.equal(again.status, 409);
  assert.equal(again.body.error.code, 'account_exists');
});

test('someone coming back is signed straight in to the account they had', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat');
  const back = await s.appleSignIn('apple-pat');
  assert.equal(back.status, 200);
  assert.equal(back.body.user.id, pat.user.id);
  assert.ok(back.body.access_token);
});

test('a username someone has is refused, not changed', async () => {
  const s = await server();
  await s.signUp('apple-pat', 'pat');
  const first = await s.appleSignIn('apple-sam');
  const taken = await s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: first.body.signup_ticket, username: 'pat' } });
  assert.equal(taken.status, 409);
  assert.equal(taken.body.error.code, 'username_taken');
});

test('a token is refused without its nonce, for another app, once used, and after it expires', async () => {
  const s = await server();
  const nonce = randomToken(24);
  const token = await s.apple.token('apple-pat', { nonce });
  const send = (json) => s.call('POST', 'v1/auth/apple', { json });
  assert.equal((await send({ identity_token: token })).status, 401, 'no nonce');
  assert.equal((await send({ identity_token: token, nonce: randomToken(24) })).status, 401, 'someone else\'s nonce');
  assert.equal((await s.appleSignIn('apple-pat', { aud: 'com.example.other' })).status, 401, 'made for another app');
  assert.equal((await send({ identity_token: token, nonce })).status, 200);
  assert.equal((await send({ identity_token: token, nonce })).status, 401, 'each nonce works once');
  const old = await s.apple.token('apple-pat', { nonce: 'n'.repeat(24), exp: Math.floor(Date.now() / 1000) - 1 });
  assert.equal((await send({ identity_token: old, nonce: 'n'.repeat(24) })).status, 401, 'expired');
  assert.equal((await send({ identity_token: 'not.a.token', nonce })).status, 401);
});

test('closed sign-ups keep out anyone new and let everyone with an account in', async () => {
  const s = await server();
  await s.signUp('apple-pat', 'pat');
  s.env.SIGNUPS = 'closed';
  assert.equal((await s.appleSignIn('apple-pat')).status, 200);
  const stranger = await s.appleSignIn('apple-stranger');
  assert.equal(stranger.status, 403);
  assert.equal(stranger.body.error.code, 'signups_closed');
});

test('refresh tokens rotate, a lost reply is forgiven, and a leaked one ends the session', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat');
  const one = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: pat.refresh } });
  assert.equal(one.status, 200);
  assert.notEqual(one.body.refresh_token, pat.refresh);
  const retry = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: pat.refresh } });
  assert.equal(retry.status, 200, 'the same token again within a minute, as after a lost reply');

  later(s, 120);
  const replay = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: pat.refresh } });
  assert.equal(replay.status, 401, 'used again much later: it leaked');
  const newest = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: retry.body.refresh_token } });
  assert.equal(newest.status, 401, 'and the whole session went with it');
});

test('access tokens last 15 minutes', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat');
  assert.equal((await s.call('GET', 'v1/me', { token: pat.token })).status, 200);
  later(s, 15 * 60 + 1);
  assert.equal((await s.call('GET', 'v1/me', { token: pat.token })).status, 401);
});

test('signing out ends this device, or every device', async () => {
  const s = await server();
  const phone = await s.signUp('apple-pat', 'pat');
  const ipadSignIn = await s.appleSignIn('apple-pat');
  const ipad = { token: ipadSignIn.body.access_token, refresh: ipadSignIn.body.refresh_token };

  assert.equal((await s.call('POST', 'v1/auth/signout', { token: phone.token })).status, 204);
  assert.equal((await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: phone.refresh } })).status, 401);
  assert.equal((await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: ipad.refresh } })).status, 200, 'the iPad is still in');

  const ipad2 = await s.appleSignIn('apple-pat');
  await s.call('POST', 'v1/auth/signout', { token: ipad2.body.access_token, json: { everywhere: true } });
  assert.equal((await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: ipad2.body.refresh_token } })).status, 401);
});

test('notes are each person\'s own', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat');
  const sam = await s.signUp('apple-sam', 'sam');
  const added = await s.call('POST', 'v1/notes', { token: pat.token, json: { text: '  Buy milk\u0000 ' } });
  assert.equal(added.status, 200);
  assert.equal(added.body.text, 'Buy milk');
  assert.equal((await s.call('POST', 'v1/notes', { token: pat.token, json: { text: '   ' } })).status, 400);

  assert.deepEqual((await s.call('GET', 'v1/notes', { token: pat.token })).body.map((n) => n.text), ['Buy milk']);
  assert.deepEqual((await s.call('GET', 'v1/notes', { token: sam.token })).body, []);
  assert.equal((await s.call('DELETE', `v1/notes/${added.body.id}`, { token: sam.token })).status, 404, 'not Sam\'s to delete');
  assert.equal((await s.call('DELETE', `v1/notes/${added.body.id}`, { token: pat.token })).status, 204);
  assert.deepEqual((await s.call('GET', 'v1/notes', { token: pat.token })).body, []);
});

test('a name and username can change, never to someone else\'s', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat');
  await s.signUp('apple-sam', 'sam');
  const changed = await s.call('PATCH', 'v1/me', { token: pat.token, json: { name: 'Pat D', username: 'patd' } });
  assert.equal(changed.status, 200);
  assert.equal(changed.body.username, 'patd');
  assert.equal((await s.call('PATCH', 'v1/me', { token: pat.token, json: { username: 'sam' } })).status, 409);
});

test('deleting the account takes everything, and the same Apple Account can start over', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat');
  await s.call('POST', 'v1/notes', { token: pat.token, json: { text: 'Mine' } });
  assert.equal((await s.call('DELETE', 'v1/me', { token: pat.token })).status, 204);
  for (const table of ['users', 'notes', 'refresh_tokens']) {
    assert.equal(s.env.DB.sqlite.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0, table);
  }
  assert.equal((await s.call('GET', 'v1/me', { token: pat.token })).status, 401);
  const fresh = await s.appleSignIn('apple-pat');
  assert.ok(fresh.body.signup_ticket, 'a new account, not the old one');
});

test('admins come from their Apple id, set from the Cloudflare side', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat');
  assert.equal((await s.call('GET', 'v1/me', { token: pat.token })).body.is_admin, false);
  s.env.DB.sqlite.prepare('INSERT INTO admin_apple_ids (apple_sub) VALUES (?)').run('apple-pat');
  assert.equal((await s.call('GET', 'v1/me', { token: pat.token })).body.is_admin, true);
});

test('the daily cleanup clears expired sessions and nonces', async () => {
  const s = await server();
  await s.signUp('apple-pat', 'pat');
  await cleanUp(s.env, new Date(Date.now() + 40 * 24 * 3600 * 1000));
  assert.equal(s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM refresh_tokens').get().n, 0);
  assert.equal(s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM used_nonces').get().n, 0);
});

test('the schema is applied once and records its version', async () => {
  const s = await server();
  await s.call('GET', 'v1/me');
  assert.equal(s.env.DB.sqlite.prepare(`SELECT value FROM config WHERE key = 'schema_version'`).get().value, SCHEMA_VERSION);
});
