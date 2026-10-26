import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { server, r2, jpeg, frame, friends, refresh, uploadPhoto, SUNDAY, WEDNESDAY, NEXT_SUNDAY } from './harness.mjs';
import { cleanUp } from '../src/worker.js';

/** A Sign in with Apple request the way the app sends it: a fresh nonce, signed into the token. */
async function appleSignIn(s, sub, { nonce = `nonce-${Math.random()}-${Date.now()}`, sent = nonce, timezone = 'UTC', ...claims } = {}) {
  const identity_token = await s.apple.token(sub, { nonce, ...claims });
  return { identity_token, nonce: sent, timezone };
}

/** What the server keeps of jpeg(size): the scan, JFIF and the color profile, never the EXIF
 * (with its GPS position) or the comment. */
function assertStripped(buffer, size) {
  const served = Buffer.from(buffer);
  const text = served.toString('latin1');
  assert.ok(!text.includes('GPS') && !text.includes('shot at home'), 'location and comments are gone');
  assert.ok(text.includes('JFIF') && text.includes('ICC_PROFILE'), 'JFIF and the color profile stay');
  const original = Buffer.from(jpeg(size));
  const scan = original.subarray(original.indexOf(Buffer.from([0xff, 0xda])));
  assert.ok(served.subarray(served.length - scan.length).equals(scan), 'the image data is untouched');
  assert.ok(served.length < size);
}

test('Sign in with Apple creates an account once, then signs back in', async () => {
  const s = await server();
  const first = await s.signUp('apple-1', 'Jon Moore', 'Jon');
  assert.equal(first.user.username, 'jonmoore');
  assert.equal(first.user.name, 'Jon');
  const again = await s.call('POST', 'v1/auth/apple', { json: await appleSignIn(s, 'apple-1', { timezone: 'Europe/London' }) });
  assert.equal(again.body.user.id, first.user.id);
  assert.equal(again.body.user.timezone, 'Europe/London');
  const someoneElse = await s.signUp('apple-2', 'jonmoore');
  assert.equal(someoneElse.user.username, 'jonmoore2');
});

test('someone coming back signs straight in; someone new chooses a username first', async () => {
  const s = await server();
  const users = () => s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM users').get().n;

  // New: no account yet, only a ticket, and the ticket opens nothing.
  const first = await s.call('POST', 'v1/auth/apple', { json: { ...(await appleSignIn(s, 'apple-new')), profile_first: true } });
  assert.equal(first.status, 200);
  assert.equal(first.body.access_token, undefined, 'no session before there is an account');
  assert.equal(first.body.expires_in, 3600);
  assert.equal(users(), 0, 'and no account either');
  const ticket = first.body.signup_ticket;
  assert.equal((await s.call('GET', 'v1/me', { token: ticket })).status, 401, 'a ticket is not a session');

  // A username someone has is refused, not quietly changed; the ticket still works after.
  await s.signUp('apple-maya', 'maya');
  const taken = await s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: ticket, username: 'Maya', timezone: 'UTC' } });
  assert.equal(taken.status, 409);
  assert.equal(taken.body.error.code, 'username_taken');
  const tooShort = await s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: ticket, username: '!', timezone: 'UTC' } });
  assert.equal(tooShort.body.error.code, 'invalid_username');
  const made = await s.call('POST', 'v1/auth/apple/signup', {
    json: { signup_ticket: ticket, username: 'Pat.Doe', name: 'Pat Doe', timezone: 'America/Chicago' },
  });
  assert.equal(made.status, 200);
  assert.equal(made.body.user.username, 'pat.doe');
  assert.equal(made.body.user.name, 'Pat Doe');
  assert.equal(made.body.user.timezone, 'America/Chicago');
  assert.equal((await s.call('GET', 'v1/me', { token: made.body.access_token })).body.id, made.body.user.id);

  // Spent: a ticket never signs in to an account, so it cannot be used again.
  const again = await s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: ticket, username: 'pat2', timezone: 'UTC' } });
  assert.equal(again.body.error.code, 'account_exists');
  assert.equal(users(), 2);

  // Coming back: straight in, with the profile and photo they set up.
  await s.call('PATCH', 'v1/me', { token: made.body.access_token, json: { bio: 'Hi' } });
  const back = await s.call('POST', 'v1/auth/apple', { json: { ...(await appleSignIn(s, 'apple-new')), profile_first: true } });
  assert.equal(back.status, 200);
  assert.equal(back.body.signup_ticket, undefined);
  assert.equal(back.body.user.id, made.body.user.id);
  assert.equal(back.body.user.username, 'pat.doe');
  assert.equal(back.body.user.bio, 'Hi');
  assert.ok(back.body.access_token && back.body.refresh_token);
  assert.equal(users(), 2, 'the same account, not a second one');
});

test('a sign-up ticket has to be the server\'s, recent, and a ticket', async () => {
  const s = await server();
  const forged = await s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: 'e30.forged', username: 'pat', timezone: 'UTC' } });
  assert.equal(forged.status, 401);
  const jon = await s.signUp('apple-jon', 'jon');
  const session = await s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: jon.token, username: 'pat', timezone: 'UTC' } });
  assert.equal(session.status, 401, 'a session token is not a ticket');

  const first = await s.call('POST', 'v1/auth/apple', { json: { ...(await appleSignIn(s, 'apple-slow')), profile_first: true } });
  s.setNow(new Date(s.now().getTime() + 61 * 60 * 1000));
  const late = await s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: first.body.signup_ticket, username: 'pat', timezone: 'UTC' } });
  assert.equal(late.status, 401, 'an hour later it has run out');

  // Closing sign-ups closes the second step too, for tickets already handed out.
  const early = await s.call('POST', 'v1/auth/apple', { json: { ...(await appleSignIn(s, 'apple-early')), profile_first: true } });
  s.env.SIGNUPS = 'closed';
  const closed = await s.call('POST', 'v1/auth/apple/signup', { json: { signup_ticket: early.body.signup_ticket, username: 'early', timezone: 'UTC' } });
  assert.equal(closed.body.error.code, 'signups_closed');
  const fresh = await s.call('POST', 'v1/auth/apple', { json: { ...(await appleSignIn(s, 'apple-later')), profile_first: true } });
  assert.equal(fresh.body.error.code, 'signups_closed');
  const jonBack = await s.call('POST', 'v1/auth/apple', { json: { ...(await appleSignIn(s, 'apple-jon')), profile_first: true } });
  assert.equal(jonBack.body.user.id, jon.user.id, 'people with an account still get in');
});

