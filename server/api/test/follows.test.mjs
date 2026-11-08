// Follows, requests, going public or private, tagged weeks, and the activity list.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { server, friends, refresh, uploadPhoto, SUNDAY, WEDNESDAY } from './harness.mjs';
import { resetSchemaCache } from '../src/schema.js';

async function postWeek(s, who, tagged = []) {
  const up = await uploadPhoto(s, who);
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: who.token, json: { caption: '', photos: [{ upload_id: up, tagged_user_ids: tagged.map((u) => u.user.id) }] } });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  return saved.body;
}

const relationshipTo = async (s, who, other) => (await s.call('GET', `v1/users/${other.user.id}/profile`, { token: who.token })).body.relationship;
const feedIds = async (s, who) => (await s.call('GET', 'v1/feed', { token: who.token })).body.map((d) => d.id);

test('following someone never follows them back, and accepting a request never does either', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  const sam = await s.signUp('apple-sam', 'sam', 'Sam Doe');
  await s.call('PUT', 'v1/me/settings', { token: pat.token, json: { is_public: true } });
  assert.equal((await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: sam.token })).body.relationship, 'following');
  assert.equal(await relationshipTo(s, pat, sam), 'none', 'Pat does not follow Sam back');

  // Sam is private: Pat asks, Sam says yes, and Sam still only follows Pat once.
  assert.equal((await s.call('POST', `v1/users/${sam.user.id}/follow`, { token: pat.token })).body.relationship, 'requested');
  await s.call('POST', `v1/me/follow-requests/${pat.user.id}`, { token: sam.token, json: { accept: true } });
  assert.equal(await relationshipTo(s, pat, sam), 'following');
  assert.equal(await relationshipTo(s, sam, pat), 'following', 'as before, and no more');
  // A request says how the one asked stands with the one asking, for Follow back.
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await s.call('POST', `v1/users/${sam.user.id}/follow`, { token: theo.token });
  await s.call('POST', `v1/users/${theo.user.id}/follow`, { token: sam.token });
  const waiting = (await s.call('GET', 'v1/me/follow-requests', { token: sam.token })).body;
  assert.deepEqual(waiting.map((u) => [u.username, u.relationship]), [['theo', 'requested']]);

  // Search says how the caller stands with everyone found, so a friend never shows Follow.
  const found = async (q, who = sam) => (await s.call('GET', `v1/users/search?q=${q}`, { token: who.token })).body
    .map((u) => [u.username, u.relationship, u.follows_you]);
  assert.deepEqual(await found('pat'), [['pat', 'following', true]]);
  assert.deepEqual(await found('theo'), [['theo', 'requested', false]]);
  assert.deepEqual(await found('sam', pat), [['sam', 'following', true]]);
  const rows = s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM follows WHERE follower_id IN (?, ?) AND followee_id IN (?, ?)')
    .get(pat.user.id, sam.user.id, pat.user.id, sam.user.id).n;
  assert.equal(rows, 2);
});

test('going public says yes to everyone waiting; going private keeps followers and new ones ask', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  const sam = await s.signUp('apple-sam', 'sam', 'Sam Doe');
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  assert.equal((await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: sam.token })).body.relationship, 'requested');

  // Public: Sam's request goes through, the list of requests empties, and Pat's week opens to Sam.
  s.setNow(WEDNESDAY);
  await s.call('PUT', 'v1/me/settings', { token: pat.token, json: { is_public: true } });
  assert.deepEqual((await s.call('GET', 'v1/me/follow-requests', { token: pat.token })).body, []);
  assert.deepEqual((await s.call('GET', 'v1/me/followers', { token: pat.token })).body.map((u) => u.username), ['sam']);
  s.setNow(SUNDAY);
  assert.equal(await relationshipTo(s, sam, pat), 'following');

  // Private again: Sam stays, Theo has to ask, and Theo's request waits.
  await s.call('PUT', 'v1/me/settings', { token: pat.token, json: { is_public: false } });
  const week = await postWeek(s, pat);
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: sam.token })).status, 200);
  assert.equal((await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: theo.token })).body.relationship, 'requested');
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: theo.token })).status, 404);
  assert.deepEqual((await s.call('GET', 'v1/me/follow-requests', { token: pat.token })).body.map((u) => u.username), ['theo']);

  // Asking twice changes nothing.
  assert.equal((await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: theo.token })).body.relationship, 'requested');
  assert.equal((await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: sam.token })).body.relationship, 'following');
});

