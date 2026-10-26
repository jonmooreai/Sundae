// The free plan's edges: 50 D1 queries per request (the harness fails any request over), a
// 500 MB database, and storage that has to be cleaned up. Each test is a heavy but real Sunday.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { server, r2, friends, refresh, uploadPhoto, SUNDAY } from './harness.mjs';
import { cleanUp } from '../src/worker.js';
import { addDays } from '../src/time.js';

const DAY = 86_400_000;

/** Jon and ten friends who follow him, so he can tag any of them. */
async function circle(s, size = 10) {
  const jon = await s.signUp('apple-jon', 'jon', 'Jon');
  const people = [];
  for (let i = 0; i < size; i++) {
    const friend = await s.signUp(`apple-f${i}`, `friend${i}`, `Friend ${i}`);
    await s.call('POST', `v1/users/${jon.user.id}/follow`, { token: friend.token });
    await s.call('POST', `v1/me/follow-requests/${friend.user.id}`, { token: jon.token, json: { accept: true } });
    people.push(friend);
  }
  return { jon, people };
}

const storedKeys = (s) => s.env.DB.sqlite.prepare('SELECT DISTINCT key FROM blob_chunks ORDER BY key').all().map((r) => r.key);

test('a full week, fifteen photos with ten people on each, and editing it, fit the free plan', async (t) => {
  const photos = r2();
  const s = await server({ photos });
  const { jon, people } = await circle(s);
  const ids = people.map((p) => p.user.id);
  const uploads = [];
  for (let i = 0; i < 15; i++) uploads.push(await uploadPhoto(s, jon));
  const first = await s.call('PUT', 'v1/me/dumps/2026-10-19', {
    token: jon.token, json: { caption: 'A big week', photos: uploads.map((u) => ({ upload_id: u, tagged_user_ids: ids })) },
  });
  assert.equal(first.status, 200, JSON.stringify(first.body));
  assert.equal(first.body.photos.length, 15);
  assert.ok(first.body.photos.every((p) => p.tags.length === 10));
  assert.equal(photos.objects.size, 15);

  // Drop five, add five new, reverse the rest, and change who is in each.
  const keep = first.body.photos.slice(5).reverse();
  const added = [];
  for (let i = 0; i < 5; i++) added.push(await uploadPhoto(s, jon));
  const edited = await s.call('PUT', 'v1/me/dumps/2026-10-19', {
    token: jon.token,
    json: {
      caption: 'Edited',
      photos: [
        ...keep.map((p) => ({ id: p.id, tagged_user_ids: ids.slice(0, 5) })),
        ...added.map((u) => ({ upload_id: u, tagged_user_ids: ids.slice(5) })),
      ],
    },
  });
  assert.equal(edited.status, 200, JSON.stringify(edited.body));
  assert.deepEqual(edited.body.photos.slice(0, 10).map((p) => p.id), keep.map((p) => p.id));
  assert.ok(edited.body.photos.every((p) => p.tags.length === 5));
  assert.equal(photos.objects.size, 15, 'the five dropped photos are deleted from storage');

  // Everyone comments twice and likes it; the thread and the feed stay cheap.
  const dump = edited.body;
  for (const friend of people) {
    for (const words of ['So good', 'Again next week']) {
      await s.call('POST', `v1/dumps/${dump.id}/comments`, { token: friend.token, json: { body: words } });
    }
    await s.call('PUT', `v1/dumps/${dump.id}/like`, { token: friend.token, json: { liked: true } });
  }
  const thread = await s.call('GET', `v1/dumps/${dump.id}/comments`, { token: jon.token });
  assert.equal(thread.body.length, 20);
  const feed = await s.call('GET', 'v1/feed', { token: people[0].token });
  assert.equal(feed.body[0].liked_by.length, 10);
  assert.equal(feed.body[0].comment_count, 20);
  const requests = await s.call('GET', 'v1/me/tag-requests', { token: people[0].token });
  assert.equal(requests.body.length, 10);
  const profile = await s.call('GET', `v1/users/${jon.user.id}/profile`, { token: people[9].token });
  assert.equal(profile.body.weeks[0].dump.photos.length, 15);
  t.diagnostic(`busiest request: ${s.busiest().queries} of 50 queries (${s.busiest().path})`);
});