test('tokens from anyone but Apple, or for another app, are refused', async () => {
  const s = await server();
  const wrongApp = await s.call('POST', 'v1/auth/apple', { json: await appleSignIn(s, 'x', { aud: 'com.other.app' }) });
  assert.equal(wrongApp.status, 401);
  const expired = await s.call('POST', 'v1/auth/apple', { json: await appleSignIn(s, 'x', { exp: 1000 }) });
  assert.equal(expired.status, 401);
  const garbage = await s.call('POST', 'v1/auth/apple', { json: { identity_token: 'a.b.c', nonce: 'n'.repeat(32), timezone: 'UTC' } });
  assert.equal(garbage.status, 401);
  assert.equal((await s.call('GET', 'v1/me')).status, 401);
  assert.equal((await s.call('GET', 'v1/me', { token: 'forged.token' })).status, 401);
});

test('Sign in with Apple needs the nonce Apple signed, and each one works once', async () => {
  const s = await server();
  const noNonce = await s.call('POST', 'v1/auth/apple', { json: { identity_token: await s.apple.token('x'), timezone: 'UTC' } });
  assert.equal(noNonce.status, 401, 'a token without a nonce');
  const wrong = await s.call('POST', 'v1/auth/apple', { json: await appleSignIn(s, 'x', { nonce: 'the-nonce-apple-signed-1234', sent: 'some-other-nonce-5678' }) });
  assert.equal(wrong.status, 401, 'a nonce that is not the one Apple signed');
  const request = await appleSignIn(s, 'x');
  assert.equal((await s.call('POST', 'v1/auth/apple', { json: request })).status, 200);
  const replay = await s.call('POST', 'v1/auth/apple', { json: request });
  assert.equal(replay.status, 401, 'the same token and nonce, copied and sent again');
});

test('refresh tokens rotate, and a reused one signs that device out', async () => {
  const s = await server();
  const jon = await s.signUp('apple-jon', 'jon');
  const next = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: jon.refresh } });
  assert.equal(next.status, 200);
  assert.notEqual(next.body.refresh_token, jon.refresh);
  const retry = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: jon.refresh } });
  assert.equal(retry.status, 200, 'a retry within a minute, after a lost reply, still works');
  s.setNow(new Date(s.now().getTime() + 2 * 60_000));
  const replay = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: jon.refresh } });
  assert.equal(replay.status, 401);
  const afterReplay = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: next.body.refresh_token } });
  assert.equal(afterReplay.status, 401, 'the whole family is revoked after a replay');
});

test('the feed, profiles and posting are Sunday only; approvals and settings are every day', async () => {
  const s = await server();
  const { jon } = await friends(s);
  s.setNow(WEDNESDAY);
  assert.equal((await s.call('GET', 'v1/feed', { token: jon.token })).body.error.code, 'sunday_closed');
  assert.equal((await s.call('GET', `v1/users/${jon.user.id}/profile`, { token: jon.token })).status, 423);
  assert.equal((await s.call('GET', 'v1/me/tag-requests', { token: jon.token })).status, 200);
  assert.equal((await s.call('GET', 'v1/me/settings', { token: jon.token })).status, 200);
  s.env.SUNDAY_EVERY_DAY = 'true';
  assert.equal((await s.call('GET', 'v1/feed', { token: jon.token })).status, 200);
});

test('a week is posted with photos and tags, shows in a friend\'s feed, and its photos load', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const up1 = await uploadPhoto(s, jon);
  const up2 = await uploadPhoto(s, jon);
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: {
    caption: 'Bikes and a very long lunch.\nAnd soup.', comments_enabled: true,
    photos: [
      { upload_id: up1, order: 0, width: 2048, height: 1536, alt_text: null, tagged_user_ids: [maya.user.id] },
      { upload_id: up2, order: 1, width: 1536, height: 2048, alt_text: 'Bread', tagged_user_ids: [] },
    ],
  } });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.equal(saved.body.photos.length, 2);
  assert.equal(saved.body.caption, 'Bikes and a very long lunch.\nAnd soup.');
  assert.equal(saved.body.photos[0].tags[0].status, 'pending');
  assert.equal(saved.body.is_authors_first, true);
  assert.equal(saved.body.locked_at, null);

  // Saving again with the same upload ids is the same photos, not new ones.
  const again = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: {
    caption: 'Edited', comments_enabled: true,
    photos: [{ upload_id: up2, order: 0, width: 1536, height: 2048, tagged_user_ids: [] }, { upload_id: up1, order: 1, width: 2048, height: 1536, tagged_user_ids: [maya.user.id] }],
  } });
  assert.deepEqual(again.body.photos.map((p) => p.id), [saved.body.photos[1].id, saved.body.photos[0].id]);

  const feed = await s.call('GET', 'v1/feed?limit=10', { token: maya.token });
  assert.equal(feed.body.length, 1);
  assert.equal(feed.body[0].author.username, 'jon');

  const image = await s.call('GET', feed.body[0].photos[0].url, { raw: true });
  assert.equal(image.status, 200);
  assert.equal(image.headers.get('content-type'), 'image/jpeg');
  assertStripped(await image.arrayBuffer(), 3000);

  const tampered = await s.call('GET', feed.body[0].photos[0].url.replace(/s=[^&]+/, 's=nope'), { raw: true });
  assert.equal(tampered.status, 403);
});

test('a week can only be saved on its own Sunday', async () => {
  const s = await server();
  const { jon } = await friends(s);
  const up = await uploadPhoto(s, jon);
  const wrongWeek = await s.call('PUT', 'v1/me/dumps/2026-10-12', { token: jon.token, json: { caption: '', photos: [{ upload_id: up, order: 0, width: 1, height: 1, tagged_user_ids: [] }] } });
  assert.equal(wrongWeek.body.error.code, 'dump_locked');
  const tooMany = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: Array.from({ length: 16 }, () => ({ upload_id: up })) } });
  assert.equal(tooMany.body.error.code, 'too_many_photos');
  const long = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: 'x'.repeat(301), photos: [{ upload_id: up }] } });
  assert.equal(long.body.error.code, 'caption_too_long');
});

