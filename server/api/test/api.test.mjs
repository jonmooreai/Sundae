import { test } from 'node:test';
import assert from 'node:assert/strict';
import { server, jpeg, friends, refresh, uploadPhoto, SUNDAY, WEDNESDAY, NEXT_SUNDAY } from './harness.mjs';

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
  const suggested = await s.call('GET', 'v1/users/suggested', { token: jon.token });
  assert.deepEqual(suggested.body.map((u) => u.username), ['theo']);
  const found = await s.call('GET', 'v1/users/search?q=park', { token: jon.token });
  assert.deepEqual(found.body.map((u) => u.username), ['theo']);
  const requested = await s.call('POST', `v1/users/${theo.user.id}/follow`, { token: jon.token });
  assert.equal(requested.body.relationship, 'requested');
  assert.deepEqual((await s.call('GET', 'v1/me/follow-requests', { token: theo.token })).body.map((u) => u.username), ['jon']);
  await s.call('POST', `v1/users/${jon.user.id}/block`, { token: theo.token });
  assert.equal((await s.call('GET', 'v1/me/follow-requests', { token: theo.token })).body.length, 0);
  assert.equal((await s.call('GET', 'v1/users/search?q=theo', { token: jon.token })).body.length, 0);
});

test('deleting an account removes everything of theirs', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const up = await uploadPhoto(s, jon);
  const dump = (await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: up, tagged_user_ids: [maya.user.id] }] } })).body;
  await s.call('POST', `v1/dumps/${dump.id}/comments`, { token: maya.token, json: { body: 'hi' } });
  assert.equal((await s.call('DELETE', 'v1/me', { token: jon.token })).status, 204);
  assert.equal((await s.call('GET', 'v1/me', { token: jon.token })).status, 401);
  assert.equal((await s.call('GET', 'v1/feed', { token: maya.token })).body.length, 0);
  const left = s.env.DB.sqlite.prepare('SELECT (SELECT COUNT(*) FROM photos) AS photos, (SELECT COUNT(*) FROM blob_chunks) AS blobs, (SELECT COUNT(*) FROM tags) AS tags, (SELECT COUNT(*) FROM comments) AS comments').get();
  assert.deepEqual({ ...left }, { photos: 0, blobs: 0, tags: 0, comments: 0 });
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