test('deleting an account that posted for two months is a handful of queries and leaves nothing', async (t) => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const mayaUpload = await uploadPhoto(s, maya);
  const mayas = await s.call('PUT', 'v1/me/dumps/2026-10-19', {
    token: maya.token, json: { caption: '', photos: [{ upload_id: mayaUpload, tagged_user_ids: [jon.user.id] }] },
  });
  await s.call('POST', `v1/dumps/${mayas.body.id}/comments`, { token: jon.token, json: { body: 'Love this' } });
  await s.call('PUT', `v1/dumps/${mayas.body.id}/like`, { token: jon.token, json: { liked: true } });

  for (let week = 0; week < 8; week++) {
    if (week) {
      s.setNow(new Date(SUNDAY.getTime() + week * 7 * DAY));
      await refresh(s, jon);
      await refresh(s, maya);
    }
    const uploads = [];
    for (let i = 0; i < 15; i++) uploads.push(await uploadPhoto(s, jon));
    const saved = await s.call('PUT', `v1/me/dumps/${addDays('2026-10-19', week * 7)}`, {
      token: jon.token, json: { caption: `Week ${week}`, photos: uploads.map((u) => ({ upload_id: u, tagged_user_ids: [maya.user.id] })) },
    });
    assert.equal(saved.status, 200, JSON.stringify(saved.body));
    await s.call('POST', `v1/dumps/${saved.body.id}/comments`, { token: maya.token, json: { body: 'Wow' } });
  }
  assert.equal(storedKeys(s).length, 121);

  const gone = await s.call('DELETE', 'v1/me', { token: jon.token });
  assert.equal(gone.status, 204);
  assert.deepEqual(storedKeys(s), [`${mayaUpload}.jpg`], 'only Maya\'s photo is left');
  const count = (sql) => s.env.DB.sqlite.prepare(sql).get().n;
  assert.equal(count('SELECT COUNT(*) AS n FROM dumps'), 1);
  assert.equal(count('SELECT COUNT(*) AS n FROM photos'), 1);
  assert.equal(count('SELECT COUNT(*) AS n FROM tags'), 0, 'his tag on her photo and her tags on his are gone');
  assert.equal(count('SELECT COUNT(*) AS n FROM comments'), 0);
  assert.equal(count('SELECT COUNT(*) AS n FROM likes'), 0);
  assert.equal(count('SELECT COUNT(*) AS n FROM follows'), 0);
  assert.equal((await s.call('GET', 'v1/me', { token: jon.token })).status, 401);
  const feed = await s.call('GET', 'v1/feed', { token: maya.token });
  assert.deepEqual(feed.body.map((d) => d.author.username), ['maya']);
  t.diagnostic(`busiest request: ${s.busiest().queries} of 50 queries (${s.busiest().path})`);
});

test('the daily cleanup clears photos that were never posted and keeps everything in use', async () => {
  const s = await server();
  const { jon } = await friends(s);
  const posted = await uploadPhoto(s, jon);
  const avatar = await uploadPhoto(s, jon);
  const abandoned = await uploadPhoto(s, jon);
  await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: posted }] } });
  await s.call('PATCH', 'v1/me', { token: jon.token, json: { avatar_upload_id: avatar } });
  assert.equal(storedKeys(s).length, 3);

  assert.equal((await cleanUp(s.env, new Date(SUNDAY.getTime() + DAY))).uploads, 0, 'a day is too soon to call it abandoned');
  assert.equal((await cleanUp(s.env, new Date(SUNDAY.getTime() + 3 * DAY))).uploads, 1);
  assert.deepEqual(storedKeys(s), [`${posted}.jpg`, `${avatar}.jpg`].sort());
  assert.ok(!storedKeys(s).includes(`${abandoned}.jpg`));
});

test('a cleanup that cannot reach storage leaves its rows for the next one', async () => {
  const photos = r2();
  const s = await server({ photos });
  const jon = await s.signUp('apple-jon', 'jon');
  await uploadPhoto(s, jon);
  const remove = photos.delete;
  photos.delete = async () => { photos.delete = remove; throw new Error('storage is down'); };
  await assert.rejects(cleanUp(s.env, new Date(SUNDAY.getTime() + 3 * DAY)));
  assert.equal(photos.objects.size, 1);
  assert.equal((await cleanUp(s.env, new Date(SUNDAY.getTime() + 3 * DAY))).uploads, 1, 'the row was still there');
  assert.equal(photos.objects.size, 0);
});

test('one person can upload 150 photos a day, each up to 10 MB', async () => {
  const s = await server();
  const jon = await s.signUp('apple-jon', 'jon');
  const ticket = (size = 1000) => s.call('POST', 'v1/uploads', {
    token: jon.token, json: { content_type: 'image/jpeg', byte_size: size, width: 1, height: 1 },
  });
  assert.equal((await ticket(11 * 1024 * 1024)).status, 400);
  for (let i = 0; i < 150; i++) assert.equal((await ticket()).status, 200);
  assert.equal((await ticket()).body.error.code, 'too_many_uploads');
  s.setNow(new Date(SUNDAY.getTime() + 25 * 3600_000));
  await refresh(s, jon);
  assert.equal((await ticket()).status, 200, 'the count covers the last 24 hours');
});

