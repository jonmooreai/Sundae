// Push notifications: which phones hear about what, and when nothing is said.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { server, friends, uploadPhoto } from './harness.mjs';
import { resetPushCache } from '../src/push.js';
import { fromB64url } from '../src/crypto.js';

const PHONE = (letter) => letter.repeat(64);

/** A server with an APNs key of its own and a fake Apple that remembers every notification. */
async function pushServer() {
  resetPushCache();
  const s = await server();
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64').match(/.{1,64}/g).join('\n');
  Object.assign(s.env, { APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----\n`, APNS_KEY_ID: 'KEY1234567', APNS_TEAM_ID: 'TEAM123456' });
  const sent = [];
  let answer = () => new Response('', { status: 200 });
  s.env.FETCH = async (url, init) => {
    sent.push({ url, headers: init.headers, body: JSON.parse(init.body) });
    return answer(url);
  };
  return { s, sent, publicKey: pair.publicKey, answer: (fn) => { answer = fn; } };
}

async function postWeek(s, who, tagged = []) {
  const up = await uploadPhoto(s, who);
  const saved = await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: who.token, json: { caption: '', photos: [{ upload_id: up, tagged_user_ids: tagged.map((u) => u.user.id) }] } });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  return saved.body;
}

const register = (s, who, token, environment) => s.call('PUT', 'v1/me/devices', { token: who.token, json: { token, ...(environment ? { environment } : {}) } });
const titles = (sent) => sent.map((m) => m.body.aps.alert.title);
const phoneOf = (message) => message.url.split('/').pop();

test('a like, a comment, a reply, a mention and a liked comment each reach the right phone once', async () => {
  const { s, sent } = await pushServer();
  const { jon, maya } = await friends(s);
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await s.call('POST', `v1/users/${jon.user.id}/follow`, { token: theo.token });
  await s.call('POST', `v1/me/follow-requests/${theo.user.id}`, { token: jon.token, json: { accept: true } });
  assert.equal((await register(s, jon, PHONE('a'))).status, 204);
  assert.equal((await register(s, maya, PHONE('b'))).status, 204);
  assert.equal((await register(s, theo, PHONE('c'))).status, 204);
  sent.length = 0;
  const week = await postWeek(s, jon);

  // A like reaches the week's poster, once: taking it back and giving it again says nothing.
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: true } });
  assert.deepEqual(titles(sent), ['Maya liked your week']);
  assert.equal(phoneOf(sent[0]), PHONE('a'));
  assert.deepEqual(sent[0].body, { aps: { alert: { title: 'Maya liked your week' }, sound: 'default', 'thread-id': week.id }, kind: 'like', dump_id: week.id });
  assert.equal(sent[0].headers['apns-collapse-id'], `like:${week.id}:${maya.user.id}`);
  // Liked twice over (a tap that landed twice): nothing more. Taken back and given again: a
  // second notification that replaces the first banner rather than adding one.
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: true } });
  assert.equal(sent.length, 1);
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: false } });
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: true } });
  assert.equal(sent.length, 2);
  assert.equal(sent[1].headers['apns-collapse-id'], sent[0].headers['apns-collapse-id']);

  // A comment reaches the poster with its words; the poster's own comment reaches nobody.
  sent.length = 0;
  const comment = (await s.call('POST', `v1/dumps/${week.id}/comments`, { token: maya.token, json: { body: 'What a week' } })).body;
  assert.deepEqual(titles(sent), ['Maya commented on your week']);
  assert.equal(sent[0].body.aps.alert.body, 'What a week');
  assert.equal(sent[0].body.comment_id, comment.id);
  sent.length = 0;
  await s.call('POST', `v1/dumps/${week.id}/comments`, { token: jon.token, json: { body: 'Thanks' } });
  assert.deepEqual(sent, []);

  // A reply reaches the person answered; a reply from the poster to Maya is one notification.
  const reply = (await s.call('POST', `v1/dumps/${week.id}/comments`, { token: jon.token, json: { body: 'Come next time', parent_id: comment.id } })).body;
  assert.deepEqual(titles(sent), ['Jon replied to your comment']);
  assert.equal(phoneOf(sent[0]), PHONE('b'));
  // A reply from a third person to Maya's comment reaches the poster and Maya, each once; a
  // reply to the poster's own comment is one notification, the poster's.
  sent.length = 0;
  await s.call('POST', `v1/dumps/${week.id}/comments`, { token: theo.token, json: { body: 'Me too', parent_id: comment.id } });
  assert.deepEqual(titles(sent).sort(), ['Theo Park commented on your week', 'Theo Park replied to your comment'].sort());
  assert.deepEqual(sent.map(phoneOf).sort(), [PHONE('a'), PHONE('b')]);
  sent.length = 0;
  await s.call('POST', `v1/dumps/${week.id}/comments`, { token: theo.token, json: { body: 'And me', parent_id: reply.id } });
  assert.deepEqual(titles(sent), ['Theo Park commented on your week']);

  // An @ reaches the person named when they can see the week, and nobody twice.
  sent.length = 0;
  await s.call('POST', `v1/dumps/${week.id}/comments`, { token: jon.token, json: { body: '@theo @maya @nobody look' } });
  assert.deepEqual(titles(sent).sort(), ['Jon mentioned you', 'Jon mentioned you']);
  assert.deepEqual(sent.map(phoneOf).sort(), [PHONE('b'), PHONE('c')]);

  // A liked comment reaches its author.
  sent.length = 0;
  await s.call('PUT', `v1/comments/${comment.id}/like`, { token: jon.token });
  assert.deepEqual(titles(sent), ['Jon liked your comment']);
  assert.equal(sent[0].body.aps.alert.body, 'What a week');
});

test('the switches in Settings are honored, for each kind on its own', async () => {
  const { s, sent } = await pushServer();
  const { jon, maya } = await friends(s);
  await register(s, jon, PHONE('a'));
  const week = await postWeek(s, jon);
  await s.call('PUT', 'v1/me/settings', { token: jon.token, json: { notify_likes_and_comments: false } });
  sent.length = 0;
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: true } });
  await s.call('POST', `v1/dumps/${week.id}/comments`, { token: maya.token, json: { body: 'Lovely' } });
  assert.deepEqual(sent, [], 'likes and comments are off');

  // Tags are their own switch, still on.
  await postWeek(s, maya, [jon]);
  assert.deepEqual(titles(sent), ['Maya tagged you in a photo']);
  assert.equal(sent[0].body.aps.alert.body, 'Have a look, and say yes if you would like it in your week.');
});

test('tags: told once a save, in the week or waiting; a yes reaches the tagger only when asked for', async () => {
  const { s, sent } = await pushServer();
  const { jon, maya } = await friends(s);
  await register(s, jon, PHONE('a'));
  await register(s, maya, PHONE('b'));
  await register(s, maya, PHONE('d'), 'sandbox');
  sent.length = 0;

  // Every phone Maya has, once each, however many photos she is in.
  const up1 = await uploadPhoto(s, jon);
  const up2 = await uploadPhoto(s, jon);
  const photos = [{ upload_id: up1, tagged_user_ids: [maya.user.id] }, { upload_id: up2, tagged_user_ids: [maya.user.id] }];
  await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos } });
  assert.deepEqual(titles(sent), ['Jon tagged you in a photo', 'Jon tagged you in a photo']);
  assert.deepEqual(sent.map(phoneOf).sort(), [PHONE('b'), PHONE('d')]);
  assert.ok(sent.find((m) => phoneOf(m) === PHONE('d')).url.startsWith('https://api.sandbox.push.apple.com/'), 'a development build goes through the sandbox');
  assert.ok(sent.find((m) => phoneOf(m) === PHONE('b')).url.startsWith('https://api.push.apple.com/'));

  // Saving the week again with the same tags says nothing more.
  sent.length = 0;
  await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: 'Edited', photos } });
  assert.deepEqual(sent, []);

  // Maya's yes: Jon hears of it only with the switch on, which is off to begin with.
  const requests = (await s.call('GET', 'v1/me/tag-requests', { token: maya.token })).body;
  assert.equal(requests.length, 2);
  await s.call('POST', `v1/tags/${requests[0].tag.id}/respond`, { token: maya.token, json: { approve: true } });
  assert.deepEqual(sent, []);
  await s.call('PUT', 'v1/me/settings', { token: jon.token, json: { notify_tag_approved: true } });
  await s.call('POST', `v1/tags/${requests[1].tag.id}/respond`, { token: maya.token, json: { approve: true } });
  assert.deepEqual(titles(sent), ['Maya said yes to your tag']);
  assert.equal(phoneOf(sent[0]), PHONE('a'));

  // Someone who approves Jon's tags in advance is told the photo is in their week already.
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await s.call('POST', `v1/users/${jon.user.id}/follow`, { token: theo.token });
  await s.call('POST', `v1/me/follow-requests/${theo.user.id}`, { token: jon.token, json: { accept: true } });
  await s.call('PUT', 'v1/me/settings', { token: theo.token, json: { auto_approve_user_ids: [jon.user.id] } });
  await register(s, theo, PHONE('c'));
  sent.length = 0;
  await s.call('PUT', 'v1/me/dumps/2026-10-19', { token: jon.token, json: { caption: '', photos: [{ ...photos[0], tagged_user_ids: [maya.user.id, theo.user.id] }, photos[1]] } });
  assert.deepEqual(titles(sent), ['Jon tagged you in a photo']);
  assert.equal(sent[0].body.aps.alert.body, 'It is in your week now.');
  assert.equal(phoneOf(sent[0]), PHONE('c'));
});

test('follows: a request, a new follower of a public account, and a yes', async () => {
  const { s, sent } = await pushServer();
  const pat = await s.signUp('apple-pat', 'pat', 'Pat Doe');
  const sam = await s.signUp('apple-sam', 'sam', 'Sam Doe');
  const theo = await s.signUp('apple-theo', 'theo', 'Theo Park');
  await register(s, pat, PHONE('a'));
  await register(s, sam, PHONE('b'));
  await register(s, theo, PHONE('c'));
  await s.call('PUT', 'v1/me/settings', { token: pat.token, json: { is_public: true } });
  sent.length = 0;

  await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: theo.token });
  assert.deepEqual(titles(sent), ['Theo Park follows you now']);
  assert.equal(phoneOf(sent[0]), PHONE('a'));
  sent.length = 0;
  await s.call('POST', `v1/users/${sam.user.id}/follow`, { token: theo.token });
  assert.deepEqual(titles(sent), ['Theo Park asked to follow you']);
  assert.equal(sent[0].body.user_id, theo.user.id);
  // Asking again changes nothing and says nothing.
  sent.length = 0;
  await s.call('POST', `v1/users/${sam.user.id}/follow`, { token: theo.token });
  assert.deepEqual(sent, []);
  await s.call('POST', `v1/me/follow-requests/${theo.user.id}`, { token: sam.token, json: { accept: true } });
  assert.deepEqual(titles(sent), ['Sam Doe said yes']);
  assert.equal(phoneOf(sent[0]), PHONE('c'));
  // Saying no, or a yes to a request already answered, is quiet.
  sent.length = 0;
  await s.call('POST', `v1/me/follow-requests/${theo.user.id}`, { token: sam.token, json: { accept: true } });
  assert.deepEqual(sent, []);
  // The follows switch off: nothing, even for a yes.
  await s.call('PUT', 'v1/me/settings', { token: pat.token, json: { notify_follow_requests: false } });
  await s.call('POST', `v1/users/${pat.user.id}/follow`, { token: sam.token });
  assert.deepEqual(sent, []);
});

test('a phone signed out hears nothing more, and one Apple says is gone is forgotten', async () => {
  const { s, sent, answer } = await pushServer();
  const { jon, maya } = await friends(s);
  await register(s, jon, PHONE('a'));
  const week = await postWeek(s, jon);

  // A second session on another phone, signed out by itself: only that phone stops.
  const again = await s.signUp('apple-jon', 'jon', 'Jon');
  await register(s, again, PHONE('e'));
  await s.call('POST', 'v1/auth/signout', { token: again.token });
  sent.length = 0;
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: true } });
  assert.deepEqual(sent.map(phoneOf), [PHONE('a')]);

  // Apple says the token is gone (the app was deleted): it is dropped and never tried again.
  answer(() => new Response(JSON.stringify({ reason: 'Unregistered' }), { status: 410 }));
  sent.length = 0;
  await s.call('POST', `v1/dumps/${week.id}/comments`, { token: maya.token, json: { body: 'Hello' } });
  assert.equal(sent.length, 1);
  sent.length = 0;
  await s.call('POST', `v1/dumps/${week.id}/comments`, { token: maya.token, json: { body: 'Still there?' } });
  assert.deepEqual(sent, []);
  assert.equal(s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM devices').get().n, 0);

  // Signing out everywhere takes every phone with it.
  await register(s, jon, PHONE('a'));
  await register(s, jon, PHONE('f'));
  await s.call('POST', 'v1/auth/signout', { token: jon.token, json: { everywhere: true } });
  assert.equal(s.env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM devices WHERE user_id = ?').get(jon.user.id).n, 0);
});

test('a token that does not look like one is refused; a server without the key stays quiet', async () => {
  const { s, sent } = await pushServer();
  const { jon, maya } = await friends(s);
  assert.equal((await register(s, jon, 'not-a-token')).status, 400);
  assert.equal((await register(s, jon, PHONE('a').toUpperCase())).status, 204, 'upper case is fine');
  delete s.env.APNS_KEY;
  const week = await postWeek(s, jon);
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: true } });
  assert.deepEqual(sent, []);
});

test('what goes to Apple is what Apple asks for', async () => {
  const { s, sent, publicKey } = await pushServer();
  const { jon, maya } = await friends(s);
  await register(s, jon, PHONE('a'));
  const week = await postWeek(s, jon);
  await s.call('PUT', `v1/dumps/${week.id}/like`, { token: maya.token, json: { liked: true } });
  const [message] = sent;
  assert.equal(message.url, `https://api.push.apple.com/3/device/${PHONE('a')}`);
  assert.equal(message.headers['apns-topic'], 'com.jonmooreai.sundae');
  assert.equal(message.headers['apns-push-type'], 'alert');
  assert.equal(message.headers['apns-priority'], '10');
  const [header, claims, signature] = message.headers.authorization.replace(/^bearer /, '').split('.');
  const decode = (part) => JSON.parse(new TextDecoder().decode(fromB64url(part)));
  assert.deepEqual(decode(header), { alg: 'ES256', kid: 'KEY1234567' });
  assert.equal(decode(claims).iss, 'TEAM123456');
  assert.ok(Math.abs(decode(claims).iat - Math.floor(s.now().getTime() / 1000)) < 5);
  const valid = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, publicKey, fromB64url(signature), new TextEncoder().encode(`${header}.${claims}`));
  assert.ok(valid, 'signed with the key');
  // The same provider token serves the next notification; Apple asks for a fresh one hourly, not per message.
  await s.call('POST', `v1/dumps/${week.id}/comments`, { token: maya.token, json: { body: 'Hi' } });
  assert.equal(sent[1].headers.authorization, message.headers.authorization);
});