test('photo sizes go out as whole pixels, whatever a client sent', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  // Sizes a script could send, on the ticket and on the photo. The app's own decoder refuses a
  // whole feed for one of them.
  const odd = [1.5, 1e300, '1e308', -7, 'Infinity', 0, null];
  const uploads = [];
  for (const [i, width] of odd.entries()) {
    const ticket = await s.call('POST', 'v1/uploads', {
      token: jon.token, json: { content_type: 'image/jpeg', byte_size: 3000, width, height: odd[(i + 1) % odd.length] },
    });
    assert.equal(ticket.status, 200, JSON.stringify(ticket.body));
    assert.equal((await s.call('PUT', ticket.body.url, { bytes: jpeg(3000) })).status, 204);
    uploads.push(ticket.body.upload_id);
  }
  const honest = await uploadPhoto(s, jon);
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [
    ...uploads.map((upload_id, i) => ({ upload_id, width: odd[(i + 2) % odd.length], height: odd[(i + 3) % odd.length], tagged_user_ids: [maya.user.id] })),
    { upload_id: honest, width: 1536, height: 2048, tagged_user_ids: [maya.user.id] },
  ] } });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.deepEqual([saved.body.photos.at(-1).width, saved.body.photos.at(-1).height], [1536, 2048], 'real sizes are kept');
  const stored = s.env.DB.sqlite.prepare(`SELECT COUNT(*) AS n FROM photos WHERE typeof(width) != 'integer' OR typeof(height) != 'integer' OR width < 1 OR height < 1`).get();
  assert.equal(stored.n, 0, 'nothing odd is stored');

  // Editing a photo with odd sizes keeps the ones it had.
  const edited = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: saved.body.photos.map((p) => (
    { id: p.id, width: 2.5, height: '9e99', tagged_user_ids: [maya.user.id] })) } });
  assert.deepEqual([edited.body.photos.at(-1).width, edited.body.photos.at(-1).height], [1536, 2048]);

  // A row stored before this check still goes out whole.
  s.env.DB.sqlite.prepare('UPDATE photos SET width = 2.5, height = 1e300 WHERE id = ?').run(saved.body.photos[0].id);
  const wholePixels = (photos, where) => {
    assert.equal(photos.length, odd.length + 1, where);
    for (const p of photos) assert.ok([p.width, p.height].every((n) => Number.isInteger(n) && n >= 1 && n <= 20_000), `${where}: ${p.width} x ${p.height}`);
  };
  wholePixels((await s.call('GET', 'v1/feed', { token: maya.token })).body[0].photos, 'feed');
  wholePixels((await s.call('GET', `v1/dumps/${saved.body.id}`, { token: maya.token })).body.photos, 'week');
  wholePixels((await s.call('GET', `v1/users/${jon.user.id}/profile`, { token: maya.token })).body.weeks[0].dump.photos, 'profile');
  wholePixels((await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body.map((r) => r.photo), 'tag requests');
});

test('a photo bigger than the app sends, or without exactly one frame, is refused', async () => {
  const s = await server();
  const jon = await s.signUp('apple-jon', 'jon');
  const ticket = await s.call('POST', 'v1/uploads', { token: jon.token, json: { content_type: 'image/jpeg', byte_size: 3000, width: 2048, height: 1536 } });
  /** The scan of jpeg(3000) with these bytes added before its end. */
  const scanWith = (bytes) => {
    const base = jpeg(3000);
    const out = new Uint8Array(base.length + bytes.length);
    out.set(base.subarray(0, base.length - 2));
    out.set([...bytes, 0xff, 0xd9], base.length - 2);
    return out;
  };
  const refused = {
    'wider than 4096 px': jpeg(3000, { width: 4097, height: 16 }),
    'taller than 4096 px': jpeg(3000, { width: 16, height: 4097 }),
    'a tiny file that says 60000 px square': jpeg(3000, { width: 60000, height: 60000 }),
    'a progressive one 20000 px across': jpeg(3000, { width: 20000, height: 20000, marker: 0xc2 }),
    'no width': jpeg(3000, { width: 0 }),
    'a height left for after the scan': jpeg(3000, { height: 0 }),
    'no frame': jpeg(3000, { frames: 0 }),
    'two frames': jpeg(3000, { frames: 2 }),
    'a second frame after the scan': scanWith(frame(60000, 60000)),
    'a height given after the scan': scanWith([0xff, 0xdc, 0x00, 0x04, 0xea, 0x60]),
  };
  for (const [what, bytes] of Object.entries(refused)) {
    const put = await s.call('PUT', ticket.body.url, { bytes });
    assert.equal(put.status, 400, what);
    assert.equal(put.body.error.code, 'invalid_photo', what);
  }
  assert.equal(s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM blob_chunks').get().n, 0, 'none of them was stored');
  // The ticket is still good for a real photo, as big as the server takes.
  assert.equal((await s.call('PUT', ticket.body.url, { bytes: jpeg(3000, { width: 4096, height: 4096, marker: 0xc2 }) })).status, 204);
});

test('auto-approve keeps only real ids, and blocking an id with no account stores nothing', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const settings = (await s.call('GET', 'v1/me/settings', { token: jon.token })).body;
  const unknown = 'u_abcdefghjkmn';
  const put = await s.call('PUT', 'v1/me/settings', { token: jon.token, json: {
    ...settings, auto_approve_user_ids: [maya.user.id, maya.user.id, 'x'.repeat(4000), `${maya.user.id}x`, { id: maya.user.id }, 42, unknown],
  } });
  assert.equal(put.status, 204);
  const after = (await s.call('GET', 'v1/me/settings', { token: jon.token })).body;
  assert.deepEqual(after.auto_approve_user_ids, [maya.user.id, unknown]);

  const blocks = () => s.env.DB.sqlite.prepare('SELECT blocked_id FROM blocks').all().map((r) => r.blocked_id);
  for (const id of [unknown, `u_${'z'.repeat(15000)}`]) {
    assert.equal((await s.call('POST', `v1/users/${id}/block`, { token: jon.token })).status, 204);
  }
  assert.deepEqual(blocks(), [], 'made-up ids leave no rows');
  assert.equal((await s.call('POST', `v1/users/${maya.user.id}/block`, { token: jon.token })).status, 204);
  assert.deepEqual(blocks(), [maya.user.id]);
  assert.equal((await s.call('GET', 'v1/me/taggable', { token: jon.token })).body.length, 0, 'a real block still works');
});

test('a second PUT on a ticket, still arriving after the photo was posted, changes nothing', async () => {
  const photos = r2();
  const s = await server({ photos });
  const { jon, maya } = await friends(s);
  const ticket = await s.call('POST', 'v1/uploads', { token: jon.token, json: { content_type: 'image/jpeg', byte_size: 3000, width: 2048, height: 1536 } });
  const held = await s.slowPut(ticket.body.url);
  assert.equal((await s.call('PUT', ticket.body.url, { bytes: jpeg(3000) })).status, 204);
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: {
    caption: '', photos: [{ upload_id: ticket.body.upload_id, tagged_user_ids: [maya.user.id] }],
  } });
  const [request] = (await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body;
  await s.call('POST', `v1/tags/${request.tag.id}/respond`, { token: maya.token, json: { approve: true } });
  const before = Buffer.from(await (await s.call('GET', saved.body.photos[0].url, { raw: true })).arrayBuffer());

  // Different bytes, a little bigger, as a swapped photo would be.
  held.finish(jpeg(3500, { width: 1000, height: 1000 }));
  assert.equal((await held.response).status, 204);
  const after = Buffer.from(await (await s.call('GET', saved.body.photos[0].url, { raw: true })).arrayBuffer());
  assert.ok(after.equals(before), 'the posted photo is the one Maya approved');

  // A PUT still arriving after the account is deleted leaves nothing behind.
  const late = await s.call('POST', 'v1/uploads', { token: jon.token, json: { content_type: 'image/jpeg', byte_size: 3000, width: 2048, height: 1536 } });
  const stillSending = await s.slowPut(late.body.url);
  assert.equal((await s.call('DELETE', 'v1/me', { token: jon.token })).status, 204);
  stillSending.finish(jpeg(3000));
  await stillSending.response;
  assert.deepEqual([...photos.objects.keys()], [], 'no photo of Jon\'s is left in storage');
});