test('tickets asked for all at once still stop at 150 a day', async () => {
  const s = await server();
  const jon = await s.signUp('apple-jon', 'jon');
  const ask = ['POST', 'v1/uploads', { token: jon.token, json: { content_type: 'image/jpeg', byte_size: 1000, width: 1, height: 1 } }];
  const answers = await s.together(Array.from({ length: 300 }, () => ask));
  assert.equal(answers.filter((r) => r.status === 200).length, 150);
  assert.ok(answers.filter((r) => r.status !== 200).every((r) => r.status === 429 && r.body.error.code === 'too_many_uploads'));
  assert.equal(s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM uploads').get().n, 150);
});

test('saves of one week sent all at once leave it with at most 15 photos', async () => {
  const photos = r2();
  const s = await server({ photos });
  const { jon, maya } = await friends(s);
  const first = await uploadPhoto(s, jon);
  await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: first }] } });
  const saves = [];
  for (let n = 0; n < 4; n++) {
    const uploads = [];
    for (let i = 0; i < 15; i++) uploads.push(await uploadPhoto(s, jon));
    saves.push(['PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: `Save ${n}`, photos: uploads.map((u) => ({ upload_id: u })) } }]);
  }
  const answers = await s.together(saves);
  assert.deepEqual(answers.map((r) => r.status), [200, 200, 200, 200]);
  const posted = s.env.DB.sqlite.prepare('SELECT object_key FROM photos').all().map((r) => r.object_key);
  assert.equal(posted.length, 15);
  assert.equal((await s.call('GET', 'v1/feed', { token: maya.token })).body[0].photos.length, 15);

  // Files of the photos one save dropped from another go with the daily cleanup.
  await cleanUp(s.env, new Date(SUNDAY.getTime() + 3 * DAY));
  assert.deepEqual([...photos.objects.keys()].sort(), posted.sort());
});

test('first saves of a week sent together, as a retry after a dropped connection, all land on one week', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const upload = await uploadPhoto(s, jon);
  const save = ['PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: 'Same week', photos: [{ upload_id: upload }] } }];
  const answers = await s.together([save, save, save]);
  assert.deepEqual(answers.map((r) => r.status), [200, 200, 200], JSON.stringify(answers.map((r) => r.body)));
  const dumps = s.env.DB.sqlite.prepare('SELECT id FROM dumps').all();
  assert.equal(dumps.length, 1);
  assert.ok(answers.every((r) => r.body.id === dumps[0].id && r.body.photos.length === 1));
  assert.equal(s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM photos').get().n, 1);
  assert.equal((await s.call('GET', 'v1/feed', { token: maya.token })).body[0].photos.length, 1);
});

test('thirty comments a person on each week, even sent all at once', async () => {
  const s = await server();
  const { jon, maya } = await friends(s);
  const dump = (await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ upload_id: await uploadPhoto(s, jon) }] } })).body;
  const say = (who, words) => ['POST', `v1/dumps/${dump.id}/comments`, { token: who.token, json: { body: words } }];
  const answers = await s.together(Array.from({ length: 50 }, (_, i) => say(maya, `Comment ${i}`)));
  assert.equal(answers.filter((r) => r.status === 200).length, 30);
  const refused = answers.find((r) => r.status !== 200);
  assert.equal(refused.status, 429);
  assert.equal(refused.body.error.code, 'too_many_comments');

  // The week's author too, one at a time; deleting one makes room for another.
  for (let i = 0; i < 30; i++) assert.equal((await s.call(...say(jon, `Reply ${i}`))).status, 200);
  const over = await s.call(...say(jon, 'One more'));
  assert.equal(over.body.error.code, 'too_many_comments');
  await s.call('DELETE', `v1/comments/${answers.find((r) => r.status === 200).body.id}`, { token: maya.token });
  assert.equal((await s.call(...say(maya, 'Changed my mind'))).status, 200);
  assert.equal((await s.call('GET', `v1/dumps/${dump.id}/comments`, { token: jon.token })).body.length, 60);
});

test('turning R2 on later keeps photos already in the database; new ones go to R2', async () => {
  const s = await server();
  const { jon } = await friends(s);
  const before = await uploadPhoto(s, jon);
  const bucket = r2();
  s.env.PHOTOS = bucket;
  const after = await uploadPhoto(s, jon);
  assert.deepEqual([...bucket.objects.keys()], [`${after}.jpg`]);
  assert.deepEqual(storedKeys(s), [`${before}.jpg`]);

  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', {
    token: jon.token, json: { caption: '', photos: [{ upload_id: before }, { upload_id: after }] },
  });
  for (const photo of saved.body.photos) {
    assert.equal((await s.call('GET', photo.url, { raw: true })).status, 200);
  }
  assert.equal((await s.call('DELETE', `v1/dumps/${saved.body.id}`, { token: jon.token })).status, 204);
  assert.equal(bucket.objects.size, 0);
  assert.deepEqual(storedKeys(s), [], 'deleting clears both places');
});