test('a request left waiting on someone public goes through when asked again, or when the server starts', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  const sam = await s.signUp('apple-sam', 'sam', 'Sam Doe');
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await s.call('PUT', 'v1/me/settings', { token: pat.token, json: { is_public: true } });
  // As an older server could leave it: requests stuck on an account that went public.
  const db = s.env.DB.sqlite;
  for (const who of [sam, theo]) {
    db.prepare(`INSERT INTO follows (follower_id, followee_id, status, created_at) VALUES (?, ?, 'requested', ?)`).run(who.user.id, pat.user.id, SUNDAY.toISOString());
  }
  assert.equal((await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: sam.token })).body.relationship, 'following');

  // Starting on a database from before this lets Theo's through too.
  db.exec(`UPDATE config SET value = '6' WHERE key = 'schema_version'`);
  resetSchemaCache();
  assert.equal(await relationshipTo(s, theo, pat), 'following');
});

test('a tagged week opens to the person in it, and lands in their feed once they say yes', async () => {
  const s = await server();
  const kadi = await s.signUp('apple-kadi', 'kadi', 'Kadi Doe');
  const jon = await s.signUp('apple-jon', 'jon', 'Jon Doe');
  const stranger = await s.signUp('apple-x', 'stranger');
  // Kadi follows Jon, so she can tag him; Jon does not follow private Kadi.
  await s.call('POST', `v1/users/${jon.user.id}/follow`, { token: kadi.token });
  await s.call('POST', `v1/me/follow-requests/${kadi.user.id}`, { token: jon.token, json: { accept: true } });
  const week = await postWeek(s, kadi, [jon]);

  // Waiting on Jon: he can look at the week before he answers, but it is not in his feed yet.
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: jon.token })).status, 200);
  assert.deepEqual(await feedIds(s, jon), []);
  const [request] = (await s.call('GET', 'v1/me/tag-requests', { token: jon.token })).body;
  await s.call('POST', `v1/tags/${request.tag.id}/respond`, { token: jon.token, json: { approve: true } });

  // Yes: it opens, it is in his feed, and he can like it and say something.
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: jon.token })).status, 200);
  assert.deepEqual(await feedIds(s, jon), [week.id]);
  assert.equal((await s.call('GET', `v1/dumps/${week.id}/comments`, { token: jon.token })).status, 200);
  assert.equal((await s.call('PUT', `v1/dumps/${week.id}/like`, { token: jon.token, json: { liked: true } })).status, 200);
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: stranger.token })).status, 404, 'nobody else');

  // Taken off his profile, the week closes to him again.
  await s.call('DELETE', `v1/tags/${request.tag.id}`, { token: jon.token });
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: jon.token })).status, 404);
  assert.deepEqual(await feedIds(s, jon), []);
});

test('a tag turned down, or from someone blocked, opens nothing', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  // Maya stops following Jon, so only the tag could open his week to her.
  await s.call('DELETE', `v1/users/${jon.user.id}/follow`, { token: maya.token });
  const week = await postWeek(s, jon, [maya]);
  const [request] = (await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body;
  await s.call('POST', `v1/tags/${request.tag.id}/respond`, { token: maya.token, json: { approve: false } });
  assert.equal((await s.call('GET', `v1/dumps/${week.id}`, { token: maya.token })).status, 404);
  assert.deepEqual(await feedIds(s, maya), []);

  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  await s.call('POST', `v1/users/${jon.user.id}/follow`, { token: pat.token });
  await s.call('POST', `v1/me/follow-requests/${pat.user.id}`, { token: jon.token, json: { accept: true } });
  const tagged = await postWeek(s, jon, [pat]);
  const [patRequest] = (await s.call('GET', 'v1/me/tag-requests', { token: pat.token })).body;
  await s.call('POST', `v1/tags/${patRequest.tag.id}/respond`, { token: pat.token, json: { approve: true } });
  s.env.DB.sqlite.prepare('INSERT INTO blocks (blocker_id, blocked_id) VALUES (?, ?)').run(jon.user.id, pat.user.id);
  assert.equal((await s.call('GET', `v1/dumps/${tagged.id}`, { token: pat.token })).status, 404);
  assert.deepEqual(await feedIds(s, pat), []);
});