test('an upload that fails to store can be sent again', async (t) => {
  t.mock.method(console, 'error', () => {});
  const photos = r2();
  const put = photos.put;
  photos.put = async () => { photos.put = put; throw new Error('storage is down'); };
  const s = await server({ photos });
  const jon = await s.signUp('apple-jon', 'jon');
  const ticket = await s.call('POST', 'v1/uploads', { token: jon.token, json: { content_type: 'image/jpeg', byte_size: 3000, width: 600, height: 600 } });
  assert.equal((await s.call('PUT', ticket.body.url, { bytes: jpeg(3000) })).status, 500);
  const early = await s.call('PATCH', 'v1/me', { token: jon.token, json: { avatar_upload_id: ticket.body.upload_id } });
  assert.equal(early.body.error.code, 'invalid_photo', 'not uploaded yet');
  assert.equal((await s.call('PUT', ticket.body.url, { bytes: jpeg(3000) })).status, 204);
  assert.equal(photos.objects.size, 1);
  const avatar = await s.call('PATCH', 'v1/me', { token: jon.token, json: { avatar_upload_id: ticket.body.upload_id } });
  assert.ok(avatar.body.avatar_url);
});

test('strangers cannot see a private week; tags only go to people you follow', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const stranger = await s.signUp('apple-x', 'stranger');
  const up = await uploadPhoto(s, jon);
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up, order: 0, width: 1, height: 1, tagged_user_ids: [maya.user.id, stranger.user.id] }] } });
  assert.deepEqual(saved.body.photos[0].tags.map((t) => t.tagged_user.username), ['maya']);
  assert.equal((await s.call('GET', `v1/dumps/${saved.body.id}`, { token: stranger.token })).status, 404);
  assert.equal((await s.call('GET', 'v1/feed', { token: stranger.token })).body.length, 0);
  const profile = await s.call('GET', `v1/users/${jon.user.id}/profile`, { token: stranger.token });
  assert.equal(profile.body.relationship, 'none');
  assert.equal(profile.body.weeks.length, 0);
});

test('tag requests are answered, auto-approve skips the wait, and removed tags leave the profile', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const up = await uploadPhoto(s, jon);
  await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up, order: 0, width: 1, height: 1, tagged_user_ids: [maya.user.id] }] } });
  const requests = await s.call('GET', 'v1/me/tag-requests', { token: maya.token });
  assert.equal(requests.body.length, 1);
  assert.equal(requests.body[0].tagger.username, 'jon');
  assert.equal(requests.body[0].week_start, '2026-10-19');
  await s.call('POST', `v1/tags/${requests.body[0].tag.id}/respond`, { token: maya.token, json: { approve: true } });
  const profile = await s.call('GET', `v1/users/${maya.user.id}/profile`, { token: maya.token });
  assert.equal(profile.body.weeks[0].tagged.length, 1);
  await s.call('DELETE', `v1/tags/${requests.body[0].tag.id}`, { token: maya.token });
  const after = await s.call('GET', `v1/users/${maya.user.id}/profile`, { token: maya.token });
  assert.equal(after.body.weeks[0].tagged.length, 0);

  // Maya auto-approves Jon: his next tag lands approved.
  await s.call('PUT', 'v1/me/settings', { token: maya.token, json: { ...(await s.call('GET', 'v1/me/settings', { token: maya.token })).body, auto_approve_user_ids: [jon.user.id] } });
  const up2 = await uploadPhoto(s, jon);
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up2, order: 0, width: 1, height: 1, tagged_user_ids: [maya.user.id] }] } });
  assert.equal(saved.body.photos[0].tags[0].status, 'approved');
});

test('comments: add, like, edit by the author, delete by the author or the week\'s owner', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const up = await uploadPhoto(s, jon);
  const dump = (await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up }] } })).body;
  const added = await s.call('POST', `v1/dumps/${dump.id}/comments`, { token: maya.token, json: { body: 'The third one.\nPut it on the fridge.' } });
  assert.equal(added.status, 200);
  const liked = await s.call('PUT', `v1/comments/${added.body.id}/like`, { token: jon.token });
  assert.equal(liked.body.like_count, 1);
  assert.equal(liked.body.liked_by_me, true);
  assert.equal((await s.call('PATCH', `v1/comments/${added.body.id}`, { token: jon.token, json: { body: 'mine now' } })).status, 403);
  const edited = await s.call('PATCH', `v1/comments/${added.body.id}`, { token: maya.token, json: { body: 'The fourth one.' } });
  assert.ok(edited.body.edited_at);
  const list = await s.call('GET', `v1/dumps/${dump.id}/comments`, { token: jon.token });
  assert.equal(list.body.length, 1);
  assert.equal((await s.call('GET', `v1/dumps/${dump.id}`, { token: jon.token })).body.comment_count, 1);
  assert.equal((await s.call('DELETE', `v1/comments/${added.body.id}`, { token: jon.token })).status, 204);
  assert.equal((await s.call('GET', `v1/dumps/${dump.id}/comments`, { token: jon.token })).body.length, 0);
});

test('likes come back as names, and the week locks when Sunday ends', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const up = await uploadPhoto(s, jon);
  const dump = (await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up }] } })).body;
  const liked = await s.call('PUT', `v1/dumps/${dump.id}/like`, { token: maya.token, json: { liked: true } });
  assert.equal(liked.body.liked_by_me, true);
  assert.deepEqual(liked.body.liked_by.map((u) => u.username), ['maya']);
  s.setNow(NEXT_SUNDAY);
  assert.equal((await s.call('GET', `v1/dumps/${dump.id}`, { token: maya.token })).status, 401, 'the old access token has expired');
  await refresh(s, jon);
  await refresh(s, maya);
  const later = await s.call('GET', `v1/dumps/${dump.id}`, { token: maya.token });
  assert.equal(later.body.locked_at, '2026-10-26T04:00:00.000Z', 'Monday midnight in New York');
  const up2 = await uploadPhoto(s, jon);
  const locked = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up2 }] } });
  assert.equal(locked.body.error.code, 'dump_locked');
});

