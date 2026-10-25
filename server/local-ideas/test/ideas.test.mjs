import { test } from 'node:test';
import assert from 'node:assert/strict';
import { encode, bounds, center, isValidCell } from '../src/geohash.js';
import { generate, seeded } from '../src/ideas.js';
import worker, { isPlausibleDay, isSunday, shardsFor } from '../src/worker.js';

const CELL = '9q8yyk'; // downtown San Francisco
const WEDNESDAY = '2026-10-21';
const SUNDAY = '2026-10-25';

function placesAround(cell) {
  const c = center(cell);
  const spread = [
    ['p1', 'Arizmendi Bakery', 'bakery', 0.001, 0.001],
    ['p2', 'Ritual Coffee', 'cafe', -0.002, 0.001],
    ['p3', 'Dolores Park', 'park', 0.003, -0.002],
    ['p4', 'Dog Eared Books', 'bookstore', 0.0015, -0.0005],
    ['p5', 'Bernal Hill', 'viewpoint', 0.004, 0.003],
    ['p6', 'Far Away Diner', 'diner', 0.5, 0.5], // about 70 km: past twenty miles
    ['p7', 'Nameless', '', 0.001, 0.001], // unknown category: ignored
  ];
  return spread.map(([id, name, category, dLat, dLon]) => ({ id, name, category, lat: c.lat + dLat, lon: c.lon + dLon }));
}

test('geohash matches the reference vector and the app', () => {
  assert.equal(encode(57.64911, 10.40744, 11), 'u4pruydqqvj');
  assert.equal(encode(37.7749, -122.4194, 6), '9q8yyk');
  const b = bounds('9q8yyk');
  assert.ok(b.latLow <= 37.7749 && 37.7749 <= b.latHigh);
  assert.ok(b.lonLow <= -122.4194 && -122.4194 <= b.lonHigh);
  assert.ok(isValidCell('9q8yy') && isValidCell('9q8yyk'));
  assert.ok(!isValidCell('9q8yykz') && !isValidCell('9q8a') && !isValidCell('../x'));
});

test('the seeded generator is stable', () => {
  const a = seeded('9q8yyk:2026-10-21');
  const b = seeded('9q8yyk:2026-10-21');
  assert.equal(a(), b());
  assert.notEqual(seeded('9q8yyk:2026-10-22')(), seeded('9q8yyk:2026-10-21')());
});

test('ideas are deterministic, one per part of the day, and never name the cell', () => {
  const places = placesAround(CELL);
  const first = generate(CELL, WEDNESDAY, places);
  const again = generate(CELL, WEDNESDAY, places);
  assert.deepEqual(first, again);
  assert.equal(first.length, 3);
  assert.deepEqual(first.map((i) => i.time_of_day), ['morning', 'afternoon', 'evening']);
  for (const idea of first) {
    assert.equal(idea.id.includes(CELL), false);
    assert.match(idea.id, /^local:2026-10-21:[0-2]$/);
    assert.ok(idea.place.walk_minutes === null || (idea.place.walk_minutes >= 1 && idea.place.walk_minutes <= 20));
    assert.ok(idea.place.distance_meters >= 0 && idea.place.distance_meters <= 32187);
    assert.ok(!idea.text.includes('{name}') && !idea.reason.includes('{name}'));
    assert.notEqual(idea.place.name, 'Far Away Diner');
    assert.notEqual(idea.place.name, 'Nameless');
  }
  // Three different places, and different categories while enough are available.
  assert.equal(new Set(first.map((i) => i.place.name)).size, 3);
});

test('a different day gives different ideas', () => {
  const places = placesAround(CELL);
  const days = ['2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22', '2026-10-23', '2026-10-24'];
  const texts = new Set(days.map((d) => generate(CELL, d, places).map((i) => i.text).join('|')));
  assert.ok(texts.size >= 2);
});

test('a quiet area gives no ideas rather than invented ones', () => {
  assert.deepEqual(generate(CELL, WEDNESDAY, []), []);
});

test('dates are checked and Sundays are refused', () => {
  const now = new Date('2026-10-21T15:00:00Z');
  assert.ok(isPlausibleDay('2026-10-21', now));
  assert.ok(isPlausibleDay('2026-10-22', now)); // already tomorrow in Auckland
  assert.ok(!isPlausibleDay('2026-10-01', now));
  assert.ok(!isPlausibleDay('2026-13-01', now));
  assert.ok(!isPlausibleDay('2026-02-30', now));
  assert.ok(isSunday(SUNDAY));
  assert.ok(!isSunday(WEDNESDAY));
});

test('shards cover the padded cell, usually one', () => {
  const shards = shardsFor(CELL);
  assert.ok(shards.length >= 1 && shards.length <= 5);
  assert.ok(shards.includes(CELL.slice(0, 4)));
});

function makeEnv(places) {
  return {
    PLACES: {
      async get(key) {
        return key.startsWith('places/') ? { json: async () => places } : null;
      },
    },
  };
}
const ctx = { waitUntil() {} };
globalThis.caches = { default: { async match() { return undefined; }, async put() {} } };

test('the worker answers cacheable JSON with no caller in the key', async () => {
  const today = new Date().toISOString().slice(0, 10);
  const weekday = isSunday(today) ? shiftDay(today, 1) : today;
  const request = new Request(`https://ideas.sundae.test/v1/ideas/local?cell=${CELL}&day=${weekday}`, {
    headers: { authorization: 'Bearer should-be-ignored' },
  });
  const response = await worker.fetch(request, makeEnv(placesAround(CELL)), ctx);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('cache-control'), /public/);
  const ideas = await response.json();
  assert.equal(ideas.length, 3);
});

test('the worker refuses Sundays and bad input', async () => {
  const sunday = nextDay(0);
  let response = await worker.fetch(new Request(`https://x/v1/ideas/local?cell=${CELL}&day=${sunday}`), makeEnv([]), ctx);
  assert.equal(response.status, 423);
  assert.equal((await response.json()).error.code, 'sunday_closed');
  response = await worker.fetch(new Request(`https://x/v1/ideas/local?cell=nope!&day=${WEDNESDAY}`), makeEnv([]), ctx);
  assert.equal(response.status, 400);
  response = await worker.fetch(new Request(`https://x/v1/ideas/local?cell=${CELL}&day=1999-01-01`), makeEnv([]), ctx);
  assert.equal(response.status, 400);
  response = await worker.fetch(new Request('https://x/v1/other'), makeEnv([]), ctx);
  assert.equal(response.status, 404);
});

function shiftDay(day, by) {
  const d = new Date(`${day}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + by);
  return d.toISOString().slice(0, 10);
}

/** The closest date (within tolerance) that falls on the given UTC weekday. */
function nextDay(weekday) {
  const today = new Date().toISOString().slice(0, 10);
  for (const by of [0, 1, -1, 2, -2]) {
    const candidate = shiftDay(today, by);
    if (new Date(`${candidate}T12:00:00Z`).getUTCDay() === weekday) return candidate;
  }
  return today;
}