test('activity: likes, comments, replies, mentions, follows and tags, newest first, from nobody blocked', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const jo = await s.signUp('apple-jo', 'jo', 'Jo Doe');
  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  const tick = (() => { let t = SUNDAY.getTime(); return () => s.setNow(new Date((t += 60_000))); })();

  // Jon posts and tags Maya; Maya says yes, likes it, comments, and mentions Jo, who is not Jon.
  const week = await postWeek(s, jon, [maya]);
  tick();
  const [request] = (await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body;
  await s.call('POST', `v1/tags/${request.tag.id}/respond`, { token: maya.token, json: { approve: true } });
  tick();
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: true } });
  tick();
  const comment = (await s.call('POST', `v1/dumps/${week.id}/comments`, { token: maya.token, json: { body: 'Love this, @jon' } })).body;
  tick();
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: jon.token, json: { liked: true } });

  // On Maya's week: Jon comments, Maya replies to him and mentions him, and likes his comment.
  const mayaWeek = await postWeek(s, maya);
  tick();
  const jonsComment = (await s.call('POST', `v1/dumps/${mayaWeek.id}/comments`, { token: jon.token, json: { body: 'So good' } })).body;
  tick();
  await s.call('POST', `v1/dumps/${mayaWeek.id}/comments`, { token: maya.token, json: { body: 'Thank you', parent_id: jonsComment.id } });
  tick();
  await s.call('POST', `v1/dumps/${mayaWeek.id}/comments`, { token: maya.token, json: { body: 'and @jon.x is not you, but @JON is' } });
  tick();
  await s.call('PUT', `v1/comments/${jonsComment.id}/like`, { token: maya.token });

  // Pat follows public Jon; Jo follows Jon while he is private, and Jon says yes.
  await s.call('PUT', 'v1/me/settings', { token: jon.token, json: { is_public: true } });
  tick();
  await s.call('POST', `v1/users/${jon.user.id}/follow`, { token: pat.token });

  const activity = (await s.call('GET', 'v1/me/activity', { token: jon.token })).body;
  assert.deepEqual(activity.map((a) => [a.kind, a.actor.username]), [
    ['follow', 'pat'],
    ['comment_like', 'maya'],
    ['mention', 'maya'],
    ['reply', 'maya'],
    ['comment', 'maya'],
    ['like', 'maya'],
    ['tag_approved', 'maya'],
    ['follow_accepted', 'maya'],
  ]);
  const byKind = Object.fromEntries(activity.map((a) => [a.kind, a]));
  assert.equal(byKind.comment.comment_body, 'Love this, @jon');
  assert.equal(byKind.comment.comment_id, comment.id);
  assert.equal(byKind.reply.comment_body, 'Thank you');
  assert.equal(byKind.like.dump_id, week.id);
  assert.equal(byKind.like.week_start, '2026-10-19');
  assert.ok(byKind.like.photo_url.includes('/v1/media/'));
  assert.equal(byKind.follow.relationship, 'none', 'Jon has not followed Pat');
  assert.equal(byKind.like.relationship, 'following');
  assert.equal(new Set(activity.map((a) => a.id)).size, activity.length, 'each has its own id');

  // Jo's request, accepted, shows on Jo's side as accepted, and not as a new follower on Jon's.
  await s.call('PUT', 'v1/me/settings', { token: jon.token, json: { is_public: false } });
  tick();
  await s.call('POST', `v1/users/${jon.user.id}/follow`, { token: jo.token });
  tick();
  await s.call('POST', `v1/me/follow-requests/${jo.user.id}`, { token: jon.token, json: { accept: true } });
  const jos = (await s.call('GET', 'v1/me/activity', { token: jo.token })).body;
  assert.deepEqual(jos.map((a) => [a.kind, a.actor.username]), [['follow_accepted', 'jon']]);
  assert.ok(!(await s.call('GET', 'v1/me/activity', { token: jon.token })).body.some((a) => a.actor.username === 'jo'));
  assert.deepEqual((await s.call('GET', 'v1/me/activity', { token: pat.token })).body, [], 'nothing for Pat');

  // Blocking Maya takes everything of hers out; a month on, the rest has aged out too.
  await s.call('POST', `v1/users/${maya.user.id}/block`, { token: jon.token });
  assert.deepEqual((await s.call('GET', 'v1/me/activity', { token: jon.token })).body.map((a) => a.actor.username), ['pat']);
  for (const days of [20, 40]) {
    s.setNow(new Date(WEDNESDAY.getTime() + days * 86_400_000));
    await refresh(s, jon);
  }
  assert.deepEqual((await s.call('GET', 'v1/me/activity', { token: jon.token })).body, []);
});