test('follow requests, search, suggestions and blocking', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await s.call('POST', `v1/users/${theo.user.id}/follow`, { token: maya.token });
  await s.call('POST', `v1/me/follow-requests/${maya.user.id}`, { token: theo.token, json: { accept: true } });
  // Suggestions are public accounts, newest first, never who a friend follows: Maya's private
  // Theo stays out.
  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  s.setNow(new Date(SUNDAY.getTime() + 60_000));
  const sam = await s.signUp('apple-sam', 'sam', 'Sam Doe');
  for (const who of [pat, sam]) await s.call('PUT', 'v1/me/settings', { token: who.token, json: { is_public: true } });
  const suggested = async () => (await s.call('GET', 'v1/users/suggested', { token: jon.token })).body.map((u) => u.username);
  assert.deepEqual(await suggested(), ['sam', 'pat']);
  await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: jon.token });
  await s.call('POST', `v1/users/${jon.user.id}/block`, { token: sam.token });
  assert.deepEqual(await suggested(), [], 'not someone followed, nor someone blocked either way');
  const found = await s.call('GET', 'v1/users/search?q=park', { token: jon.token });
  assert.deepEqual(found.body.map((u) => u.username), ['theo']);
  const requested = await s.call('POST', `v1/users/${theo.user.id}/follow`, { token: jon.token });
  assert.equal(requested.body.relationship, 'requested');
  assert.deepEqual((await s.call('GET', 'v1/me/follow-requests', { token: theo.token })).body.map((u) => u.username), ['jon']);
  await s.call('POST', `v1/users/${jon.user.id}/block`, { token: theo.token });
  assert.equal((await s.call('GET', 'v1/me/follow-requests', { token: theo.token })).body.length, 0);
  assert.equal((await s.call('GET', 'v1/users/search?q=theo', { token: jon.token })).body.length, 0);
});

test('anyone who follows you can be removed, even someone who followed while you were public', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  const sam = await s.signUp('apple-sam', 'sam', 'Sam Doe');
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  // Pat is public for a moment: Sam and Theo follow with no approval.
  await s.call('PUT', 'v1/me/settings', { token: pat.token, json: { is_public: true } });
  for (const who of [sam, theo]) {
    assert.equal((await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: who.token })).body.relationship, 'following');
  }
  await s.call('PUT', 'v1/me/settings', { token: pat.token, json: { is_public: false } });
  const week = await postWeek(s, pat);
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: sam.token })).status, 200, 'going private keeps followers');

  // Every day, and never anyone blocked either way.
  s.setNow(WEDNESDAY);
  s.env.DB.sqlite.prepare('INSERT INTO blocks (blocker_id, blocked_id) VALUES (?, ?)').run(theo.user.id, pat.user.id);
  const listed = await s.call('GET', 'v1/me/followers', { token: pat.token });
  assert.equal(listed.status, 200);
  assert.deepEqual(listed.body.map((u) => [u.username, u.name]), [['sam', 'Sam Doe']]);
  assert.equal(listed.body[0].timezone, null);
  assert.equal((await s.call('DELETE', `v1/me/followers/${sam.user.id}`, { token: pat.token })).status, 204);
  assert.equal((await s.call('DELETE', `v1/me/followers/${sam.user.id}`, { token: pat.token })).status, 204, 'removing again is fine');
  assert.deepEqual((await s.call('GET', 'v1/me/followers', { token: pat.token })).body, []);

  // Sam sees nothing of Pat's now, and neither can tag the other.
  s.setNow(SUNDAY);
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: sam.token })).status, 404);
  assert.equal((await s.call('GET', `v1/dumps/${week.id}/comments`, { token: sam.token })).status, 404);
  assert.equal((await s.call('PUT', `v1/dumps/${week.id}/like`, { token: sam.token, json: { liked: true } })).status, 404);
  assert.equal((await s.call('GET', 'v1/feed', { token: sam.token })).body.length, 0);
  const profile = await s.call('GET', `v1/users/${pat.user.id}/profile`, { token: sam.token });
  assert.equal(profile.body.relationship, 'none');
  assert.deepEqual(profile.body.weeks, []);
  assert.deepEqual((await s.call('GET', 'v1/me/taggable', { token: sam.token })).body, []);
  assert.deepEqual((await s.call('GET', 'v1/me/taggable', { token: pat.token })).body, []);

  // Following again is a request Pat can turn down, and removing a request turns it down.
  assert.equal((await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: sam.token })).body.relationship, 'requested');
  assert.deepEqual((await s.call('GET', 'v1/me/follow-requests', { token: pat.token })).body.map((u) => u.username), ['sam']);
  assert.deepEqual((await s.call('GET', 'v1/me/followers', { token: pat.token })).body, []);
  await s.call('DELETE', `v1/me/followers/${sam.user.id}`, { token: pat.token });
  assert.deepEqual((await s.call('GET', 'v1/me/follow-requests', { token: pat.token })).body, []);
});

test('names lose invisible characters that make look-alikes, and keep emoji', async () => {
  const s = await server();
  const sam = await s.signUp('apple-sam', 'sam', 'S\u200bam\u2028 Doe');
  assert.equal(sam.user.name, 'Sam Doe');
  const pat = await s.signUp('apple-pat', 'pat', 'Pat');
  const named = async (name) => (await s.call('PATCH', 'v1/me', { token: pat.token, json: { name } })).body.name;
  assert.equal(await named('S\u200bam \u202eDoe\u2066\u2069\u2029\u00ad\ufeff'), 'Sam Doe');
  assert.equal(await named('Sam\nDoe\u0085\u007f'), 'Sam Doe');
  assert.equal(await named('Pat \u{1f469}\u200d\u{1f467}'), 'Pat \u{1f469}\u200d\u{1f467}', 'the joiner in a family emoji stays');
  await s.call('PATCH', 'v1/me', { token: pat.token, json: { name: 'S\u200bam Doe', bio: 'Line one\nLine two' } });
  assert.equal((await s.call('GET', 'v1/me', { token: pat.token })).body.bio, 'Line one\nLine two', 'a bio keeps its line breaks');
  const found = await s.call('GET', 'v1/users/search?q=sam%20doe', { token: sam.token });
  assert.deepEqual(found.body.map((u) => u.username), ['pat'], 'a look-alike shows up when searching the name it copies');
});

/** Each follows the other, both accepted. */
async function mutual(s, a, b) {
  for (const [from, to] of [[a, b], [b, a]]) {
    await s.call('POST', `v1/users/${to.user.id}/follow`, { token: from.token });
    await s.call('POST', `v1/me/follow-requests/${from.user.id}`, { token: to.token, json: { accept: true } });
  }
}

async function postWeek(s, who, tagged = []) {
  const up = await uploadPhoto(s, who);
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: who.token, json: { caption: '', photos: [{ upload_id: up, tagged_user_ids: tagged.map((u) => u.user.id) }] } });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  return saved.body;
}

test('blocking takes away comments, likes and tags between the two, for everyone', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await mutual(s, jon, theo);
  await mutual(s, maya, theo);
  const jons = await postWeek(s, jon, [maya]);
  const mayas = await postWeek(s, maya, [jon]);
  const theos = await postWeek(s, theo, [jon, maya]);
  const request = (await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body.find((r) => r.tagger.id === jon.user.id);
  await s.call('POST', `v1/tags/${request.tag.id}/respond`, { token: maya.token, json: { approve: true } });
  const comment = async (who, dump, text) => (await s.call('POST', `v1/dumps/${dump.id}/comments`, { token: who.token, json: { body: text } })).body;
  const like = (who, dump) => s.call('PUT', `v1/dumps/${dump.id}/like`, { token: who.token, json: { liked: true } });
  await comment(maya, jons, 'Something unkind');
  await comment(theo, jons, 'Lovely');
  await comment(jon, mayas, 'Nice bread');
  const jonOnTheos = await comment(jon, theos, 'Great hike');
  await comment(maya, theos, 'So green');
  await s.call('PUT', `v1/comments/${jonOnTheos.id}/like`, { token: maya.token });
  for (const [who, dump] of [[maya, jons], [jon, mayas], [jon, theos], [maya, theos]]) await like(who, dump);

  assert.equal((await s.call('POST', `v1/users/${maya.user.id}/block`, { token: jon.token })).status, 204);

  // Theo, who still follows both, sees nothing of either on the other's week.
  const week = async (who, dump) => (await s.call('GET', `v1/dumps/${dump.id}`, { token: who.token })).body;
  const comments = async (who, dump) => (await s.call('GET', `v1/dumps/${dump.id}/comments`, { token: who.token })).body;
  const tagged = (dump) => dump.photos[0].tags.map((t) => t.tagged_user.username);
  const onJons = await week(theo, jons);
  assert.deepEqual((await comments(theo, jons)).map((c) => c.body), ['Lovely']);
  assert.equal(onJons.comment_count, 1);
  assert.deepEqual(onJons.liked_by, []);
  assert.deepEqual(tagged(onJons), []);
  const onMayas = await week(theo, mayas);
  assert.deepEqual(await comments(theo, mayas), []);
  assert.equal(onMayas.comment_count, 0);
  assert.deepEqual(onMayas.liked_by, []);
  assert.deepEqual(tagged(onMayas), []);
  const mayasProfile = (await s.call('GET', `v1/users/${maya.user.id}/profile`, { token: theo.token })).body;
  assert.ok(mayasProfile.weeks.every((w) => !w.tagged.length), 'Jon\'s photo is gone from Maya\'s profile');

  // On Theo's week, which both can still read, each sees nothing of the other.
  for (const [me, them, mine] of [[jon, maya, 'Great hike'], [maya, jon, 'So green']]) {
    const seen = await week(me, theos);
    assert.deepEqual(seen.liked_by.map((u) => u.id), [me.user.id]);
    assert.deepEqual(tagged(seen), [me.user.username]);
    assert.equal(seen.comment_count, 1);
    const list = await comments(me, theos);
    assert.deepEqual(list.map((c) => c.body), [mine]);
    assert.ok(!JSON.stringify(seen).includes(them.user.id));
  }
  assert.equal((await comments(theo, theos)).find((c) => c.id === jonOnTheos.id).like_count, 0, 'Maya\'s like on Jon\'s comment is gone');
  assert.deepEqual(tagged(await week(theo, theos)).sort(), ['jon', 'maya'], 'tags by someone else stay');

  const left = s.env.DB.sqlite.prepare(`SELECT
    (SELECT COUNT(*) FROM tags WHERE tagged_user_id IN (?1, ?2) AND tagger_id IN (?1, ?2)) AS tags,
    (SELECT COUNT(*) FROM comments WHERE author_id = ?2 AND dump_id = ?3) AS comments,
    (SELECT COUNT(*) FROM likes WHERE user_id = ?1 AND dump_id = ?4) AS likes`).get(jon.user.id, maya.user.id, jons.id, mayas.id);
  assert.deepEqual({ ...left }, { tags: 0, comments: 0, likes: 0 });
});

test('a block made before this kept old likes, tags and comments, and they still show nobody', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await mutual(s, jon, theo);
  await mutual(s, maya, theo);
  const theos = await postWeek(s, theo, [maya]);
  await s.call('PUT', `v1/dumps/${theos.id}/like`, { token: maya.token, json: { liked: true } });
  await s.call('POST', `v1/dumps/${theos.id}/comments`, { token: maya.token, json: { body: 'So green' } });
  // The block row alone, as an earlier server wrote it, with nothing cleared.
  s.env.DB.sqlite.prepare('INSERT INTO blocks (blocker_id, blocked_id) VALUES (?, ?)').run(maya.user.id, jon.user.id);
  const seen = (await s.call('GET', `v1/dumps/${theos.id}`, { token: jon.token })).body;
  assert.deepEqual(seen.liked_by, []);
  assert.deepEqual(seen.photos[0].tags, []);
  assert.equal(seen.comment_count, 0);
  assert.ok(!JSON.stringify(seen).includes(maya.user.id));
  assert.equal((await s.call('GET', `v1/dumps/${theos.id}`, { token: theo.token })).body.photos[0].tags.length, 1, 'Theo still sees his tag');
});

test('your own profile shows tags of you on weeks you cannot open, never from someone blocked', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  // Private Theo follows Maya, so he can tag her, but she does not follow him.
  await s.call('POST', `v1/users/${maya.user.id}/follow`, { token: theo.token });
  await s.call('POST', `v1/me/follow-requests/${theo.user.id}`, { token: maya.token, json: { accept: true } });
  await postWeek(s, theo, [maya]);
  const request = (await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body[0];
  await s.call('POST', `v1/tags/${request.tag.id}/respond`, { token: maya.token, json: { approve: true } });
  const taggedOn = async (who) => (await s.call('GET', `v1/users/${maya.user.id}/profile`, { token: who.token })).body.weeks.flatMap((w) => w.tagged);
  const own = await taggedOn(maya);
  assert.deepEqual(own.map((t) => t.tag.id), [request.tag.id], 'Maya can find it, and so remove it');
  assert.deepEqual(await taggedOn(jon), [], 'Jon cannot read Theo, so it is not shown to him');
  s.env.DB.sqlite.prepare('INSERT INTO blocks (blocker_id, blocked_id) VALUES (?, ?)').run(theo.user.id, maya.user.id);
  assert.deepEqual(await taggedOn(maya), [], 'never from someone blocked either way');
});

test('a comment\'s author can always delete it; an unlike never shows a week to someone who cannot read it', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await mutual(s, jon, theo);
  const dump = await postWeek(s, jon);
  const mayas = (await s.call('POST', `v1/dumps/${dump.id}/comments`, { token: maya.token, json: { body: 'Pat says hi' } })).body;
  await s.call('PUT', `v1/dumps/${dump.id}/like`, { token: maya.token, json: { liked: true } });
  assert.equal((await s.call('DELETE', `v1/comments/${mayas.id}`, { token: theo.token })).status, 403, 'not Theo\'s to delete');
  await s.call('DELETE', `v1/users/${jon.user.id}/follow`, { token: maya.token });
  assert.equal((await s.call('GET', `v1/dumps/${dump.id}`, { token: maya.token })).status, 404, 'Jon is private and Maya no longer follows him');

  const unlike = await s.call('PUT', `v1/dumps/${dump.id}/like`, { token: maya.token, json: { liked: false } });
  assert.equal(unlike.status, 404);
  assert.deepEqual(Object.keys(unlike.body), ['error'], 'no photos, caption or likers');
  assert.equal((await s.call('DELETE', `v1/comments/${mayas.id}`, { token: maya.token })).status, 204);
  assert.deepEqual((await s.call('GET', `v1/dumps/${dump.id}/comments`, { token: theo.token })).body, []);
});