test('activity is every day, and only about weeks that can still be opened', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const mayaWeek = await postWeek(s, maya);
  const jonsComment = (await s.call('POST', `v1/dumps/${mayaWeek.id}/comments`, { token: jon.token, json: { body: 'So good' } })).body;
  await s.call('PUT', `v1/comments/${jonsComment.id}/like`, { token: maya.token });
  s.setNow(WEDNESDAY);
  const kinds = async () => (await s.call('GET', 'v1/me/activity', { token: jon.token })).body.map((a) => a.kind);
  assert.deepEqual(await kinds(), ['comment_like', 'follow_accepted']);
  // Maya removes Jon as a follower: her week, and what happened on it, are closed to him now.
  await s.call('DELETE', `v1/me/followers/${jon.user.id}`, { token: maya.token });
  assert.deepEqual(await kinds(), []);
});

test('an edited photo, sent as a new upload in place of the old one, keeps its tags and their answers', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const week = await postWeek(s, jon, [maya]);
  const [request] = (await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body;
  await s.call('POST', `v1/tags/${request.tag.id}/respond`, { token: maya.token, json: { approve: true } });

  const edited = await uploadPhoto(s, jon);
  const old = week.photos[0];
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [
    { upload_id: edited, replaces: old.id, tagged_user_ids: [maya.user.id] },
  ] } });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.equal(saved.body.photos.length, 1);
  assert.notEqual(saved.body.photos[0].id, old.id, 'a new photo');
  assert.deepEqual(saved.body.photos[0].tags.map((t) => [t.tagged_user.username, t.status]), [['maya', 'approved']]);
  assert.deepEqual((await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body, [], 'Maya is not asked again');
  const profile = await s.call('GET', `v1/users/${maya.user.id}/profile`, { token: maya.token });
  assert.equal(profile.body.weeks[0].tagged[0].photo.id, saved.body.photos[0].id, 'and the new photo is on her week');

  // Untagged in the edit, the tag goes; a photo that replaces nothing tags afresh.
  const again = await uploadPhoto(s, jon);
  const untagged = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [
    { upload_id: again, replaces: saved.body.photos[0].id, tagged_user_ids: [] },
  ] } });
  assert.deepEqual(untagged.body.photos[0].tags, []);
  const fresh = await uploadPhoto(s, jon);
  const retagged = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [
    { upload_id: fresh, replaces: 'p_not_in_this_week', tagged_user_ids: [maya.user.id] },
  ] } });
  assert.deepEqual(retagged.body.photos[0].tags.map((t) => t.status), ['pending']);
});