test('nobody\'s time zone goes to anyone else; their own account still has it', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const dump = await postWeek(s, maya, [jon]);
  await s.call('PUT', `v1/dumps/${dump.id}/like`, { token: jon.token, json: { liked: true } });
  await s.call('POST', `v1/dumps/${dump.id}/comments`, { token: maya.token, json: { body: 'Hi' } });
  assert.equal((await s.call('GET', 'v1/me', { token: maya.token })).body.timezone, 'America/New_York');
  const seen = [
    ...(await s.call('GET', 'v1/users/search?q=maya', { token: jon.token })).body,
    (await s.call('GET', `v1/users/${maya.user.id}/profile`, { token: jon.token })).body.user,
    (await s.call('GET', `v1/dumps/${dump.id}`, { token: jon.token })).body.author,
    ...(await s.call('GET', `v1/dumps/${dump.id}/comments`, { token: jon.token })).body.map((c) => c.author),
    ...(await s.call('GET', 'v1/me/taggable', { token: jon.token })).body,
  ];
  assert.equal(seen.length, 5);
  for (const user of seen) assert.equal(user.timezone, null);
});

test('deleting an account removes everything of theirs', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  const up = await uploadPhoto(s, jon);
  const dump = (await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up, tagged_user_ids: [maya.user.id] }] } })).body;
  await s.call('POST', `v1/dumps/${dump.id}/comments`, { token: maya.token, json: { body: 'hi' } });
  const his = await s.call('POST', `v1/dumps/${dump.id}/comments`, { token: jon.token, json: { body: 'thanks' } });
  // Reports he sent, reports about him and everything of his, and one about someone else.
  const report = (who, target_type, target_id, note) => s.call('POST', 'v1/reports', { token: who.token, json: { target_type, target_id, reason: 'other', note } });
  await report(jon, 'profile', pat.user.id, 'Pat Doe posted something unkind');
  for (const [type, id] of [['profile', jon.user.id], ['dump', dump.id], ['photo', dump.photos[0].id], ['comment', his.body.id]]) {
    assert.equal((await report(maya, type, id)).status, 204);
  }
  await report(maya, 'profile', pat.user.id);
  assert.equal((await s.call('DELETE', 'v1/me', { token: jon.token })).status, 204);
  assert.equal((await s.call('GET', 'v1/me', { token: jon.token })).status, 401);
  assert.equal((await s.call('GET', 'v1/feed', { token: maya.token })).body.length, 0);
  const left = s.env.DB.sqlite.prepare('SELECT (SELECT COUNT(*) FROM photos) AS photos, (SELECT COUNT(*) FROM blob_chunks) AS blobs, (SELECT COUNT(*) FROM tags) AS tags, (SELECT COUNT(*) FROM comments) AS comments').get();
  assert.deepEqual({ ...left }, { photos: 0, blobs: 0, tags: 0, comments: 0 });
  const reports = s.env.DB.sqlite.prepare('SELECT reporter_id, target_id FROM reports').all().map((r) => ({ ...r }));
  assert.deepEqual(reports, [{ reporter_id: maya.user.id, target_id: pat.user.id }], 'only Maya\'s report about Pat is left');
});

test('a photo stored while its account is deleted goes with the account', async () => {
  const photos = r2();
  const s = await server({ photos });
  const jon = await s.signUp('apple-jon', 'jon');
  const ticket = await s.call('POST', 'v1/uploads', { token: jon.token, json: { content_type: 'image/jpeg', byte_size: 3000, width: 2048, height: 1536 } });
  // The account is deleted after the PUT has claimed its ticket, before R2 has the photo.
  const put = photos.put;
  photos.put = async (key, bytes) => {
    photos.put = put;
    assert.equal((await s.call('DELETE', 'v1/me', { token: jon.token })).status, 204);
    return put(key, bytes);
  };
  assert.equal((await s.call('PUT', ticket.body.url, { bytes: jpeg(3000) })).status, 404);
  assert.equal(photos.objects.size, 0, 'nothing of Jon\'s is left in storage');
  assert.equal((await s.call('PUT', ticket.body.url, { bytes: jpeg(3000) })).status, 404, 'the ticket is no good now');
  assert.equal(photos.objects.size, 0);
});

test('when photos cannot be deleted with the account, the account still goes and the daily cleanup takes them', async (t) => {
  t.mock.method(console, 'error', () => {});
  const photos = r2();
  const s = await server({ photos });
  const { jon, maya } = await friends(s);
  const posted = await uploadPhoto(s, jon);
  const avatar = await uploadPhoto(s, jon);
  await uploadPhoto(s, jon);
  await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: posted }] } });
  await s.call('PATCH', 'v1/me', { token: jon.token, json: { avatar_upload_id: avatar } });
  const mayas = await uploadPhoto(s, maya);
  assert.equal(photos.objects.size, 4);

  const remove = photos.delete;
  photos.delete = async () => { photos.delete = remove; throw new Error('storage is down'); };
  assert.equal((await s.call('DELETE', 'v1/me', { token: jon.token })).status, 204, 'the account is gone, so say so');
  assert.equal((await s.call('GET', 'v1/me', { token: jon.token })).status, 401);
  assert.equal(photos.objects.size, 4, 'R2 still has them for now');

  await cleanUp(s.env, new Date(SUNDAY.getTime() + 60_000));
  assert.deepEqual([...photos.objects.keys()], [`${mayas}.jpg`], 'the next cleanup deletes all of Jon\'s');
  assert.equal(s.env.DB.sqlite.prepare("SELECT COUNT(*) AS n FROM uploads WHERE user_id = ''").get().n, 0);
});

test('a refresh under way when someone signs out everywhere is refused', async () => {
  for (const everywhere of [true, false]) {
    const s = await server();
    const phone = await s.signUp('apple-jon', 'jon');
    const thief = { ...phone };
    // Sign out lands after the refresh has checked its token, before it writes the next one.
    const prepare = s.env.DB.prepare;
    let armed = true;
    s.env.DB.prepare = (sql) => {
      const statement = prepare(sql);
      if (!armed || !sql.includes('INSERT INTO refresh_tokens')) return statement;
      return { ...statement, bind: (...values) => {
        const bound = statement.bind(...values);
        return { ...bound, run: async () => {
          armed = false;
          assert.equal((await s.call('POST', 'v1/auth/signout', { token: phone.token, json: { everywhere } })).status, 204);
          return bound.run();
        } };
      } };
    };
    assert.equal((await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: thief.refresh } })).status, 401);
    s.env.DB.prepare = prepare;
    const live = s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM refresh_tokens WHERE revoked = 0').get().n;
    assert.equal(live, 0, 'no refresh token is left that still works');
  }
});

test('profile, settings, the privacy page, and a bigger photo across chunks', async () => {
  const s = await server();
  const { jon } = await friends(s);
  const patched = await s.call('PATCH', 'v1/me', { token: jon.token, json: { name: 'Jon M', username: 'Jon.M', bio: 'Sundays only.' } });
  assert.equal(patched.body.username, 'jon.m');
  const settings = await s.call('GET', 'v1/me/settings', { token: jon.token });
  assert.equal(settings.body.notify_sunday_reminder, true);
  const big = await uploadPhoto(s, jon, 700_000);
  const avatar = await s.call('PATCH', 'v1/me', { token: jon.token, json: { avatar_upload_id: big } });
  const image = await s.call('GET', avatar.body.avatar_url, { raw: true });
  assertStripped(await image.arrayBuffer(), 700_000);
  const privacy = await s.call('GET', 'privacy', { raw: true });
  assert.match(await privacy.text(), /What Sundae never collects/);
  const own = await s.call('GET', `v1/users/${jon.user.id}/profile`, { token: jon.token });
  assert.equal(own.body.relationship, 'me');
  assert.equal(own.body.follower_count, 1);
});

test('weekday ideas marked done come back for their week', async () => {
  const s = await server();
  const jon = await s.signUp('apple-jon', 'jon');
  s.setNow(WEDNESDAY);
  await s.call('PUT', 'v1/me/suggestions/s003/done', { token: jon.token, json: { done_on: WEDNESDAY.toISOString() } });
  const done = await s.call('GET', 'v1/me/suggestions/done?week_start=2026-10-19', { token: jon.token });
  assert.deepEqual(done.body.map((d) => d.suggestion_id), ['s003']);
  void SUNDAY;
});

test('every response forbids sniffing, framing, scripts and referrers', async () => {
  const s = await server();
  const jon = await s.signUp('apple-jon', 'jon');
  const up = await uploadPhoto(s, jon);
  const week = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up }] } });
  const responses = {
    api: await s.call('GET', 'v1/me', { token: jon.token, raw: true }),
    error: await s.call('GET', 'v1/me', { raw: true }),
    photo: await s.call('GET', week.body.photos[0].url, { raw: true }),
    privacy: await s.call('GET', 'privacy', { raw: true }),
  };
  for (const [name, r] of Object.entries(responses)) {
    assert.equal(r.headers.get('x-content-type-options'), 'nosniff', name);
    assert.equal(r.headers.get('referrer-policy'), 'no-referrer', name);
    assert.match(r.headers.get('content-security-policy'), /default-src 'none'.*frame-ancestors 'none'/, name);
    assert.doesNotMatch(r.headers.get('content-security-policy'), /script-src/, name);
    assert.match(r.headers.get('strict-transport-security'), /max-age=\d+/, name);
    assert.equal(r.headers.get('access-control-allow-origin'), null, `${name}: no browser on another site can read it`);
  }
});

test('with sign-ups closed, nobody new gets in and everyone else still signs in', async () => {
  const s = await server();
  const jon = await s.signUp('apple-jon', 'jon');
  s.env.SIGNUPS = 'closed';
  await assert.rejects(s.signUp('apple-stranger', 'stranger'), /signups_closed/);
  const back = await s.signUp('apple-jon', 'jon');
  assert.equal(back.user.id, jon.user.id);
});

test('an admin can open Sunday any day; nobody else can, or even sees the flag', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  s.env.DB.sqlite.prepare('INSERT INTO admins (user_id) VALUES (?)').run(jon.user.id);
  s.setNow(WEDNESDAY);
  await refresh(s, jon);
  await refresh(s, maya);
  assert.equal((await s.call('GET', 'v1/feed', { token: jon.token })).status, 200, 'the admin, midweek');
  assert.equal((await s.call('GET', 'v1/feed', { token: maya.token })).body.error.code, 'sunday_closed', 'everyone else waits');

  assert.equal((await s.call('GET', 'v1/me', { token: jon.token })).body.is_admin, true);
  assert.equal('is_admin' in (await s.call('GET', 'v1/me', { token: maya.token })).body, false);
  const patched = await s.call('PATCH', 'v1/me', { token: jon.token, json: { bio: 'Testing' } });
  assert.equal(patched.body.is_admin, true, 'editing the profile keeps it');
  const again = await s.signUp('apple-jon', 'jon');
  assert.equal(again.user.id, jon.user.id);
  const signedIn = await s.call('GET', 'v1/me', { token: again.token });
  assert.equal(signedIn.body.is_admin, true, 'and signing in again');

  // Other people never learn who the admin is.
  const theirView = await s.call('GET', `v1/users/${jon.user.id}/profile`, { token: maya.token });
  assert.equal(theirView.status, 423, 'Maya waits for Sunday');
  s.setNow(new Date('2026-11-01T17:00:00Z'));
  await refresh(s, maya);
  const onSunday = await s.call('GET', `v1/users/${jon.user.id}/profile`, { token: maya.token });
  assert.equal('is_admin' in onSunday.body.user, false);
});

test('sign out signs out this phone; everywhere signs out every phone', async () => {
  const s = await server();
  const phone = await s.signUp('apple-jon', 'jon');
  const ipad = await s.signUp('apple-jon', 'jon');
  const laptop = await s.signUp('apple-jon', 'jon');
  assert.equal((await s.call('POST', 'v1/auth/signout', { token: phone.token })).status, 204);
  assert.equal((await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: phone.refresh } })).status, 401);
  assert.equal((await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: ipad.refresh } })).status, 200, 'the others stay in');
  assert.equal((await s.call('POST', 'v1/auth/signout', { token: laptop.token, json: { everywhere: true } })).status, 204);
  const ipadAfter = await s.call('POST', 'v1/auth/refresh', { json: { refresh_token: ipad.refresh } });
  assert.equal(ipadAfter.status, 401, 'everywhere means every device');
});

test('the privacy page says exactly what the app says, from the one shared file', async () => {
  const policy = JSON.parse(readFileSync(new URL('../../../Shared/privacy.json', import.meta.url), 'utf8'));
  const s = await server();
  const page = await (await s.call('GET', 'privacy', { raw: true })).text();
  const escape = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  assert.ok(page.includes(escape(policy.summary)));
  for (const section of policy.sections) {
    assert.ok(page.includes(`<h2>${escape(section.title)}</h2>`), section.title);
    assert.ok(section.items.length > 0, `${section.title} has something to say`);
    for (const item of section.items) assert.ok(page.includes(`<li>${escape(item)}</li>`), item);
  }
  const text = JSON.stringify(policy);
  assert.doesNotMatch(text, /—/, 'no em-dashes');
  assert.match(policy.updated, /^\d{4}-\d{2}-\d{2}$/);
});
